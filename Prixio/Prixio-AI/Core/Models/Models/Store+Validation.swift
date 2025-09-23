import Foundation

extension Store {

    func touch() {
        updatedAt = Date()
    }
}


extension Store {
    /// Validates the Store instance.
    /// Throws a ValidationError if any validation rule fails.
    func validate() throws {
        try validateName()
        try validateAddress()
        try validateCoordinates()
    }

    /// Validates that the name is not empty after trimming whitespace.
    /// Throws `.emptyName` if invalid.
    private func validateName() throws {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError.emptyName
        }
    }

    /// Validates that address fields are not empty after trimming whitespace.
    /// Throws `.custom("Address fields must not be empty")` if any field is invalid.
    private func validateAddress() throws {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedState = state.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedZipCode = zipCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCountry = country.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedAddress.isEmpty || trimmedCity.isEmpty || trimmedState.isEmpty || trimmedZipCode.isEmpty || trimmedCountry.isEmpty {
            throw ValidationError.custom("Address fields must not be empty")
        }
    }

    /// Validates that latitude is between -90 and 90 and longitude is between -180 and 180.
    /// Throws `.invalidCoordinates` if invalid.
    private func validateCoordinates() throws {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw ValidationError.invalidCoordinates
        }
    }
}
