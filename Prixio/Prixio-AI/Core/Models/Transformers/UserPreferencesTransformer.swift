import Foundation

/// Custom transformer for UserPreferences
final class UserPreferencesTransformer: ValueTransformer {

    override class func allowsReverseTransformation() -> Bool { true }

    override class func transformedValueClass() -> AnyClass { NSData.self }

    override func transformedValue(_ value: Any?) -> Any? {
        guard let preferences = value as? UserPreferences else { return nil }
        return try? JSONEncoder().encode(preferences)
    }

    override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else { return nil }
        return try? JSONDecoder().decode(UserPreferences.self, from: data)
    }
}
