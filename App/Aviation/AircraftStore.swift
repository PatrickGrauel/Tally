import Foundation

/// User-saved aircraft profile. Persisted by `AircraftStore`
/// (= `PersistentStore<SavedAircraft>`) in UserDefaults as JSON.
struct SavedAircraft: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var stations: [Station]
    var envelope: Envelope

    struct Station: Codable, Identifiable, Equatable {
        var id: UUID
        var name: String
        var weight: Double
        var arm: Double
    }

    struct Envelope: Codable, Equatable {
        var minCG: Double
        var maxCG: Double
        var maxWeight: Double
    }
}
