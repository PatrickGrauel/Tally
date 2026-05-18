import SwiftUI

/// Filter buckets the sidebar lets the user pick between. Each maps to
/// a different note list in the middle column.
enum NotesFilter: Hashable {
    case all
    case today                    // modified in the last 24 hours
    case tag(String)              // hierarchical tag, e.g. "work/2026"
    case archived
    case trashed
    case untagged

    var displayName: String {
        switch self {
        case .all:           return "All Notes"
        case .today:         return "Today"
        case .archived:      return "Archive"
        case .trashed:       return "Trash"
        case .untagged:      return "Untagged"
        case .tag(let path): return path
        }
    }

    var iconName: String {
        switch self {
        case .all:       return "note.text"
        case .today:     return "calendar"
        case .archived:  return "archivebox"
        case .trashed:   return "trash"
        case .untagged:  return "questionmark.circle"
        case .tag:       return "number"
        }
    }
}

/// Left-most pane: search field, all-notes bucket, the tag tree built
/// from `#tag/sub/…` paths, plus archive and trash buckets.
struct NotesSidebar: View {
    @ObservedObject var store: NotesStore
    @Binding var filter: NotesFilter
    @Binding var search: String

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            List(selection: bindingForList) {
                Section {
                    row(.all, count: store.activeNotes.filter { !$0.isArchived }.count)
                    row(.today, count: todayCount)
                    if hasUntagged {
                        row(.untagged, count: untaggedCount)
                    }
                }

                if !pinnedTagNodes.isEmpty {
                    Section("Pinned") {
                        ForEach(pinnedTagNodes, id: \.path) { node in
                            TagDisclosureGroup(node: node,
                                               filter: $filter,
                                               store: store)
                        }
                    }
                }
                if !tagTree.children.isEmpty {
                    Section("Tags") {
                        ForEach(tagTree.children, id: \.path) { node in
                            TagDisclosureGroup(node: node,
                                               filter: $filter,
                                               store: store)
                        }
                    }
                }

                Section {
                    row(.archived, count: store.archivedNotes.count)
                    row(.trashed, count: store.trashedNotes.count)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .background(TallyTheme.surface)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(TallyTheme.muted)
                .font(.system(size: 11))
            TextField("Search notes", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(TallyTheme.muted)
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(TallyTheme.codeSurface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - List rows

    @ViewBuilder
    private func row(_ target: NotesFilter, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: target.iconName)
                .foregroundStyle(TallyTheme.muted)
                .frame(width: 16)
            Text(target.displayName)
                .foregroundStyle(TallyTheme.text)
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.caption2)
                    .foregroundStyle(TallyTheme.muted)
            }
        }
        .tag(target)
    }

    /// Wraps the per-item `tag(_:)` selection into the list's
    /// SelectionValue type. Using a custom binding keeps the
    /// untagged / tag / archive / trash buckets in the same list.
    private var bindingForList: Binding<NotesFilter?> {
        Binding(
            get: { filter },
            set: { new in if let new { filter = new } }
        )
    }

    // MARK: - Tag tree

    private var hasUntagged: Bool { untaggedCount > 0 }
    private var untaggedCount: Int {
        store.activeNotes.filter { !$0.isArchived && $0.tags.isEmpty }.count
    }
    /// Notes modified within the last 24 hours. Cheap O(n) scan —
    /// notes counts at this layer are tiny.
    private var todayCount: Int {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        return store.activeNotes.filter {
            !$0.isArchived && $0.modifiedAt >= cutoff
        }.count
    }

    /// Tag paths the user has explicitly pinned via the right-click
    /// menu. Surfaced as a flat list above the main tag tree so they
    /// don't get buried under siblings. Each pinned entry stays in
    /// the regular tree too — pinning is presentation only, not a
    /// move.
    private var pinnedTagNodes: [TagNode] {
        var counts: [String: Int] = [:]
        var seen: [String: Bool] = [:]
        for note in store.activeNotes where !note.isArchived {
            seen.removeAll()
            for tag in note.tags {
                var parts: [String] = []
                for component in tag.split(separator: "/") {
                    parts.append(String(component))
                    let path = parts.joined(separator: "/")
                    if seen[path] == nil {
                        seen[path] = true
                        counts[path, default: 0] += 1
                    }
                }
            }
        }
        let pinned = store.tagMetadata.values
            .filter { $0.isPinned }
            .map { $0.tag }
            .sorted()
        return pinned.map { path in
            let node = TagNode(path: path)
            node.count = counts[path] ?? 0
            return node
        }
    }

    /// Build a forest from all hierarchical tag paths present across
    /// non-archived, non-trashed notes. A note tagged `#work/2026`
    /// contributes the nodes "work" and "work/2026", with the count at
    /// each level being the number of notes touching that prefix.
    private var tagTree: TagNode {
        var counts: [String: Int] = [:]
        var seen: [String: Bool] = [:]
        for note in store.activeNotes where !note.isArchived {
            // Avoid double-counting a note whose body has the same tag
            // typed in multiple places.
            seen.removeAll()
            for tag in note.tags {
                var parts: [String] = []
                for component in tag.split(separator: "/") {
                    parts.append(String(component))
                    let path = parts.joined(separator: "/")
                    if seen[path] == nil {
                        seen[path] = true
                        counts[path, default: 0] += 1
                    }
                }
            }
        }
        let root = TagNode(path: "")
        for path in counts.keys.sorted() {
            root.insert(path: path, count: counts[path] ?? 0)
        }
        return root
    }
}

/// One node in the hierarchical tag tree shown in the sidebar.
final class TagNode {
    let path: String
    var children: [TagNode] = []
    var count: Int = 0
    init(path: String) { self.path = path }
    var displayLabel: String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
    func insert(path: String, count: Int) {
        let components = path.split(separator: "/").map(String.init)
        var cursor = self
        for i in 0..<components.count {
            let subpath = components[0...i].joined(separator: "/")
            if let existing = cursor.children.first(where: { $0.path == subpath }) {
                cursor = existing
            } else {
                let child = TagNode(path: subpath)
                cursor.children.append(child)
                cursor = child
            }
        }
        cursor.count = count
    }
}

/// Recursive disclosure rendering for the tag tree. SwiftUI's
/// `DisclosureGroup` doesn't natively work inside `List` selection in a
/// nested way, so we manage expansion state per node locally.
struct TagDisclosureGroup: View {
    let node: TagNode
    @Binding var filter: NotesFilter
    @ObservedObject var store: NotesStore
    @State private var emojiPickerShown: Bool = false
    @State private var emojiDraft: String = ""

    /// Persistent expansion state per tag path. The previous
    /// always-expanded behaviour meant every launch forced the user
    /// to re-collapse trees they didn't care about; this keys the
    /// state in @AppStorage with the tag path so each subtree
    /// remembers itself across launches.
    @AppStorage private var expanded: Bool
    init(node: TagNode,
         filter: Binding<NotesFilter>,
         store: NotesStore) {
        self.node = node
        self._filter = filter
        self.store = store
        // Default expanded for top-level nodes (single path
        // component) so users see something on first launch; nested
        // levels start collapsed.
        let isTopLevel = !node.path.contains("/")
        self._expanded = AppStorage(wrappedValue: isTopLevel,
                                    "tally.notes.tagExpanded.\(node.path)")
    }

    var body: some View {
        if node.children.isEmpty {
            tagRow
        } else {
            DisclosureGroup(isExpanded: $expanded) {
                ForEach(node.children, id: \.path) { child in
                    TagDisclosureGroup(node: child,
                                       filter: $filter,
                                       store: store)
                }
            } label: {
                tagRow
            }
        }
    }

    private var meta: NotesDatabase.TagMeta? { store.tagMetadata[node.path] }

    private var tagRow: some View {
        HStack(spacing: 6) {
            // Custom emoji takes precedence over the default `#` glyph.
            // Bear's per-tag pancake / plant / etc. icons are this
            // feature exactly.
            if let emoji = meta?.emoji, !emoji.isEmpty {
                Text(emoji)
                    .font(.system(size: 13))
                    .frame(width: 14)
            } else {
                Image(systemName: "number")
                    .foregroundStyle(TallyTheme.muted)
                    .frame(width: 14)
            }
            Text(node.displayLabel)
                .foregroundStyle(TallyTheme.text)
            if meta?.isPinned == true {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(TallyTheme.accent)
                    .rotationEffect(.degrees(45))
            }
            Spacer()
            if node.count > 0 {
                Text("\(node.count)")
                    .font(.caption2)
                    .foregroundStyle(TallyTheme.muted)
            }
        }
        .tag(NotesFilter.tag(node.path))
        .contextMenu {
            Button(meta?.isPinned == true ? "Unpin tag" : "Pin tag") {
                store.toggleTagPinned(node.path)
            }
            Button("Set emoji…") {
                emojiDraft = meta?.emoji ?? ""
                emojiPickerShown = true
            }
            if meta?.emoji != nil {
                Button("Remove emoji") {
                    store.setTagEmoji(node.path, emoji: nil)
                }
            }
        }
        .sheet(isPresented: $emojiPickerShown) {
            EmojiSheet(
                tag: node.path,
                draft: $emojiDraft,
                onSet: { value in
                    store.setTagEmoji(node.path, emoji: value)
                    emojiPickerShown = false
                },
                onCancel: { emojiPickerShown = false }
            )
        }
    }
}

/// Tiny modal for picking the emoji to attach to a tag. Bear-style
/// "type any emoji or paste one." We don't include a full emoji
/// picker grid (NSPopover-based emoji picker exists but is fiddly to
/// embed); the user types or pastes a single emoji character.
private struct EmojiSheet: View {
    let tag: String
    @Binding var draft: String
    let onSet: (String) -> Void
    let onCancel: () -> Void

    /// Curated quick picks. Tap to choose without typing. Covers the
    /// most-common tag-icon use cases (work/personal/health/etc.).
    private let suggestions: [String] = [
        "📝", "💼", "🏠", "🧠", "📚", "✈️", "🍳", "💪",
        "🩺", "🌿", "🎯", "📅", "💡", "🛠️", "🎵", "🐾",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Emoji for #\(tag)")
                .font(.headline)
                .foregroundStyle(TallyTheme.text)

            Text("Type or paste a single emoji, or pick a suggestion below.")
                .font(.caption)
                .foregroundStyle(TallyTheme.muted)

            HStack {
                TextField("emoji", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8),
                          spacing: 6) {
                    ForEach(suggestions, id: \.self) { e in
                        Button(e) { draft = e }
                            .buttonStyle(.plain)
                            .font(.system(size: 18))
                            .frame(width: 26, height: 26)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                Button("Set") { onSet(draft) }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                    .tint(TallyTheme.accent)
                    .disabled(draft.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
