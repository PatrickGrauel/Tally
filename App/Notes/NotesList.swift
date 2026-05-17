import SwiftUI

/// How the middle column's notes are ordered. Pinned notes always
/// float to the top within each sort mode — the mode just decides the
/// secondary ordering inside the pinned and un-pinned groups.
enum NotesSortMode: String, CaseIterable, Identifiable {
    case modified, created, title
    var id: String { rawValue }
    var label: String {
        switch self {
        case .modified: return "Date modified"
        case .created:  return "Date created"
        case .title:    return "Title"
        }
    }
    var systemImage: String {
        switch self {
        case .modified: return "clock"
        case .created:  return "calendar"
        case .title:    return "textformat"
        }
    }
}

/// Middle column: list of notes matching the current filter + search.
/// One row per note — title, two-line preview, relative modified date,
/// and a row of tag chips. Selection drives the editor in the right
/// column.
struct NotesList: View {
    @ObservedObject var store: NotesStore
    let filter: NotesFilter
    let search: String
    @Binding var selectedID: UUID?
    /// Multi-select set. Shift-/Cmd-click adds to it; bulk actions
    /// (archive, trash, pin) operate on every id here. Empty when the
    /// user is in single-select mode (the default).
    @State private var multiSelection: Set<UUID> = []
    @AppStorage("tally.notes.sortMode") private var sortModeRaw: String = NotesSortMode.modified.rawValue
    private var sortMode: NotesSortMode {
        NotesSortMode(rawValue: sortModeRaw) ?? .modified
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(TallyTheme.divider)
            if filteredNotes.isEmpty {
                emptyState
            } else {
                // Bind to the multi-select set so Shift/Cmd-click
                // selects ranges; also keep `selectedID` in sync with
                // the single-select case (when the set has exactly
                // one item) so the editor reacts.
                List(selection: $multiSelection) {
                    ForEach(filteredNotes) { note in
                        NotesListRow(note: note)
                            .tag(note.id)
                            .contextMenu { rowContextMenu(for: note) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onChange(of: multiSelection) { _, new in
                    // Drive the editor selection from whatever the
                    // user most recently clicked. Multi-select stays
                    // available for bulk context-menu actions.
                    if new.count == 1, let only = new.first {
                        selectedID = only
                    } else if new.isEmpty {
                        selectedID = nil
                    }
                }
                .onChange(of: selectedID) { _, new in
                    // External selection change (chrome new-note,
                    // wiki-link follow) → reflect into the set so the
                    // list row visually highlights.
                    if let id = new {
                        multiSelection = [id]
                    }
                }
                .onAppear {
                    if let id = selectedID { multiSelection = [id] }
                }
            }
        }
        .background(TallyTheme.background)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text(filter.displayName)
                .font(.headline)
                .foregroundStyle(TallyTheme.text)
            Spacer()
            Text("\(filteredNotes.count)")
                .font(.caption)
                .foregroundStyle(TallyTheme.muted)
            Menu {
                ForEach(NotesSortMode.allCases) { mode in
                    Button {
                        sortModeRaw = mode.rawValue
                    } label: {
                        Label(mode.label, systemImage: mode.systemImage)
                        if mode == sortMode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.caption)
                    .foregroundStyle(TallyTheme.muted)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Sort: \(sortMode.label)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: filter.iconName)
                .font(.system(size: 22))
                .foregroundStyle(TallyTheme.muted)
            Text(emptyText)
                .font(.callout)
                .foregroundStyle(TallyTheme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private var emptyText: String {
        if !search.isEmpty { return "No notes match \"\(search)\"." }
        switch filter {
        case .all:       return "No notes yet — press ⌘N to create one."
        case .today:     return "No notes edited in the last 24 hours."
        case .archived:  return "Archive is empty."
        case .trashed:   return "Trash is empty."
        case .untagged:  return "No untagged notes."
        case .tag(let p): return "No notes tagged #\(p)."
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private func rowContextMenu(for note: Note) -> some View {
        // Operate on the multi-selection set when the user
        // right-clicked a row that's part of a current bulk selection.
        // Otherwise act on just the clicked note.
        let targets: [Note] = {
            if multiSelection.count > 1, multiSelection.contains(note.id) {
                return filteredNotes.filter { multiSelection.contains($0.id) }
            }
            return [note]
        }()
        let label = targets.count > 1 ? " (\(targets.count))" : ""

        if note.isTrashed {
            Button("Restore\(label)") { targets.forEach(restore) }
            Button("Delete permanently\(label)", role: .destructive) {
                targets.forEach { store.remove($0.id) }
            }
        } else {
            let allPinned = targets.allSatisfy { $0.isPinned }
            Button(allPinned ? "Unpin\(label)" : "Pin to top\(label)") {
                targets.forEach { togglePin($0, force: !allPinned) }
            }
            Button(note.isArchived ? "Unarchive\(label)" : "Archive\(label)") {
                targets.forEach(toggleArchive)
            }
            Button("Move to Trash\(label)", role: .destructive) {
                targets.forEach(trash)
            }
        }
    }

    private func togglePin(_ note: Note, force: Bool) {
        var copy = note
        copy.isPinned = force
        copy.modifiedAt = Date()
        store.add(copy)
    }

    private func toggleArchive(_ note: Note) {
        var copy = note
        copy.isArchived.toggle()
        copy.modifiedAt = Date()
        store.add(copy)
    }

    private func trash(_ note: Note) {
        var copy = note
        copy.isTrashed = true
        copy.isArchived = false
        copy.modifiedAt = Date()
        store.add(copy)
        if selectedID == note.id { selectedID = nil }
    }

    private func restore(_ note: Note) {
        var copy = note
        copy.isTrashed = false
        copy.modifiedAt = Date()
        store.add(copy)
    }

    // MARK: - Filtering

    private var filteredNotes: [Note] {
        let base: [Note]
        switch filter {
        case .trashed:
            base = store.trashedNotes
        case .archived:
            base = store.archivedNotes
        case .all:
            base = store.activeNotes.filter { !$0.isArchived }
        case .today:
            let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
            base = store.activeNotes.filter { !$0.isArchived && $0.modifiedAt >= cutoff }
        case .untagged:
            base = store.activeNotes.filter { !$0.isArchived && $0.tags.isEmpty }
        case .tag(let path):
            base = store.activeNotes.filter { note in
                guard !note.isArchived else { return false }
                return note.tags.contains { tag in
                    tag == path || tag.hasPrefix("\(path)/")
                }
            }
        }
        let resorted = applySort(to: base)
        guard !search.trimmingCharacters(in: .whitespaces).isEmpty else { return resorted }
        // FTS5: the store's search index handles tokenisation, ranking
        // and prefix matches. We intersect the result set with the
        // filter's base list so the sidebar's archive/trash/tag bucket
        // still constrains the visible matches.
        let matchedIDs = store.searchIDs(matching: search)
        guard !matchedIDs.isEmpty else { return [] }
        return resorted.filter { matchedIDs.contains($0.id) }
    }

    /// Apply the user-chosen sort mode while keeping pinned notes at
    /// the top of every group. NotesStore already pre-sorts
    /// `activeNotes` pinned-first by modifiedAt, so for the .modified
    /// mode we can pass through; the other modes re-sort within the
    /// pinned/un-pinned groups.
    private func applySort(to notes: [Note]) -> [Note] {
        switch sortMode {
        case .modified:
            return notes
        case .created:
            return notes.sorted { a, b in
                if a.isPinned != b.isPinned { return a.isPinned && !b.isPinned }
                return a.createdAt > b.createdAt
            }
        case .title:
            return notes.sorted { a, b in
                if a.isPinned != b.isPinned { return a.isPinned && !b.isPinned }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        }
    }
}

private struct NotesListRow: View {
    let note: Note

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if note.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(TallyTheme.accent)
                            .rotationEffect(.degrees(45))
                    }
                    Text(note.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TallyTheme.text)
                        .lineLimit(1)
                    Spacer()
                    Text(NotesListRow.dateFormatter.localizedString(
                        for: note.modifiedAt, relativeTo: Date()))
                        .font(.system(size: 10))
                        .foregroundStyle(TallyTheme.muted)
                }
                if !note.preview.isEmpty {
                    Text(strippedPreview)
                        .font(.system(size: 11))
                        .foregroundStyle(TallyTheme.muted)
                        .lineLimit(2)
                }
                if !note.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(note.tags.prefix(4), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(TallyTheme.accent)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(TallyTheme.accent.opacity(0.10))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            if let thumbnail = firstImageThumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.vertical, 4)
    }

    /// Preview text minus any inline-image markdown — the raw
    /// `![](notes-asset://...)` tokens are ugly in the snippet and
    /// the thumbnail on the right already conveys "this note has an
    /// image."
    private var strippedPreview: String {
        let pattern = #"!\[[^\]]*\]\([^)]+\)"#
        return note.preview
            .replacingOccurrences(of: pattern, with: "",
                                  options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// First image attachment referenced by this note, loaded from
    /// the assets directory. Lazy via the assets resolver.
    private var firstImageThumbnail: NSImage? {
        guard let firstName = NotesAssets.referencedAssetNames(in: note.body).first,
              let url = URL(string: "\(NotesAssets.scheme)://\(firstName)"),
              let fileURL = NotesAssets.resolve(url) else { return nil }
        return NSImage(contentsOf: fileURL)
    }

    private static let dateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}
