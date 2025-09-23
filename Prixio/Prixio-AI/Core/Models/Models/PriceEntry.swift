import Foundation
import SwiftData
import CloudKit

@Model
final class PriceEntry: Sendable {

    // MARK: - Core Properties

    @Attribute(.unique)
    var id: UUID

    /// Price value stored as Decimal for precision
    @Attribute(.transformable(by: DecimalTransformer.self))
    var price: Decimal

    /// When the price was captured
    var captureDate: Date

    /// Method used to capture the price
    var captureMethod: CaptureMethod

    /// Optional notes about the price entry
    var notes: String?

    /// Validation status of the price
    var validationStatus: ValidationStatus

    /// Confidence score (0.0 - 1.0) for AI-captured prices
    var confidenceScore: Double

    // MARK: - Relationships

    /// The store where this price was found
    @Relationship(deleteRule: .nullify, inverse: \Store.priceEntries)
    var store: Store?

    /// The product this price is for
    @Relationship(deleteRule: .nullify, inverse: \Product.priceEntries)
    var product: Product?

    /// User who captured this price (if applicable)
    @Relationship(deleteRule: .nullify)
    var capturedBy: User?

    // MARK: - Metadata

    /// Creation timestamp
    var createdAt: Date

    /// Last modification timestamp
    var updatedAt: Date

    /// Soft delete flag
    var isDeleted: Bool = false

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        price: Decimal,
        captureDate: Date,
        captureMethod: CaptureMethod,
        notes: String? = nil,
        validationStatus: ValidationStatus = ValidationStatus.pending,
        confidenceScore: Double = 1.0,
        store: Store? = nil,
        product: Product? = nil,
        capturedBy: User? = nil
    ) {
        self.id = id
        self.price = price
        self.captureDate = captureDate
        self.captureMethod = captureMethod
        self.notes = notes
        self.validationStatus = validationStatus
        self.confidenceScore = confidenceScore
        self.store = store
        self.product = product
        self.capturedBy = capturedBy
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

