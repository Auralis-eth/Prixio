import Foundation

/// Custom transformer for Decimal values
final class DecimalTransformer: ValueTransformer {

    override class func allowsReverseTransformation() -> Bool { true }

    override class func transformedValueClass() -> AnyClass { NSData.self }

    override func transformedValue(_ value: Any?) -> Any? {
        guard let decimal = value as? Decimal else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: NSDecimalNumber(decimal: decimal),
                                                requiringSecureCoding: true)
    }

    override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else { return nil }
        guard let decimalNumber = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? NSDecimalNumber else {
            return nil
        }
        return decimalNumber.decimalValue
    }
}
