import SwiftUI
import AppKit

/// User-facing appearance controls for the notes pane: theme, font,
/// reading width, line height. The choices live in @AppStorage so they
/// survive launches, and are exposed via a single
/// `NotesAppearanceSettings` ObservableObject the editor and list bind
/// to. The global `TallyTheme` keeps owning the rest of Vektor's
/// chrome; this struct only overrides what the notes pane draws.

/// Visual theme presets specific to the notes pane.
///   - `system` follows the OS appearance via `TallyTheme` (the
///     default — what existing users see today).
///   - `sepia` warm paper-tone background with deep ink text. Reads
///     well in long-form writing.
///   - `darkContrast` higher-contrast variant of dark mode for OLED
///     displays / late-night editing.
enum NotesTheme: String, CaseIterable, Identifiable {
    case system, sepia, darkContrast
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system:       return "Match system"
        case .sepia:        return "Sepia"
        case .darkContrast: return "High-contrast dark"
        }
    }

    var background: Color {
        switch self {
        case .system:       return TallyTheme.background
        case .sepia:        return Color(red: 0xF5/255, green: 0xEE/255, blue: 0xD8/255)
        case .darkContrast: return Color(red: 0x05/255, green: 0x08/255, blue: 0x10/255)
        }
    }
    var surface: Color {
        switch self {
        case .system:       return TallyTheme.surface
        case .sepia:        return Color(red: 0xEB/255, green: 0xE2/255, blue: 0xC6/255)
        case .darkContrast: return Color(red: 0x0D/255, green: 0x12/255, blue: 0x1C/255)
        }
    }
    var text: Color {
        switch self {
        case .system:       return TallyTheme.text
        case .sepia:        return Color(red: 0x2A/255, green: 0x21/255, blue: 0x10/255)
        case .darkContrast: return Color(red: 0xF6/255, green: 0xF7/255, blue: 0xFB/255)
        }
    }
    var muted: Color {
        switch self {
        case .system:       return TallyTheme.muted
        case .sepia:        return Color(red: 0x77/255, green: 0x64/255, blue: 0x42/255)
        case .darkContrast: return Color(red: 0x9C/255, green: 0xA5/255, blue: 0xBC/255)
        }
    }
    var accent: Color { TallyTheme.accent }  // accent stays Vektor orange across themes
}

/// Font choice for the editor + preview text. We always layer the
/// markdown styling on top, but the base typeface changes per choice.
enum NotesFont: String, CaseIterable, Identifiable {
    case system, serif, monospaced
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system:     return "System"
        case .serif:      return "Serif"
        case .monospaced: return "Monospaced"
        }
    }

    /// Base body font at the user's chosen size. The styling layer
    /// adjusts weight (bold / italic) and size (headings) on top.
    func baseFont(size: CGFloat) -> NSFont {
        switch self {
        case .system:
            return .systemFont(ofSize: size)
        case .serif:
            // macOS ships "New York" as a high-quality serif since
            // 11.0 — fall back to Charter / Times if the user has
            // somehow removed it.
            return NSFont(name: "New York", size: size)
                ?? NSFont(name: "Charter", size: size)
                ?? NSFont(name: "Times New Roman", size: size)
                ?? .systemFont(ofSize: size)
        case .monospaced:
            return .monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }
}

/// Maximum width the editor's text column should occupy. Wider
/// windows centre the column, leaving the side gutters as background.
/// Long lines hurt readability; this is the Bear / Ulysses / iA
/// Writer convention.
enum NotesReadingWidth: String, CaseIterable, Identifiable {
    case narrow, medium, wide, unlimited
    var id: String { rawValue }
    var label: String {
        switch self {
        case .narrow:    return "Narrow (600pt)"
        case .medium:    return "Medium (760pt)"
        case .wide:      return "Wide (920pt)"
        case .unlimited: return "Unlimited"
        }
    }
    var maxWidth: CGFloat {
        switch self {
        case .narrow:    return 600
        case .medium:    return 760
        case .wide:      return 920
        case .unlimited: return .infinity
        }
    }
}

/// Centralised observable that the editor + list bind to. SwiftUI
/// views observe one object instead of four separate @AppStorage
/// values, and the storage keys live in one place.
///
/// Not marked @MainActor so the NSTextView coordinator (which is
/// formally nonisolated under strict concurrency) can read the
/// values from its delegate callbacks. UserDefaults reads are
/// thread-safe; the only thing that needs main-actor isolation is
/// `objectWillChange.send()`, which the property setters do via
/// MainActor.assumeIsolated.
final class NotesAppearanceSettings: ObservableObject {
    static let shared = NotesAppearanceSettings()

    @AppStorage("tally.notes.theme") private var themeRaw: String = NotesTheme.system.rawValue
    @AppStorage("tally.notes.font") private var fontRaw: String = NotesFont.system.rawValue
    @AppStorage("tally.notes.fontSize") var fontSize: Double = 14
    @AppStorage("tally.notes.readingWidth") private var readingWidthRaw: String = NotesReadingWidth.medium.rawValue

    var theme: NotesTheme {
        get { NotesTheme(rawValue: themeRaw) ?? .system }
        set { themeRaw = newValue.rawValue; objectWillChange.send() }
    }
    var font: NotesFont {
        get { NotesFont(rawValue: fontRaw) ?? .system }
        set { fontRaw = newValue.rawValue; objectWillChange.send() }
    }
    var readingWidth: NotesReadingWidth {
        get { NotesReadingWidth(rawValue: readingWidthRaw) ?? .medium }
        set { readingWidthRaw = newValue.rawValue; objectWillChange.send() }
    }
}
