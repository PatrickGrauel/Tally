import Foundation
import AppKit

/// File-based export / import of the notes collection. Each note
/// becomes a single `.md` file inside the chosen folder, with a YAML
/// frontmatter block carrying the metadata that doesn't survive plain
/// markdown (`id`, `createdAt`, `archived`, `trashed`). Referenced
/// image assets are copied into a sibling `assets/` directory.
///
/// Use cases:
///   1. **Backup** — periodically export to a folder you trust.
///      Putting the folder inside `~/Library/Mobile Documents/com~apple~CloudDocs/`
///      (i.e. iCloud Drive) gets you cross-Mac sync for free, without
///      needing the iCloud-container infrastructure that CloudKit
///      requires.
///   2. **Migration** — bring an existing Bear / Obsidian markdown
///      vault into Vektor. The importer is lenient: any `.md` file
///      without frontmatter is imported as a fresh note keyed by a
///      new UUID.
enum NotesExporter {

    /// Export every active and archived note (skips trash) to
    /// `folder`. Returns the count of files written. Asset files
    /// referenced by note bodies are also copied into `folder/assets/`.
    /// Re-running over the same folder overwrites — last write wins.
    @MainActor
    static func exportAll(from store: NotesStore, to folder: URL) throws -> Int {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let assetsDir = folder.appendingPathComponent("assets", isDirectory: true)
        try fm.createDirectory(at: assetsDir, withIntermediateDirectories: true)

        let notesToExport = store.saved.filter { !$0.isTrashed }
        var assetsToCopy: Set<String> = []
        for note in notesToExport {
            let mdURL = folder.appendingPathComponent(filename(for: note),
                                                      isDirectory: false)
            let payload = serialize(note: note)
            try payload.write(to: mdURL, atomically: true, encoding: .utf8)
            for name in NotesAssets.referencedAssetNames(in: note.body) {
                assetsToCopy.insert(name)
            }
        }
        if let srcAssets = try? NotesAssets.directory() {
            for name in assetsToCopy {
                let src = srcAssets.appendingPathComponent(name)
                guard fm.fileExists(atPath: src.path) else { continue }
                let dst = assetsDir.appendingPathComponent(name)
                if fm.fileExists(atPath: dst.path) {
                    try? fm.removeItem(at: dst)
                }
                try? fm.copyItem(at: src, to: dst)
            }
        }
        return notesToExport.count
    }

    /// File-safe name derived from the note's first-line title. Falls
    /// back to a UUID-based name when the title would be empty or
    /// collides with another note's title.
    static func filename(for note: Note) -> String {
        let raw = note.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        let base = raw.isEmpty ? note.id.uuidString : raw
        // Append a short id suffix so two notes with the same first
        // line don't overwrite each other on export.
        let suffix = String(note.id.uuidString.prefix(8))
        return "\(base) [\(suffix)].md"
    }

    /// Serialise a note as YAML-frontmatter + markdown body.
    static func serialize(note: Note) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var lines: [String] = [
            "---",
            "id: \(note.id.uuidString)",
            "createdAt: \(iso.string(from: note.createdAt))",
            "modifiedAt: \(iso.string(from: note.modifiedAt))",
        ]
        if note.isArchived { lines.append("archived: true") }
        if note.isTrashed  { lines.append("trashed: true") }
        if note.isPinned   { lines.append("pinned: true") }
        let tags = note.tags
        if !tags.isEmpty {
            lines.append("tags: [\(tags.map { "\"\($0)\"" }.joined(separator: ", "))]")
        }
        lines.append("---")
        lines.append("")
        lines.append(note.body)
        return lines.joined(separator: "\n")
    }
}

enum NotesImporter {

    /// Scan `folder` (non-recursive) for `.md` files. For each:
    ///   - If a YAML frontmatter `id:` is present and matches an
    ///     existing note in the store, the import is treated as an
    ///     **update** of that note (last-write-wins by modifiedAt).
    ///   - Otherwise, a fresh note is created with a new UUID.
    /// Referenced asset filenames in the body are looked up in
    /// `folder/assets/` and copied into the live assets directory.
    ///
    /// Returns `(imported: Int, updated: Int)`.
    @MainActor
    static func importAll(from folder: URL,
                          into store: NotesStore) throws -> (imported: Int, updated: Int) {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(at: folder,
                                                   includingPropertiesForKeys: nil)) ?? []
        var imported = 0
        var updated = 0
        for url in entries where url.pathExtension.lowercased() == "md" {
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let parsed = parse(text)
            // Resolve any referenced assets out of folder/assets/ into
            // the live assets dir so the body's `notes-asset://` URLs
            // still resolve after import.
            copyAssets(referencedBy: parsed.body, from: folder.appendingPathComponent("assets"))
            if let existing = store.saved.first(where: { $0.id == parsed.id }) {
                // Last-write-wins on modifiedAt.
                if parsed.modifiedAt > existing.modifiedAt {
                    var copy = existing
                    copy.body = parsed.body
                    copy.modifiedAt = parsed.modifiedAt
                    copy.isArchived = parsed.isArchived
                    copy.isTrashed  = parsed.isTrashed
                    store.add(copy)
                    updated += 1
                }
            } else {
                let note = Note(id: parsed.id,
                                body: parsed.body,
                                createdAt: parsed.createdAt,
                                modifiedAt: parsed.modifiedAt,
                                isArchived: parsed.isArchived,
                                isTrashed: parsed.isTrashed)
                store.add(note)
                imported += 1
            }
        }
        return (imported, updated)
    }

    private struct ParsedNote {
        let id: UUID
        let body: String
        let createdAt: Date
        let modifiedAt: Date
        let isArchived: Bool
        let isTrashed: Bool
    }

    /// Parse a markdown file with optional YAML frontmatter. Lenient —
    /// every metadata field is optional; missing fields fall back to
    /// sensible defaults (fresh UUID, file mtime).
    private static func parse(_ text: String) -> ParsedNote {
        // Detect frontmatter: file must start with `---\n` and contain
        // a closing `\n---\n` (or `\n---` at end of file).
        var body = text
        var frontMatter: [String: String] = [:]
        if text.hasPrefix("---\n") {
            let afterOpener = text.index(text.startIndex, offsetBy: 4)
            let remaining = String(text[afterOpener...])
            if let closingRange = remaining.range(of: "\n---") {
                let fmText = String(remaining[..<closingRange.lowerBound])
                for line in fmText.split(separator: "\n", omittingEmptySubsequences: true) {
                    if let colon = line.firstIndex(of: ":") {
                        let key = line[..<colon].trimmingCharacters(in: .whitespaces)
                        let value = line[line.index(after: colon)...]
                            .trimmingCharacters(in: .whitespaces)
                        frontMatter[String(key)] = String(value)
                    }
                }
                // Body starts after the closing `---` line.
                let afterClose = remaining.index(closingRange.upperBound, offsetBy: 0)
                // Skip the newline immediately after `---` if present.
                body = String(remaining[afterClose...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFallback = ISO8601DateFormatter()
        isoFallback.formatOptions = [.withInternetDateTime]

        let now = Date()
        let id = frontMatter["id"].flatMap(UUID.init(uuidString:)) ?? UUID()
        let createdAt = frontMatter["createdAt"]
            .flatMap { iso.date(from: $0) ?? isoFallback.date(from: $0) } ?? now
        let modifiedAt = frontMatter["modifiedAt"]
            .flatMap { iso.date(from: $0) ?? isoFallback.date(from: $0) } ?? now
        let archived = (frontMatter["archived"] ?? "").lowercased() == "true"
        let trashed  = (frontMatter["trashed"]  ?? "").lowercased() == "true"
        return ParsedNote(id: id, body: body,
                          createdAt: createdAt, modifiedAt: modifiedAt,
                          isArchived: archived, isTrashed: trashed)
    }

    /// Walk an imported body for `notes-asset://name` references and
    /// copy each name from `assetsFolder` into the live assets dir,
    /// skipping anything that's already present so re-imports don't
    /// re-shuttle the same files.
    private static func copyAssets(referencedBy body: String, from assetsFolder: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: assetsFolder.path),
              let dst = try? NotesAssets.directory() else { return }
        for name in NotesAssets.referencedAssetNames(in: body) {
            let src = assetsFolder.appendingPathComponent(name)
            guard fm.fileExists(atPath: src.path) else { continue }
            let target = dst.appendingPathComponent(name)
            if fm.fileExists(atPath: target.path) { continue }
            try? fm.copyItem(at: src, to: target)
        }
    }
}
