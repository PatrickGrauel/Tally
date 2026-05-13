import Foundation

// MARK: - Saved loan

/// One saved loan scenario. Persisted by `LoanStore`
/// (= `PersistentStore<SavedLoan>`) in UserDefaults.
struct SavedLoan: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var principal: Double
    var ratePercent: Double
    var termYears: Double
    var currency: String
    var extraMonthly: Double          // monthly prepayment amount
}

// MARK: - Saved real-estate deal

/// One saved real-estate analysis. Carries every input the analyzer
/// needs plus a human-readable name and an optional address blob for
/// reference. Versioned key so older `SavedInvestment` data is ignored
/// rather than mis-decoded. Persisted by `RealEstateStore`
/// (= `PersistentStore<SavedRealEstateDeal>`).
struct SavedRealEstateDeal: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var address: String                                // free text, optional
    var currency: String

    // Property
    var purchasePrice: Double
    var closingCostsPercent: Double
    // Financing
    var downPaymentPercent: Double
    var mortgageRatePercent: Double
    var loanTermYears: Double
    // Rental income
    var monthlyRent: Double
    var vacancyPercent: Double
    var otherMonthlyIncome: Double
    var annualRentGrowthPercent: Double
    // Operating expenses
    var propertyTaxAnnual: Double
    var insuranceAnnual: Double
    var maintenancePercentOfRent: Double
    var propertyMgmtPercentOfRent: Double
    var hoaMonthly: Double
    var capExPercentOfRent: Double
    var utilitiesAnnual: Double
    // Hold + exit
    var appreciationPercent: Double
    var holdYears: Int
    var sellingCostsPercent: Double
}
