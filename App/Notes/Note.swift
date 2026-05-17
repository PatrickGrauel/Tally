import Foundation

/// One note in the Notes pane. Body is plain-text markdown; title and
/// tags are derived from the body on read so they're never stale. The
/// model deliberately stores no separate `title` field — Bear's first-
/// line-is-title convention is honest and survives copy-paste between
/// notes without keeping a denormalised copy in sync.
///
/// Image attachments live on disk under `~/Library/Application
/// Support/Vektor/notes-assets/` and are referenced from the body via
/// the custom `notes-asset://<uuid>.<ext>` scheme. The body is the
/// only source of truth for which assets are in use; the orphan
/// cleanup pass scans every note's body on launch and deletes
/// unreferenced files.
struct Note: Codable, Identifiable, Equatable {
    var id: UUID
    var body: String
    var createdAt: Date
    var modifiedAt: Date
    var isArchived: Bool
    var isTrashed: Bool
    var isPinned: Bool

    init(id: UUID = UUID(),
         body: String = "",
         createdAt: Date = Date(),
         modifiedAt: Date = Date(),
         isArchived: Bool = false,
         isTrashed: Bool = false,
         isPinned: Bool = false) {
        self.id = id
        self.body = body
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isArchived = isArchived
        self.isTrashed = isTrashed
        self.isPinned = isPinned
    }

    /// Manual Codable so a note encoded before `isPinned` existed
    /// (legacy UserDefaults snapshots, older .md exports) still
    /// decodes cleanly. New field defaults to false.
    enum CodingKeys: String, CodingKey {
        case id, body, createdAt, modifiedAt, isArchived, isTrashed, isPinned
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id         = try c.decode(UUID.self,   forKey: .id)
        self.body       = try c.decode(String.self, forKey: .body)
        self.createdAt  = try c.decode(Date.self,   forKey: .createdAt)
        self.modifiedAt = try c.decode(Date.self,   forKey: .modifiedAt)
        self.isArchived = try c.decode(Bool.self,   forKey: .isArchived)
        self.isTrashed  = try c.decode(Bool.self,   forKey: .isTrashed)
        self.isPinned   = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }

    /// First non-empty line of the body, stripped of leading markdown
    /// noise (`#`, `##`, `*`, `>`). Empty notes show as "New note".
    var title: String {
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = String(line)
                .trimmingCharacters(in: .whitespaces)
                .trimmingPrefix(while: { ch in
                    ch == "#" || ch == "*" || ch == ">" || ch == "-" || ch == " "
                })
            if !trimmed.isEmpty {
                return String(trimmed)
            }
        }
        return "New note"
    }

    /// Body without the first line — used for the list-row preview snippet.
    var preview: String {
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 1 else { return "" }
        return lines.dropFirst()
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// All `#tag` and `#tag/sub` tokens in the body, lowercased and
    /// deduplicated. A tag stops at whitespace, punctuation other than
    /// `/`, or end-of-line.
    var tags: [String] {
        NoteTokenizer.tags(in: body)
    }
}

private extension String {
    /// Trim the prefix until a character that doesn't match the predicate.
    func trimmingPrefix(while predicate: (Character) -> Bool) -> String {
        var i = startIndex
        while i < endIndex, predicate(self[i]) {
            i = index(after: i)
        }
        return String(self[i...])
    }
}
