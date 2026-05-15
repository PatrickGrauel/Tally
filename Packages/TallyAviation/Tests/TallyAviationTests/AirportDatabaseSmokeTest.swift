import XCTest
@testable import TallyAviation

/// Smoke coverage for the bundled OurAirports `airports.csv` parser.
/// Specifically guards the line-ending handling — the file ships with
/// CRLF terminators, and Swift's grapheme-cluster `Character` makes it
/// easy to mis-handle (a `split(separator: "\n")` returns zero rows
/// because `\r\n` collapses into a single character). If that
/// regresses, every test below collapses to zero.
final class AirportDatabaseTests: XCTestCase {
    func test_parsesEveryTier() {
        let db = AirportDatabase.shared
        XCTAssertGreaterThan(db.airports(tier: .large).count,  500,
                             "expected >500 large airports worldwide")
        XCTAssertGreaterThan(db.airports(tier: .medium).count, 1000,
                             "expected >1000 medium airports worldwide")
        XCTAssertGreaterThan(db.airports(tier: .small).count,  10_000,
                             "expected >10k small airports worldwide")
    }

    func test_bboxLookupReturnsCentralEuropeHubs() {
        let central = AirportDatabase.shared.airports(
            minLat: 44, maxLat: 56, minLon: 1, maxLon: 19,
            tiers: [.large]
        )
        XCTAssertGreaterThan(central.count, 30,
                             "expected several dozen large airports in central europe; got \(central.count)")
        // EDDF (Frankfurt) is a known large airport inside this box —
        // anchoring the test to a specific ident proves both the
        // viewport cull and the grid index are working, not just that
        // *some* entries land.
        XCTAssertTrue(central.contains(where: { $0.ident == "EDDF" }),
                      "expected EDDF in the central europe bbox")
    }

    func test_identLookup() {
        XCTAssertEqual(AirportDatabase.shared.airport(forIdent: "KSFO")?.ident, "KSFO")
        XCTAssertEqual(AirportDatabase.shared.airport(forIdent: "ksfo")?.ident, "KSFO")
        XCTAssertNil(AirportDatabase.shared.airport(forIdent: "ZZZZ"))
    }
}
