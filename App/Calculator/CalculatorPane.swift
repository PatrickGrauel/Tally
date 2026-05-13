import SwiftUI
import AppKit
import SumiEngine

struct CalculatorPane: View {
    let engine: NumiEngine?
    let error: String?
    @ObservedObject var documents: DocumentStore
    @Environment(\.openSettings) private var openSettings

    @State private var results: [LineResult] = []
    @State private var evaluateTask: Task<Void, Never>? = nil

    /// Drives a periodic re-evaluation so live data (METAR/TAF freshness
    /// labels, current-time timezone results, FX rates) refreshes on its
    /// own without the user having to type. The actual upstream network
    /// fetches are still gated by per-service cooldowns; this just makes
    /// sure those cooldowns get *checked* on a regular cadence.
    private let recomputeTick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    /// Editor line height. Forces the gutter rows to match so blank/header
    /// lines don't collapse and throw off alignment.
    private let lineHeight: CGFloat = 18

    var body: some View {
        Group {
            if let error {
                ContentUnavailableView("Engine failed to start",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(error))
            } else {
                HSplitView {
                    AutocompletingEditor(text: Binding(
                        get: { documents.selected.content },
                        set: { documents.updateSelectedContent($0) }
                    ))
                    .frame(minWidth: 320)
                    .background(SumiTheme.background)

                    resultsPane
                }
                .overlay(alignment: .bottomLeading) { gearButton }
            }
        }
        .background(SumiTheme.background)
        .onChange(of: documents.selectedID) { _, _ in evaluate() }
        .onChange(of: documents.selected.content) { _, _ in scheduleEvaluate() }
        .onAppear { evaluate() }
        .onReceive(NotificationCenter.default.publisher(for: CityResolver.notificationName)) { _ in
            evaluate()
        }
        .onReceive(NotificationCenter.default.publisher(for: MetarCacheBridge.notificationName)) { _ in
            evaluate()
        }
        // FX or crypto rates just landed in the JSContext — re-evaluate so
        // currency conversions stop showing the offline placeholder.
        // Without this the user sees `100 EUR + 25 USD = 125 USD` (1:1)
        // for the first 60 seconds of every launch, until either the
        // periodic tick fires or they happen to type something.
        .onReceive(NotificationCenter.default.publisher(for: NumiEngine.ratesUpdatedNotification)) { _ in
            evaluate()
        }
        // Every minute, re-evaluate the whole document. This refreshes the
        // freshness label on METAR/TAF lines (and current-time timezone
        // lines), and triggers `handleMetarLine` to nudge the cache bridge
        // — which itself decides whether to actually go to the network.
        .onReceive(recomputeTick) { _ in evaluate() }
    }

    private var resultsPane: some View {
        ScrollView {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(results, id: \.line) { r in
                    Text(attributedFor(r))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, minHeight: lineHeight, alignment: .trailing)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 44)
        }
        .frame(minWidth: 240)
        .background(SumiTheme.background)
    }

    private func attributedFor(_ r: LineResult) -> AttributedString {
        // Numi-style: lines that don't parse render as blank. The user
        // figures out what's wrong from the line they're typing, not
        // from the calculator yelling at them. Empty / structural lines
        // also render blank so the row keeps its baseline.
        switch r.kind {
        case .error:
            var blank = AttributedString(" ")
            blank.font = .system(.body, design: .monospaced)
            return blank
        default:
            var attr = AttributedString(display(r))
            attr.font = .system(.body, design: .monospaced)
            attr.foregroundColor = color(r)
            if let a = r.annotation {
                var suffix = AttributedString("  \(a.label)")
                suffix.font = .system(size: 10.5, design: .monospaced)
                switch a.tone {
                case .fresh:    suffix.foregroundColor = SumiTheme.muted
                case .stale:    suffix.foregroundColor = SumiTheme.statusCaution
                case .outdated: suffix.foregroundColor = SumiTheme.statusBad
                }
                attr.append(suffix)
            }
            return attr
        }
    }

    private func display(_ r: LineResult) -> String {
        switch r.kind {
        case .empty, .header, .comment, .label: return " "
        case .expression, .timezone:
            let v = r.value ?? ""
            // Truly empty result → blank row (no em dash). Reserve the
            // dash for the rare "we have a value but it isn't a number"
            // case, which lands here as an empty string already.
            if v.isEmpty || v == "undefined" || v == "null" { return " " }
            return v
        case .error:
            // Unreached: error path is taken in attributedFor above.
            return r.value ?? ""
        }
    }

    private func color(_ r: LineResult) -> Color {
        switch r.kind {
        case .error:      return SumiTheme.statusCaution
        case .timezone:   return SumiTheme.accent
        case .expression: return SumiTheme.text
        default:          return SumiTheme.muted
        }
    }

    // MARK: - Gear

    private var gearButton: some View {
        Button {
            openSettings()
        } label: {
            Image(systemName: "gearshape")
                .imageScale(.medium)
                .foregroundStyle(SumiTheme.muted)
                .padding(8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 6)
        .padding(.bottom, 4)
        .help("Preferences (⌘,)")
    }

    // MARK: - Evaluation

    private func scheduleEvaluate() {
        evaluateTask?.cancel()
        evaluateTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            if !Task.isCancelled { evaluate() }
        }
    }

    private func evaluate() {
        guard let engine else { return }
        results = engine.evaluate(documents.selected.content)
    }
}

// MARK: - Inline-autocomplete editor
//
// Custom NSTextView that draws a *ghost* suggestion after the cursor when the
// `SuggestionEngine` finds a dimension-compatible unit completion. Enter or
// Tab inserts the suggestion; Escape dismisses it.
//
// Deliberately does **not** mess with `textContainer.containerSize` /
// `setFrameSize` — those are the two paths that triggered the layout-
// recursion crash in the earlier custom-NSTextView attempt.

private struct AutocompletingEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let tv = AutocompletingTextView()
        tv.isRichText = false
        tv.isEditable = true
        tv.isSelectable = true
        tv.allowsUndo = true
        tv.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        tv.textColor = NSColor(SumiTheme.text)
        tv.insertionPointColor = NSColor(SumiTheme.accent)
        tv.backgroundColor = NSColor(SumiTheme.background)
        tv.drawsBackground = true
        tv.delegate = context.coordinator
        tv.textContainerInset = NSSize(width: 18, height: 14)
        // Pin the editor's line height to match the gutter's row height
        // exactly. Without this the editor uses the font's natural leading
        // (~17pt at default size) while the gutter rows are 18pt — over a
        // long document the two columns drift apart by ~1pt per line.
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 18
        paragraph.maximumLineHeight = 18
        tv.defaultParagraphStyle = paragraph
        tv.typingAttributes = [
            .font: tv.font!,
            .foregroundColor: NSColor(SumiTheme.text),
            .paragraphStyle: paragraph,
        ]
        tv.string = text
        if let container = tv.textContainer {
            container.lineFragmentPadding = 0
        }

        let scroll = NSScrollView()
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor(SumiTheme.background)

        context.coordinator.textView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? AutocompletingTextView else { return }
        if tv.string != text { tv.string = text }
        tv.recomputeSuggestion()
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let text: Binding<String>
        weak var textView: AutocompletingTextView?

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? AutocompletingTextView else { return }
            text.wrappedValue = tv.string
            tv.recomputeSuggestion()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? AutocompletingTextView else { return }
            tv.recomputeSuggestion()
        }
    }
}

private final class AutocompletingTextView: NSTextView {

    private var ghostSuggestion: String?

    /// Recompute the suggestion based on the current text + cursor position.
    func recomputeSuggestion() {
        let cursor = selectedRange().location
        let suggestion = SuggestionEngine.suggest(in: string, cursor: cursor)
        if suggestion != ghostSuggestion {
            ghostSuggestion = suggestion
            needsDisplay = true
        }
    }

    override func draw(_ rect: NSRect) {
        super.draw(rect)
        drawGhost()
    }

    private func drawGhost() {
        guard let suggestion = ghostSuggestion, !suggestion.isEmpty,
              let layoutManager, let textContainer
        else { return }

        let nsString = string as NSString
        let cursor = selectedRange().location
        guard cursor >= 0, cursor <= nsString.length else { return }

        // Find the position immediately to the right of the cursor.
        let glyphIndex: Int
        if cursor < nsString.length {
            glyphIndex = layoutManager.glyphIndexForCharacter(at: cursor)
        } else {
            glyphIndex = layoutManager.numberOfGlyphs
        }

        let fragment: NSRect
        let pointInFragment: NSPoint

        if glyphIndex < layoutManager.numberOfGlyphs {
            fragment = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            pointInFragment = layoutManager.location(forGlyphAt: glyphIndex)
        } else if layoutManager.numberOfGlyphs > 0 {
            // End of buffer — anchor to the trailing edge of the last glyph.
            let lastGlyph = layoutManager.numberOfGlyphs - 1
            fragment = layoutManager.lineFragmentRect(forGlyphAt: lastGlyph, effectiveRange: nil)
            let lastLoc = layoutManager.location(forGlyphAt: lastGlyph)
            let lastBox = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: lastGlyph, length: 1),
                in: textContainer
            )
            pointInFragment = NSPoint(x: lastLoc.x + lastBox.width, y: lastLoc.y)
        } else {
            fragment = layoutManager.extraLineFragmentRect
            pointInFragment = NSPoint(x: 0, y: 0)
        }

        let x = fragment.origin.x + pointInFragment.x + textContainerOrigin.x
        let y = fragment.origin.y + textContainerOrigin.y

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            .foregroundColor: NSColor(SumiTheme.muted).withAlphaComponent(0.55)
        ]
        (suggestion as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attrs)

        // Hint chip just past the suggestion — "↩ to accept".
        let chipFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .medium)
        let chipAttrs: [NSAttributedString.Key: Any] = [
            .font: chipFont,
            .foregroundColor: NSColor(SumiTheme.muted).withAlphaComponent(0.7)
        ]
        let ghostSize = (suggestion as NSString).size(withAttributes: attrs)
        let chip = "  ↩"
        (chip as NSString).draw(
            at: NSPoint(x: x + ghostSize.width, y: y + 2),
            withAttributes: chipAttrs
        )
    }

    override func keyDown(with event: NSEvent) {
        // Only intercept keys when a suggestion is showing — otherwise let
        // the editor behave normally.
        if ghostSuggestion != nil {
            switch event.keyCode {
            case 36, 48:   // 36 = Return, 48 = Tab — accept the suggestion
                acceptSuggestion()
                return
            case 53:       // Esc — dismiss
                ghostSuggestion = nil
                needsDisplay = true
                return
            default:
                break
            }
        }
        super.keyDown(with: event)
    }

    private func acceptSuggestion() {
        guard let suggestion = ghostSuggestion else { return }
        let cursor = selectedRange().location
        insertText(suggestion, replacementRange: NSRange(location: cursor, length: 0))
        ghostSuggestion = nil
        needsDisplay = true
    }
}
