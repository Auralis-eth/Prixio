import Foundation

extension Product {

    func touch() {
        updatedAt = Date()
    }
}


extension Product {
    /// Validates the product properties
    func validate() throws {
        try validateName()
        try validateCategory()
        try validateBarcode()
    }
    
    /// Ensures the product name is non-empty after trimming whitespace
    private func validateName() throws {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError.emptyName
        }
    }
    
    /// Validates the category (currently a placeholder for potential checks)
    private func validateCategory() throws {
        // Category is non-optional and assumed valid; no action needed for now
    }
    
    /// Validates the barcode if present: digits only & valid EAN/UPC length
    private func validateBarcode() throws {
        guard let code = barcode else { return }
        
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let validLengths = [8, 12, 13, 14]
        
        // Check length
        guard validLengths.contains(trimmed.count) else {
            throw ValidationError.invalidBarcode
        }
        
        // Check all characters are digits
        guard trimmed.allSatisfy({ $0.isNumber }) else {
            throw ValidationError.invalidBarcode
        }
    }
}
