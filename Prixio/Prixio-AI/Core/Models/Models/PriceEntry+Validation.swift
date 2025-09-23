import Foundation

extension PriceEntry {
    /// Update the modification timestamp
    func touch() {
        updatedAt = Date()
    }
}


public enum ValidationError: LocalizedError, Equatable {
    case emptyName
    case invalidPrice
    case invalidDateRange
    case missingCategory
    case invalidBarcode
    case invalidCoordinates
    case missingAssociation(String)
    case custom(String)

    public var errorDescription: String? {
        switch self {
        case .emptyName:
            return "The name cannot be empty."
        case .invalidPrice:
            return "The price must be a positive, finite number."
        case .invalidDateRange:
            return "The date is out of the allowed range."
        case .missingCategory:
            return "A category is required."
        case .invalidBarcode:
            return "The barcode is invalid."
        case .invalidCoordinates:
            return "The coordinates provided are invalid."
        case .missingAssociation(let association):
            return "Missing required association: \(association)."
        case .custom(let message):
            return message
        }
    }
}

extension PriceEntry {
    public func validate() throws {
        try validatePrice()
        try validateDates()
        try validateAssociations()
        try validateConfidence()
    }

    private func validatePrice() throws {
        guard price > 0 else {
            throw ValidationError.invalidPrice
        }
        let decimalPrice = NSDecimalNumber(decimal: price)
        guard decimalPrice.doubleValue.isFinite else {
            throw ValidationError.invalidPrice
        }
    }

    private func validateDates() throws {
        // Define reasonable bounds: 5 years in the past and future from now
        let now = Date()
        guard let pastLimit = Calendar.current.date(byAdding: .year, value: -5, to: now),
              let futureLimit = Calendar.current.date(byAdding: .year, value: 5, to: now) else {
            throw ValidationError.invalidDateRange
        }
        guard captureDate >= pastLimit && captureDate <= futureLimit else {
            throw ValidationError.invalidDateRange
        }
    }

    private func validateAssociations() throws {
        if store == nil && product == nil {
            throw ValidationError.missingAssociation("store or product")
        }
    }

    private func validateConfidence() throws {
        guard confidenceScore >= 0.0 && confidenceScore <= 1.0 else {
            throw ValidationError.custom("Confidence score must be between 0.0 and 1.0")
        }
    }
}

