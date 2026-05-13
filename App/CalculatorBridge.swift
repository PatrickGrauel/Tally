import SwiftUI

/// Cross-pane bridge for "Send to Calculator" actions. The Finance pane
/// doesn't own the `DocumentStore` or the pane selection, but it needs to
/// push a labelled value into the active calculator document. `ContentView`
/// installs a real implementation on this object at app launch; everywhere
/// else just calls `bridge.send(...)`.
@MainActor
final class CalculatorBridge: ObservableObject {
    /// `(label, value)` → append the line as a `# label` comment plus the
    /// raw value on the next line. Implementation lives in `ContentView`.
    var send: (String, String) -> Void = { _, _ in }
}
