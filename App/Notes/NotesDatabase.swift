import Foundation
import GRDB

/// SQLite-backed persistence for notes. Replaces the previous
/// UserDefaults JSON storage so the notes pane can scale past a few
/// hundred entries without re-encoding the entire collection on every
/// keystroke, AND can answer full-text search queries instantly via
/// FTS5 instead of substring-scanning every body on every keystroke.
///
/// One database file lives in the app's sandboxed Application Support
/// container next to the assets directory. The file is keyed by the
/// app's bundle identifier (`app.vektor.Vektor`), so a future bundle-id
/// change would orphan the old DB.
///
/// Schema is versioned via GRDB's `DatabaseMigrator`. The initial
/// migration creates `notes` plus an FTS5 virtual table (`notes_fts`)
/// kept in sync via triggers. The FTS index is `external content` —
/// it stores only the FTS metadata, not a second copy of the body —
/// so the database stays compact.
final class NotesDatabase {

    static let shared = NotesDatabase()

    /// On-disk location of the database. Public so tests and
    /// migrations can target it precisely.
    static let url: URL = {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory,
                                in: .userDomainMask,
                                appropriateFor: nil,
                                create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("Vektor", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("notes.sqlite")
    }()

    let dbQueue: DatabaseQueue

    private init() {
        do {
            var configuration = Configuration()
            // Foreign-key enforcement is on by default in modern GRDB,
            // but we make it explicit so a future schema change with
            // joined tables doesn't silently drop integrity.
            configuration.foreignKeysEnabled = true
            self.dbQueue = try DatabaseQueue(path: Self.url.path,
                                             configuration: configuration)
            try Self.migrator.migrate(self.dbQueue)
        } catch {
            // The database is a hard dependency for the notes pane —
            // if it can't be opened we're effectively offline for
            // notes. Crash early in dev; ship a friendlier error
            // surface once we have a place to render it.
            fatalError("NotesDatabase init failed: \(error)")
        }
    }

    // MARK: - Schema

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "notes") { t in
                t.column("id", .text).primaryKey()      // UUID string
                t.column("body", .text).notNull()
                t.column("createdAt", .double).notNull()
                t.column("modifiedAt", .double).notNull()
                t.column("isArchived", .integer).notNull().defaults(to: 0)
                t.column("isTrashed", .integer).notNull().defaults(to: 0)
            }

            // External-content FTS5 index — the index stores token
            // positions + offsets but not the source text itself. The
            // triggers below keep it in sync with `notes.body`.
            try db.execute(sql: """
                CREATE VIRTUAL TABLE notes_fts USING fts5(
                    body,
                    content='notes',
                    content_rowid='rowid'
                )
            """)
            try db.execute(sql: """
                CREATE TRIGGER notes_ai AFTER INSERT ON notes BEGIN
                    INSERT INTO notes_fts(rowid, body) VALUES (new.rowid, new.body);
                END
            """)
            try db.execute(sql: """
                CREATE TRIGGER notes_ad AFTER DELETE ON notes BEGIN
                    INSERT INTO notes_fts(notes_fts, rowid, body)
                    VALUES('delete', old.rowid, old.body);
                END
            """)
            try db.execute(sql: """
                CREATE TRIGGER notes_au AFTER UPDATE ON notes BEGIN
                    INSERT INTO notes_fts(notes_fts, rowid, body)
                    VALUES('delete', old.rowid, old.body);
                    INSERT INTO notes_fts(rowid, body) VALUES (new.rowid, new.body);
                END
            """)
        }

        // v2: pinned notes. Default 0 so all existing notes start
        // un-pinned; the user opts in per-note via the list context
        // menu.
        migrator.registerMigration("v2-isPinned") { db in
            try db.alter(table: "notes") { t in
                t.add(column: "isPinned", .integer).notNull().defaults(to: 0)
            }
        }

        // v3: tag metadata — emoji and pinned state per hashtag.
        // Keyed by the tag string itself so a tag that nobody uses
        // anymore quietly disappears from the sidebar without
        // garbage-collecting its row here.
        migrator.registerMigration("v3-tagMetadata") { db in
            try db.create(table: "tag_metadata") { t in
                t.column("tag", .text).primaryKey()
                t.column("emoji", .text)               // nullable
                t.column("isPinned", .integer).notNull().defaults(to: 0)
            }
        }
        return migrator
    }

    // MARK: - Tag metadata

    /// A single row in `tag_metadata`. We expose this as a value
    /// type so the SwiftUI sidebar can observe a snapshot rather
    /// than the live row.
    struct TagMeta: Equatable {
        var tag: String
        var emoji: String?
        var isPinned: Bool
    }

    func allTagMetadata() throws -> [TagMeta] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM tag_metadata").map { row in
                TagMeta(
                    tag: row["tag"],
                    emoji: row["emoji"] as String?,
                    isPinned: (row["isPinned"] as Int? ?? 0) != 0
                )
            }
        }
    }

    /// Upsert one tag's metadata row.
    func setTagMetadata(_ meta: TagMeta) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO tag_metadata(tag, emoji, isPinned)
                VALUES (?, ?, ?)
                ON CONFLICT(tag) DO UPDATE SET
                    emoji = excluded.emoji,
                    isPinned = excluded.isPinned
                """, arguments: [meta.tag, meta.emoji, meta.isPinned ? 1 : 0])
        }
    }

    // MARK: - CRUD

    /// Load every note. Used by the in-memory cache at NotesStore init.
    /// O(n) once at launch; subsequent reads come from the cache.
    func allNotes() throws -> [Note] {
        try dbQueue.read { db in
            try Note.fetchAll(db, sql: "SELECT * FROM notes")
        }
    }

    /// Insert-or-replace a note. Used for both add and update — the id
    /// is stable per note across edits.
    func save(_ note: Note) throws {
        try dbQueue.write { db in
            try note.save(db)
        }
    }

    func delete(id: UUID) throws {
        _ = try dbQueue.write { db in
            try Note.deleteOne(db, key: id.uuidString)
        }
    }

    /// FTS5-driven body search. Returns ids of notes whose body matches
    /// `query`. Ranked by rank() so the most relevant rows surface
    /// first. We return ids (not full Notes) so the caller can join
    /// against the in-memory cache and keep filter logic centralised.
    func searchNoteIDs(matching rawQuery: String, limit: Int = 200) throws -> [UUID] {
        let cleanQuery = ftsQuery(from: rawQuery)
        guard !cleanQuery.isEmpty else { return [] }
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT notes.id FROM notes
                JOIN notes_fts ON notes_fts.rowid = notes.rowid
                WHERE notes_fts MATCH ?
                ORDER BY rank
                LIMIT ?
                """, arguments: [cleanQuery, limit])
            return rows.compactMap { row in
                (row["id"] as String?).flatMap(UUID.init(uuidString:))
            }
        }
    }

    /// Sanitise a user-typed query for FTS5. Strips characters that
    /// FTS treats as operators (`AND`, `OR`, `"`, `*`, `:` etc.) so a
    /// keystroke can't blow up the query parser. Multi-word inputs
    /// become prefix-matched AND queries, which is the most useful
    /// default for a note-search field.
    private func ftsQuery(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        // Split on whitespace, then strip every non-word character and
        // re-join with " AND " — anchoring each token as a prefix
        // match so partial typing matches early.
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "_"))
        let tokens: [String] = trimmed
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { word in
                String(word.unicodeScalars.filter { allowed.contains($0) })
            }
            .filter { !$0.isEmpty }
            .map { "\"\($0)\"*" }   // FTS5 prefix syntax
        return tokens.joined(separator: " AND ")
    }

    // MARK: - Migration from UserDefaults v1 blob

    /// One-shot import of the legacy UserDefaults JSON store, if any.
    /// Called once at app launch; deletes the legacy key afterwards so
    /// subsequent runs are no-ops.
    static let legacyKey = "vektor.notes.v1"
    static let migrationCompleteKey = "vektor.notes.sqliteMigrated"

    func importLegacyUserDefaultsIfNeeded() {
        let ud = UserDefaults.standard
        guard !ud.bool(forKey: Self.migrationCompleteKey),
              let data = ud.data(forKey: Self.legacyKey),
              let legacyNotes = try? JSONDecoder().decode([Note].self, from: data) else {
            ud.set(true, forKey: Self.migrationCompleteKey)
            return
        }
        do {
            try dbQueue.write { db in
                for note in legacyNotes {
                    try note.save(db)
                }
            }
            // Mark complete and remove the legacy blob so a future
            // schema reset doesn't re-import a stale copy.
            ud.set(true, forKey: Self.migrationCompleteKey)
            ud.removeObject(forKey: Self.legacyKey)
        } catch {
            // Don't mark complete — we'll retry on next launch.
            print("Notes legacy migration failed: \(error)")
        }
    }
}

// MARK: - GRDB record conformance

extension Note: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "notes" }

    /// Custom column mapping — Date round-trips as
    /// `Date.timeIntervalSince1970` (a Double), Bool as 0/1 Int.
    enum Columns: String, ColumnExpression {
        case id, body, createdAt, modifiedAt, isArchived, isTrashed, isPinned
    }

    init(row: Row) {
        let idString: String = row[Columns.id]
        self.id = UUID(uuidString: idString) ?? UUID()
        self.body = row[Columns.body]
        let created: Double = row[Columns.createdAt]
        let modified: Double = row[Columns.modifiedAt]
        self.createdAt = Date(timeIntervalSince1970: created)
        self.modifiedAt = Date(timeIntervalSince1970: modified)
        self.isArchived = (row[Columns.isArchived] as Int? ?? 0) != 0
        self.isTrashed = (row[Columns.isTrashed] as Int? ?? 0) != 0
        self.isPinned = (row[Columns.isPinned] as Int? ?? 0) != 0
    }

    func encode(to container: inout PersistenceContainer) {
        container[Columns.id]         = id.uuidString
        container[Columns.body]       = body
        container[Columns.createdAt]  = createdAt.timeIntervalSince1970
        container[Columns.modifiedAt] = modifiedAt.timeIntervalSince1970
        container[Columns.isArchived] = isArchived ? 1 : 0
        container[Columns.isTrashed]  = isTrashed ? 1 : 0
        container[Columns.isPinned]   = isPinned ? 1 : 0
    }
}
