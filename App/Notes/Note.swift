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

    /// First non-empty line of the body, stripped of every markdown
    /// affordance that doesn't belong in a list-row title: heading
    /// hashes, bullet/checkbox markers, quote `>`, image markdown,
    /// inline code backticks, bold/italic asterisks, leading
    /// numbered-list digits.
    var title: String {
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let cleaned = Self.stripMarkdown(line: String(line))
            if !cleaned.isEmpty {
                return cleaned
            }
        }
        return "New note"
    }

    /// Body without the first line — used for the list-row preview
    /// snippet. Same markdown-stripping pass as `title` so the row
    /// reads as natural text, plus inline-image markdown is
    /// collapsed away (the row thumbnail conveys "this has an image").
    var preview: String {
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 1 else { return "" }
        return lines.dropFirst()
            .map { Self.stripMarkdown(line: String($0)) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// Pull off every kind of leading markdown prefix and remove
    /// inline punctuation that reads as noise in a preview-style
    /// snippet. Conservative — bullet/checkbox lines lose their
    /// marker, image references drop entirely, bold/italic stars
    /// and inline backticks come off so the result reads like
    /// natural prose.
    private static func stripMarkdown(line raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces)
        // Strip a numbered-list prefix `12. ` (digits + dot + space).
        if let m = s.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
            s.removeSubrange(m)
        }
        // Strip bullet + (optional) checkbox: `- `, `* `, `+ `,
        // `- [ ] `, `- [x] ` (case-insensitive).
        if let m = s.range(of: #"^[-*+]\s+(\[[ xX]\]\s+)?"#, options: .regularExpression) {
            s.removeSubrange(m)
        }
        // Strip leading heading hashes, blockquote `>`, and any
        // remaining leading whitespace.
        s = s.trimmingPrefix { ch in
            ch == "#" || ch == ">" || ch == " "
        }
        // Strip inline image markdown anywhere in the line.
        if let regex = try? NSRegularExpression(pattern: #"!\[[^\]]*\]\([^)]+\)"#) {
            let ns = s as NSString
            s = regex.stringByReplacingMatches(
                in: s,
                range: NSRange(location: 0, length: ns.length),
                withTemplate: "")
        }
        // Strip inline punctuation that reads as noise in a snippet:
        // bold/italic stars, inline backticks. Leaves the content
        // text intact.
        s = s
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
        return s.trimmingCharacters(in: .whitespaces)
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
