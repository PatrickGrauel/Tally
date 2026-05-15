import Foundation
import os

/// Live stock-quote fetcher backed by Financial Modeling Prep's
/// `/stable/quote-short/{symbol}` endpoint. Cheap (1 API call per
/// symbol), shape:
///
///     [{ "symbol": "AAPL", "price": 175.34, "change": 1.02, "volume": ... }]
///
/// Multi-symbol queries hit the endpoint once per symbol — the bulk
/// endpoint exists but charges the same per-symbol and complicates
/// caching. The bridge layer dedupes via cooldown so this is fine.
public actor QuoteService {
    public static let shared = QuoteService()

    public struct Quote: Sendable, Equatable {
        public let symbol: String
        public let priceUSD: Double
        /// Day change in absolute price units (USD). FMP's `change`
        /// field; can be negative.
        public let changeUSD: Double?
        public let fetchedAt: Date
    }

    public enum FetchError: Error, Equatable {
        case missingAPIKey
        case symbolNotCovered      // FMP HTTP 402
        case rateLimited           // FMP HTTP 429
        case http(Int)
        case transport
        case decode
    }

    /// API-key source. Set by the App layer (which owns the Keychain)
    /// at launch. The engine never reads the Keychain directly so it
    /// keeps no Security-framework dependency.
    private var apiKeyProvider: (@Sendable () -> String?)?

    /// Per-symbol "last attempt" timestamp. Used as a 60-second
    /// cooldown on the network call so a user keystroke-spamming
    /// `stock AAPL` on a fresh document doesn't burn 20 API calls.
    private var lastAttempt: [String: Date] = [:]
    private static let cooldown: TimeInterval = 60

    private let session: URLSession
    private static let host = "https://financialmodelingprep.com"
    private static let logger = Logger(subsystem: "app.tally.Tally", category: "quote-service")

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 15
            cfg.timeoutIntervalForResource = 25
            self.session = URLSession(configuration: cfg)
        }
    }

    public func setAPIKeyProvider(_ provider: @escaping @Sendable () -> String?) {
        self.apiKeyProvider = provider
    }

    /// Fetch a single quote. Respects the 60-second per-symbol cooldown;
    /// returns `nil` on cooldown skip rather than throwing — the caller
    /// already has a cached value to fall back on.
    public func fetch(symbol: String, force: Bool = false) async throws -> Quote? {
        let id = symbol.uppercased()
        if !force, let last = lastAttempt[id],
           Date().timeIntervalSince(last) < Self.cooldown {
            return nil
        }
        lastAttempt[id] = Date()

        guard let key = apiKeyProvider?(), !key.isEmpty else {
            throw FetchError.missingAPIKey
        }
        guard var comps = URLComponents(string: "\(Self.host)/stable/quote-short") else {
            throw FetchError.transport
        }
        comps.queryItems = [
            URLQueryItem(name: "symbol", value: id),
            URLQueryItem(name: "apikey", value: key),
        ]
        guard let url = comps.url else { throw FetchError.transport }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            Self.logger.warning("quote fetch transport error for \(id): \(error.localizedDescription)")
            throw FetchError.transport
        }
        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200..<300: break
            case 402:       throw FetchError.symbolNotCovered
            case 429:       throw FetchError.rateLimited
            default:        throw FetchError.http(http.statusCode)
            }
        }
        // FMP wraps successful responses in a single-element array.
        struct Row: Decodable {
            let symbol: String
            let price: Double?
            let change: Double?
        }
        let rows: [Row]
        do {
            rows = try JSONDecoder().decode([Row].self, from: data)
        } catch {
            // Some FMP error states return a JSON object instead of an
            // array, so a decode failure usually means "no data."
            throw FetchError.decode
        }
        guard let r = rows.first, let p = r.price else {
            // Empty array == "not found" rather than a transport error;
            // surface as coverage gap so the UI shows the right message.
            throw FetchError.symbolNotCovered
        }
        return Quote(symbol: r.symbol, priceUSD: p, changeUSD: r.change, fetchedAt: Date())
    }
}
