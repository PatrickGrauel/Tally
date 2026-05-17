import Foundation
import AppKit

/// Auto-backup of the notes collection to a user-chosen folder.
///
/// Two-way sync via the filesystem:
///   - On every note save, write that note's `.md` file into the
///     backup folder (incremental, fast — no full re-export).
///   - On app launch, scan the backup folder and import any `.md`
///     files whose `modifiedAt` is newer than the local copy. This is
///     how cross-Mac sync works when the backup folder lives inside
///     `~/Library/Mobile Documents/com~apple~CloudDocs/` (iCloud
///     Drive) — macOS handles the file replication, we handle the
///     merge.
///
/// Folder access is persisted as a **security-scoped bookmark** in
/// UserDefaults, which lets a sandboxed app keep its grant across
/// launches. Without the bookmark the sandbox would forget the folder
/// every time and prompt the user again.
@MainActor
final class NotesBackupService: ObservableObject {

    static let shared = NotesBackupService()

    @Published private(set) var folderURL: URL?
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var lastError: String?

    private static let bookmarkKey = "tally.notes.backupBookmark"
    private weak var store: NotesStore?

    private init() {
        // Resolve any persisted bookmark on init so the published
        // folderURL is correct before the first SwiftUI render.
        if let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data,
                                  options: [.withSecurityScope],
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &stale) {
                _ = url.startAccessingSecurityScopedResource()
                self.folderURL = url
                if stale { rebookmarkIfNeeded(url) }
            }
        }
    }

    /// Hook called once the NotesStore is constructed so the backup
    /// service knows where to push exports and pull imports from.
    /// We hold a weak reference to avoid a retain cycle.
    func attach(store: NotesStore) {
        self.store = store
        // On launch, do one full import pass — bringing in any
        // changes made on another Mac while this Mac was offline.
        if folderURL != nil {
            scanForRemoteChanges()
        }
    }

    // MARK: - Folder configuration

    /// Open NSOpenPanel for the user to pick a backup folder, store
    /// a security-scoped bookmark, do an immediate full export, and
    /// pull any remote changes already in the folder.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Enable backup"
        panel.message = "Choose a folder for automatic backups. Tip: put it inside iCloud Drive (Mobile Documents) for cross-Mac sync."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try url.bookmarkData(options: [.withSecurityScope],
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil)
            UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
            stopAccessing()
            _ = url.startAccessingSecurityScopedResource()
            self.folderURL = url
            self.lastError = nil
            // Immediate full export so a fresh setup populates the
            // folder right away, then scan for any pre-existing files.
            if let store {
                _ = try? NotesExporter.exportAll(from: store, to: url)
                scanForRemoteChanges()
            }
            lastSyncAt = Date()
        } catch {
            lastError = "Could not save folder bookmark: \(error.localizedDescription)"
        }
    }

    func disable() {
        stopAccessing()
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        folderURL = nil
        lastSyncAt = nil
        lastError = nil
    }

    private func stopAccessing() {
        folderURL?.stopAccessingSecurityScopedResource()
    }

    private func rebookmarkIfNeeded(_ url: URL) {
        // The bookmark went stale (folder moved/renamed). Recreate it
        // so future launches don't lose access.
        if let data = try? url.bookmarkData(options: [.withSecurityScope],
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        }
    }

    // MARK: - Write path

    /// Called from NotesStore on every save. Exports the single
    /// changed note (and any of its referenced assets) into the
    /// backup folder. Best-effort — IO errors set `lastError` but
    /// don't propagate.
    func backupChanged(note: Note) {
        guard let folder = folderURL else { return }
        do {
            try NotesExporter.exportNote(note, to: folder)
            lastSyncAt = Date()
            lastError = nil
        } catch {
            lastError = "Backup failed: \(error.localizedDescription)"
        }
    }

    /// Called from NotesStore.remove. Deletes the corresponding
    /// .md file from the backup folder if present so the on-disk
    /// state matches the live store.
    func backupRemoved(noteID: UUID) {
        guard let folder = folderURL else { return }
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(at: folder,
                                                   includingPropertiesForKeys: nil)) ?? []
        // Find any .md whose name embeds this UUID's first-8 suffix
        // (the convention NotesExporter uses). Safer than matching the
        // title because titles change.
        let suffix = "[\(noteID.uuidString.prefix(8))]"
        for url in entries where url.pathExtension.lowercased() == "md" {
            if url.lastPathComponent.contains(suffix) {
                try? fm.removeItem(at: url)
            }
        }
        lastSyncAt = Date()
    }

    // MARK: - Read path

    /// Walk the backup folder and import any file whose `modifiedAt`
    /// is newer than the live copy. Called on launch + after the user
    /// re-enables backup. We don't poll periodically yet — relies on
    /// the user re-opening the app to pick up remote edits.
    func scanForRemoteChanges() {
        guard let store, let folder = folderURL else { return }
        do {
            _ = try NotesImporter.importAll(from: folder, into: store)
            lastSyncAt = Date()
            lastError = nil
        } catch {
            lastError = "Import scan failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - NotesExporter extension: single-note write

extension NotesExporter {

    /// Write a single note's `.md` file into the backup folder.
    /// Used by the auto-backup pipeline to avoid re-exporting the
    /// whole collection on every save.
    @MainActor
    static func exportNote(_ note: Note, to folder: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let assetsDir = folder.appendingPathComponent("assets", isDirectory: true)
        try fm.createDirectory(at: assetsDir, withIntermediateDirectories: true)

        // Remove any older `.md` for this note id (the filename might
        // have changed because the title changed).
        let suffix = "[\(note.id.uuidString.prefix(8))]"
        let entries = (try? fm.contentsOfDirectory(at: folder,
                                                   includingPropertiesForKeys: nil)) ?? []
        for url in entries where url.pathExtension.lowercased() == "md"
            && url.lastPathComponent.contains(suffix)
            && url.lastPathComponent != filename(for: note) {
            try? fm.removeItem(at: url)
        }

        let mdURL = folder.appendingPathComponent(filename(for: note),
                                                  isDirectory: false)
        try serialize(note: note).write(to: mdURL, atomically: true, encoding: .utf8)

        // Copy referenced assets (only if missing — they're content-
        // addressed UUID names so a name match means the bytes match).
        if let srcAssets = try? NotesAssets.directory() {
            for name in NotesAssets.referencedAssetNames(in: note.body) {
                let src = srcAssets.appendingPathComponent(name)
                guard fm.fileExists(atPath: src.path) else { continue }
                let dst = assetsDir.appendingPathComponent(name)
                if !fm.fileExists(atPath: dst.path) {
                    try? fm.copyItem(at: src, to: dst)
                }
            }
        }
    }

}
