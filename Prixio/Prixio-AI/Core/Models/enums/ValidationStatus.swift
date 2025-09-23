import Foundation

/// Price validation status
enum ValidationStatus: String, Sendable, CaseIterable, Codable {
    case pending = "pending"         // Not yet validated
    case valid = "valid"             // Confirmed valid
    case invalid = "invalid"         // Confirmed invalid
    case suspicious = "suspicious"   // Flagged for review
    case userVerified = "user_verified" // User confirmed accuracy
}
