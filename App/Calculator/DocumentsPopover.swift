import SwiftUI

/// Popover that lists all calculation documents. First line of each doc is
/// shown as its title (Numi-style). The user can pick one, create new docs,
/// search across all docs, and delete docs.
struct DocumentsPopover: View {
    @ObservedObject var store: DocumentStore
    @Binding var isPresented: Bool
    @State private var search: String = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(SumiTheme.muted)
                TextField("Search calculations", text: $search)
                    .textFieldStyle(.plain)
                    .foregroundStyle(SumiTheme.text)
                    .focused($searchFocused)
            }
            .padding(8)
            .background(SumiTheme.codeSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding([.horizontal, .top], 8)

            let filtered = store.filtered(searching: search)
            ScrollView {
                if filtered.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.title2)
                            .foregroundStyle(SumiTheme.muted)
                        Text(search.isEmpty
                             ? "No calculations yet."
                             : "No calculations match '\(search)'.")
                            .font(.callout)
                            .foregroundStyle(SumiTheme.muted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 32)
                } else {
                    VStack(spacing: 2) {
                        ForEach(filtered) { doc in
                            DocumentRow(doc: doc,
                                        isSelected: doc.id == store.selectedID,
                                        onSelect: {
                                store.select(doc.id)
                                isPresented = false
                            },
                                        onDelete: { store.delete(doc.id) })
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(width: 320, height: 420)
        .themedSheet()
        // Auto-focus the search field on open. Eliminates the
        // why-do-I-have-to-click trip every time the popover appears.
        .onAppear { searchFocused = true }
    }
}

private struct DocumentRow: View {
    let doc: SumiDocument
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(doc.title)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(SumiTheme.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(doc.updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(SumiTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Always render the trash button (at low opacity when not
            // hovered) so keyboard-only users can reach it and so the
            // affordance is consistent across rows.
            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(SumiTheme.muted)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1.0 : 0.35)
            .help("Delete document")
            .accessibilityLabel("Delete \(doc.title)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? SumiTheme.surface : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { hovering = $0 }
    }
}
