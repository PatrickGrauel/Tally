import SwiftUI
import AppKit

@main
struct TallyApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var menuBarBoot = MenuBarBoot()
    @Environment(\.openWindow) private var openWindow
    @AppStorage("tally.alwaysOnTop") private var alwaysOnTop: Bool = false

    var body: some Scene {
        WindowGroup("Tally", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 760, minHeight: 520)
                .background(WindowLevelApplier(alwaysOnTop: alwaysOnTop))
                .background(CrossSpaceSummonApplier())
                .background(WindowOpenerBridge())
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

/// Pins the hosting window to `.floating` when Always-on-Top is enabled.
/// Restricted to the actual content window — never touches the MenuBarExtra
/// status-item window (which would cause a redraw storm).
private struct WindowLevelApplier: NSViewRepresentable {
    let alwaysOnTop: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            let desired: NSWindow.Level = alwaysOnTop ? .floating : .normal
            if window.level != desired {
                window.level = desired
            }
        }
    }
}

/// Configures the hosting window to appear on the active Space and
/// pierce fullscreen apps. Applied via `.background` on the WindowGroup
/// root so every freshly-created window gets the flags from the start.
private struct CrossSpaceSummonApplier: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            MenuBarController.prepareForCrossSpaceSummon(window)
        }
    }
}

/// Hands SwiftUI's `openWindow` and `openSettings` actions to
/// MenuBarController so the NSObject world can (re)open the "main"
/// WindowGroup window and the Settings scene reliably across macOS
/// releases. The historical `showSettingsWindow:` / `showPreferencesWindow:`
/// selectors aren't always wired into the responder chain when the app
/// is running in `.accessory` mode, so going via SwiftUI's native
/// environment actions is much more robust.
private struct WindowOpenerBridge: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                MenuBarController.shared.openMainWindow = {
                    openWindow(id: "main")
                }
                MenuBarController.shared.openSettingsAction = {
                    openSettings()
                }
            }
    }
}

/// Drives the menu bar installation + activation policy at app startup.
@MainActor
final class MenuBarBoot: ObservableObject {
    init() {
        MenuBarController.shared.install()
        MenuBarController.shared.applyActivationPolicy()
    }
}
