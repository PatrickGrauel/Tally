import Foundation
import os

/// Synchronous-friendly hot cache for live stock quotes, mirroring the
/// shape of `MetarCacheBridge`. The calculator engine asks the bridge
/// for a cached quote when it sees a `stock AAPL` line; on a miss the
/// bridge kicks off a `QuoteService` fetch and posts a notification so
/// the calculator pane re-evaluates and the cached value lands inline.
@MainActor
public final class QuoteCacheBridge {
    public static let shared = QuoteCacheBridge()

    public static let notificationName = Notification.Name("tally.quoteCache.updated")

    public struct Entry: Sendable, Equatable {
        public let symbol: String
        public let priceUSD: Double
        public let changeUSD: Double?
        public let fetchedAt: Date
    }

    /// Outcome of the last fetch attempt for a symbol. Lets the engine
    /// display a useful error inline (`AAPL: not in your data plan`)
    /// instead of a perpetual "Fetching…" placeholder.
    public enum LastError: Sendable, Equatable {
        case missingAPIKey
        case symbolNotCovered
        case rateLimited
        case transient
    }

    private var entries: [String: Entry] = [:]
    private var errors: [String: LastError] = [:]
    private var inFlight: Set<String> = []
    private let service: QuoteService
    private static let logger = Logger(subsystem: "app.tally.Tally", category: "quote-cache-bridge")

    /// Per-symbol disk-cache TTL would be premature optimisation —
    /// quotes are 1-call-each and change minute-to-minute. We rely on
    /// `QuoteService`'s 60-second per-symbol cooldown for spam control.
    public init(service: QuoteService = .shared) {
        self.service = service
    }

    public func cached(symbol: String) -> Entry? {
        entries[symbol.uppercased()]
    }

    public func lastError(for symbol: String) -> LastError? {
        errors[symbol.uppercased()]
    }

    /// Kick off a background fetch. Idempotent per-symbol (dedupes
    /// in-flight tasks); the service layer enforces the cooldown.
    public func prefetch(symbol: String) {
        let id = symbol.uppercased()
        if inFlight.contains(id) { return }
        inFlight.insert(id)

        let service = self.service
        Task { [weak self] in
            guard let self else { return }
            do {
                if let q = try await service.fetch(symbol: id) {
                    await MainActor.run {
                        self.entries[id] = Entry(
                            symbol: q.symbol,
                            priceUSD: q.priceUSD,
                            changeUSD: q.changeUSD,
                            fetchedAt: q.fetchedAt
                        )
                        self.errors[id] = nil
                        self.inFlight.remove(id)
                        NotificationCenter.default.post(name: Self.notificationName, object: nil)
                    }
                } else {
                    // Cooldown skip — nothing to do, leave existing
                    // cached value (if any) alone.
                    await MainActor.run { self.inFlight.remove(id) }
                }
            } catch let err as QuoteService.FetchError {
                let mapped: LastError
                switch err {
                case .missingAPIKey:      mapped = .missingAPIKey
                case .symbolNotCovered:   mapped = .symbolNotCovered
                case .rateLimited:        mapped = .rateLimited
                case .http, .transport, .decode: mapped = .transient
                }
                await MainActor.run {
                    self.errors[id] = mapped
                    self.inFlight.remove(id)
                    NotificationCenter.default.post(name: Self.notificationName, object: nil)
                }
            } catch {
                await MainActor.run {
                    self.errors[id] = .transient
                    self.inFlight.remove(id)
                }
            }
        }
    }

    /// Drop all cached entries. Useful for tests; not exposed in UI.
    internal func _reset() {
        entries.removeAll()
        errors.removeAll()
        inFlight.removeAll()
    }
}
