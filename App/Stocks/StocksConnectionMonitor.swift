import Foundation
import SwiftUI

/// Live connection-status indicator for the Stocks pane and Settings.
/// FMPClient is an actor and can't be observed directly by SwiftUI; this
/// MainActor-isolated singleton wraps the status into a `@Published` value
/// that views can bind to.
///
/// The actor posts an update after every analysis attempt (success or
/// error). Views read `status` for the dot colour + label.
@MainActor
final class StocksConnectionMonitor: ObservableObject {
    static let shared = StocksConnectionMonitor()

    enum Status: Equatable {
        case noKey                                // empty key field
        case unused                               // key set, no calls yet this launch
        case ok(symbol: String, at: Date)         // last call succeeded
        case invalidKey                           // 401/403
        case coverageGap(symbol: String)          // 402 Special Endpoint
        case rateLimited                          // 240/240 budget reached
        case networkProblem                       // generic transport error
    }

    @Published var status: Status

    private init() {
        let key = KeychainStorage.get("tally.stocks.fmpApiKey") ?? ""
        self.status = key.isEmpty ? .noKey : .unused
    }

    func update(_ newStatus: Status) {
        status = newStatus
    }

    /// Convenience: re-derive a sensible initial status when the key
    /// changes (user types into the SecureField or pastes a fresh key).
    func reflectKeyChange(newKey: String) {
        if newKey.trimmingCharacters(in: .whitespaces).isEmpty {
            status = .noKey
        } else if case .invalidKey = status {
            // They were red; pasting something new gets them back to amber
            // ("unvalidated") rather than leaving the red flag up.
            status = .unused
        } else if case .noKey = status {
            status = .unused
        }
    }

    var dotColour: Color {
        switch status {
        case .ok:                                  return TallyTheme.statusGood
        case .unused:                              return TallyTheme.statusCaution
        case .noKey, .coverageGap:                 return TallyTheme.muted
        case .invalidKey, .rateLimited,
             .networkProblem:                      return TallyTheme.statusBad
        }
    }

    var label: String {
        switch status {
        case .noKey:                       return "Not connected — paste a key to enable Stocks"
        case .unused:                      return "Key set — connection will be confirmed on first analysis"
        case .ok(let symbol, let at):
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.dateFormat = "HH:mm"
            return "Connected · last call \(symbol) at \(fmt.string(from: at))"
        case .invalidKey:                  return "Key rejected — FMP returned HTTP 401/403"
        case .coverageGap(let symbol):     return "\(symbol) not in your plan — key still valid"
        case .rateLimited:                 return "Daily budget reached — cached tickers still work"
        case .networkProblem:              return "Could not reach FMP — check your connection"
        }
    }
}
