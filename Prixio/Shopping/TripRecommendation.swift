import Foundation

enum TripRecommendation: Equatable {
    case insufficientData
    case strongWinner(
        chainID: UUID?,
        chainName: String,
        count: Int,
        total: Int,
        staleCount: Int
    )
    case splitTrip(
        primaryChainID: UUID?,
        primaryChainName: String,
        primaryCount: Int,
        secondaryChainID: UUID?,
        secondaryChainName: String?,
        secondaryCount: Int?,
        staleCount: Int
    )
}
