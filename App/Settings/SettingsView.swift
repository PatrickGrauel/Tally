import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    // General
    @AppStorage("tally.precision")  private var precision: Int = 14
    @AppStorage("tally.appearance") private var appearance: String = "system"
    @AppStorage("tally.menuBarOnly") private var menuBarOnly: Bool = false
    @State private var launchAtLogin: Bool = LaunchAtLogin.isEnabled
    @AppStorage("tally.alwaysOnTop") private var alwaysOnTop: Bool = false
    @State private var showDocs: Bool = false

    // Units (preferences shared across all panes that care)
    @AppStorage("tally.aviation.speedUnit")    private var speedUnit: String = "kt"
    @AppStorage("tally.aviation.altitudeUnit") private var altitudeUnit: String = "ft"
    @AppStorage("tally.aviation.pressureUnit") private var pressureUnit: String = "hPa"


    // Module pane visibility — each toggle hides/shows the corresponding
    // pane in the top-left dropdown. Defaults match what new users got
    // before this setting existed, so nothing disappears after upgrade.
    @AppStorage("tally.panes.finance")      private var enableFinance      = true
    @AppStorage("tally.panes.aviation")     private var enableAviation     = true
    @AppStorage("tally.panes.stocks")       private var enableStocks       = false

    // Stocks — the API key field used to live in "Advanced", which hid
    // the only step that makes the pane work behind a label that means
    // "you probably don't need this". Now it sits in its own section
    // directly under the Stocks toggle, visible only when Stocks is
    // enabled.
    @AppStorage("tally.stocks.fmpApiKey")   private var fmpApiKey: String = ""
    @StateObject private var monitor = StocksConnectionMonitor.shared
    @State private var budget: FMPClient.BudgetSnapshot?

    var body: some View {
        Form {
            // MARK: General
            Section("General") {
                LabeledContent("Precision") {
                    HStack(spacing: 6) {
                        TextField("", value: $precision, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 48)
                            .multilineTextAlignment(.center)
                        Stepper("", value: $precision, in: 0...14).labelsHidden()
                        Text("decimal places")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        if !LaunchAtLogin.setEnabled(newValue) {
                            // Revert UI if the system rejected the change.
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
                Toggle("Always on top", isOn: $alwaysOnTop)
                Toggle("Menu Bar Only Mode", isOn: $menuBarOnly)
                    .onChange(of: menuBarOnly) { _, _ in
                        MenuBarController.shared.applyActivationPolicy()
                    }
                Text("Menu Bar Only Mode hides the Dock icon; reopen Tally by clicking the menu bar icon. macOS sometimes leaves the Dock icon visible until the next launch — use **Relaunch Tally** below if it sticks.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Relaunch Tally") {
                        MenuBarController.shared.relaunch()
                    }
                    .help("Quit and reopen Tally. The cleanest way to apply Menu Bar Only Mode if the Dock icon doesn't disappear.")
                }
            }

            // MARK: Tools — pane visibility
            Section {
                Toggle(Pane.finance.moduleTitle, isOn: $enableFinance)
                Text(Pane.finance.moduleDescription)
                    .font(.caption).foregroundStyle(.secondary)

                Toggle(Pane.aviation.moduleTitle, isOn: $enableAviation)
                Text(Pane.aviation.moduleDescription)
                    .font(.caption).foregroundStyle(.secondary)

                Toggle(Pane.stocks.moduleTitle, isOn: $enableStocks)
                Text(Pane.stocks.moduleDescription)
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Tools")
            } footer: {
                Text("Turn off tools you don't use to keep the top-left menu tidy. Calculator and Timezone are always available.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            // MARK: Units
            Section("Units") {
                Picker("Speed",    selection: $speedUnit) {
                    Text("Knots").tag("kt")
                    Text("MPH").tag("mph")
                    Text("km/h").tag("kph")
                }
                Picker("Altitude", selection: $altitudeUnit) {
                    Text("Feet").tag("ft")
                    Text("Meters").tag("m")
                }
                Picker("Pressure", selection: $pressureUnit) {
                    Text("hPa").tag("hPa")
                    Text("inHg").tag("inHg")
                }
            }

            // MARK: Stocks — only appears when the Stocks pane is on.
            // Houses the FMP API key + the live connection status + the
            // daily budget mirror, so the user can see at a glance
            // whether the data source is healthy without bouncing into
            // the pane.
            if enableStocks {
                Section {
                    LabeledContent("FMP API key") {
                        SecureField("", text: $fmpApiKey, prompt: Text("Paste your key"))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 260)
                            .onChange(of: fmpApiKey) { _, new in
                                monitor.reflectKeyChange(newKey: new)
                                Task { await FMPClient.shared.setAPIKey(new.isEmpty ? nil : new) }
                            }
                    }
                    HStack(spacing: 8) {
                        Circle()
                            .fill(monitor.dotColour)
                            .frame(width: 8, height: 8)
                        Text(monitor.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let b = budget {
                        LabeledContent("Today's usage") {
                            Text("\(b.callsToday)/\(b.callsLimit) calls · \(String(format: "%.1f MB / %.0f MB", Double(b.bytesToday) / 1_048_576, Double(b.bytesLimit) / 1_048_576))")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("Free plan: a curated set of US-listed large-caps, around 50 analyses/day.  •  Starter ($14/mo): full S&P 500.  •  Premium: international markets. [See plans →](https://site.financialmodelingprep.com/developer/docs/pricing)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Stocks")
                } footer: {
                    Text("Your key stays on this Mac. Tally only sends it to financialmodelingprep.com when you analyse a ticker. [Get a free key →](https://site.financialmodelingprep.com/developer/docs)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: Footer
            Section {
                HStack {
                    Button {
                        showDocs = true
                    } label: {
                        Label("Documentation", systemImage: "book")
                    }
                    Button("Send feedback") {
                        if let url = URL(string: "mailto:feedback@tally.app?subject=Tally%20feedback") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Spacer()
                    Text("Tally \(Bundle.main.shortVersion) (\(Bundle.main.buildVersion))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(width: 480, height: 540)
        .task {
            // Mirror the daily budget into Settings so the user can see
            // how their FMP allowance is doing without opening Stocks.
            budget = await FMPClient.shared.budgetSnapshot()
        }
        // `themedSheet` applies TallyTheme.background AND the user's
        // light/dark preference. Without it the Settings window ignores
        // the Appearance picker the user just changed.
        .themedSheet()
        .background(WindowLevelApplier(alwaysOnTop: alwaysOnTop))
        .sheet(isPresented: $showDocs) {
            DocumentationView()
        }
    }
}

/// Pins the host window to .floating when Always-on-Top is on, matching
/// the main Tally window so Settings doesn't end up hidden behind it.
private struct WindowLevelApplier: NSViewRepresentable {
    let alwaysOnTop: Bool
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            let desired: NSWindow.Level = alwaysOnTop ? .floating : .normal
            if window.level != desired { window.level = desired }
        }
    }
}

private extension Bundle {
    var shortVersion: String {
        (object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.1"
    }
    var buildVersion: String {
        (object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "1"
    }
}
