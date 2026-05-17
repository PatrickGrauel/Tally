import Foundation
import SwiftUI

/// SQLite-backed store of the user's notes. Replaces the previous
/// `PersistentStore<Note>` typealias so we can:
///   1. Scale past the ~few-hundred-note point where re-encoding the
///      whole collection on every keystroke starts to bite.
///   2. Use FTS5 for full-text search instead of substring-scanning
///      every body on every keystroke.
///
/// The store still exposes an in-memory `@Published saved: [Note]`
/// snapshot so existing call sites (`NotesPane`, `NotesList`,
/// `NotesSidebar`) keep working unchanged. The cache is the source of
/// truth for the current frame's render; the database is the source of
/// truth across launches. Every write is write-through to the DB and
/// updates the cache in one step.
@MainActor
final class NotesStore: ObservableObject {
    @Published private(set) var saved: [Note] = []

    private let database: NotesDatabase

    static func notes() -> NotesStore {
        NotesStore(database: .shared)
    }

    init(database: NotesDatabase) {
        self.database = database
        // One-time migration from the legacy UserDefaults JSON blob.
        // Idempotent — skips work once the migration flag is set.
        database.importLegacyUserDefaultsIfNeeded()
        reload()
    }

    // MARK: - Writes

    /// Insert-or-update a note. Equivalent semantics to the old
    /// PersistentStore<Note>.add: keying by id, last-writer-wins. We
    /// bump `modifiedAt` to "now" on existing-row replacement so the
    /// list-by-modified sort reflects the latest edit, while keeping
    /// the original `createdAt`.
    func add(_ item: Note) {
        var toSave = item
        if let existing = saved.first(where: { $0.id == item.id }) {
            toSave.createdAt = existing.createdAt
            toSave.modifiedAt = Date()
        }
        do {
            try database.save(toSave)
            if let idx = saved.firstIndex(where: { $0.id == toSave.id }) {
                saved[idx] = toSave
            } else {
                saved.append(toSave)
            }
        } catch {
            // Persist failure is non-fatal — keep the cache change so
            // the user's typing isn't lost mid-session.
            print("NotesStore.add failed: \(error)")
        }
    }

    func remove(_ id: UUID) {
        do {
            try database.delete(id: id)
            saved.removeAll { $0.id == id }
        } catch {
            print("NotesStore.remove failed: \(error)")
        }
    }

    // MARK: - Reads

    /// FTS5-driven search. Returns the ids of notes whose body matches
    /// the multi-word, prefix-matched query, in relevance order.
    /// NotesList feeds these ids into the regular filter pipeline so
    /// the sidebar's archive/trash/tag buckets still apply.
    func searchIDs(matching query: String) -> Set<UUID> {
        do {
            return Set(try database.searchNoteIDs(matching: query))
        } catch {
            print("NotesStore.search failed: \(error)")
            return []
        }
    }

    /// Force-refresh the in-memory cache from disk. Cheap (single
    /// SELECT). Reserved for after an out-of-band write (eventual
    /// iCloud sync).
    func reload() {
        do {
            saved = try database.allNotes()
        } catch {
            print("NotesStore.reload failed: \(error)")
            saved = []
        }
    }

    // MARK: - Convenience accessors

    /// Active notes (not trashed), sorted by most recently modified.
    /// Same API the previous PersistentStore extension provided.
    var activeNotes: [Note] {
        saved
            .filter { !$0.isTrashed }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    var trashedNotes: [Note] {
        saved
            .filter { $0.isTrashed }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    var archivedNotes: [Note] {
        saved
            .filter { $0.isArchived && !$0.isTrashed }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }
}
