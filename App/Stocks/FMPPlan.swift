import Foundation

/// Which FMP subscription tier the user is on. Drives the daily-call hard
/// cap that Vektor enforces locally. Free is the default, since most users
/// will be — paid tiers are an explicit opt-in via the manage popover.
///
/// The cap is a *protective* hard cap, not a soft suggestion: even if
/// FMP would actually serve more, Vektor refuses new network calls past
/// it. That's the explicit ask — protection against runaway usage,
/// regardless of what the upstream tier allows.
enum FMPPlan: String, CaseIterable, Identifiable {
    case free
    case starter
    case pro
    case premium
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .free:    return "Free (250/day)"
        case .starter: return "Starter (600/day)"
        case .pro:     return "Pro (1500/day)"
        case .premium: return "Premium (unlimited)"
        case .custom:  return "Custom"
        }
    }

    /// Vektor's recommended cap for this plan — always a little under
    /// FMP's documented ceiling so the user has retry headroom. Premium
    /// is documented as "unlimited within reason"; we still pick a
    /// finite number because the user explicitly wants a hard cap.
    var recommendedCap: Int {
        switch self {
        case .free:    return 240    // 250 official, 10 reserved
        case .starter: return 570    // 600 official, 30 reserved
        case .pro:     return 1425   // 1500 official, 75 reserved
        case .premium: return 4750   // "unlimited" → still capped at 5000 minus reserve
        case .custom:  return 240    // user overrides via custom value
        }
    }

    /// Persistence keys — kept here so the actor and the views read the
    /// same names.
    static let storageKey = "vektor.stocks.fmpPlan"
    static let customCapKey = "vektor.stocks.fmpCustomCap"

    /// Resolve the effective hard cap from UserDefaults.
    static func currentDailyCap(defaults: UserDefaults = .standard) -> Int {
        let raw = defaults.string(forKey: storageKey) ?? FMPPlan.free.rawValue
        let plan = FMPPlan(rawValue: raw) ?? .free
        if plan == .custom {
            let cap = defaults.integer(forKey: customCapKey)
            return cap > 0 ? cap : FMPPlan.free.recommendedCap
        }
        return plan.recommendedCap
    }
}
