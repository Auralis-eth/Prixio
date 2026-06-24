import CoreLocation
import Foundation

struct ShoppingListRowData: Identifiable {
    let itemID: UUID
    let itemKey: String
    let displayName: String
    let brand: String?
    let quantityNote: String?
    let isDone: Bool
    let suggestion: PriceInsightEngine.BestStoreSuggestion?
    let bestStoreName: String?
    let bestPriceText: String?
    let ageText: String?
    let stalenessBucket: StalenessBucket?
    let distanceMeters: CLLocationDistance?

    var id: UUID {
        itemID
    }

    var shouldNudgeForFreshness: Bool {
        guard let suggestion else {
            return true
        }
        return suggestion.ageDays > 30 || suggestion.stalenessBucket == .veryStale
    }
}
