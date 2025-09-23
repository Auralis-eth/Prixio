import Foundation

/// Comprehensive error handling for Prixio application
enum PrixioError: Error, LocalizedError, Sendable {

    // MARK: - Service Errors

    case serviceInitializationFailed(String, underlying: Error?)
    case serviceUnavailable(String)
    case dependencyResolutionFailed(String)

    // MARK: - Database Errors

    case databaseError(DatabaseErrorType, context: String?)

    enum DatabaseErrorType: Sendable {
        case saveFailure
        case fetchFailure
        case deleteFailure
        case corruptedData
        case constraintViolation
        case migrationFailed
    }

    // MARK: - Network Errors

    case networkError(NetworkErrorType, context: String?)

    enum NetworkErrorType: Sendable {
        case noConnection
        case timeout
        case serverError(Int)
        case invalidResponse
        case rateLimited
    }

    // MARK: - Sync Errors

    case syncError(SyncErrorType, context: String?)

    enum SyncErrorType: Sendable {
        case cloudKitUnavailable
        case syncTimeout
        case conflictResolution
        case quotaExceeded
    }

    // MARK: - Permission Errors

    case permissionDenied(PermissionType)

    enum PermissionType: String, Sendable {
        case camera = "camera"
        case location = "location"
        case notifications = "notifications"
        case cloudKit = "cloudkit"
    }

    // MARK: - Data Processing Errors

    case dataProcessingError(DataProcessingErrorType, context: String?)

    enum DataProcessingErrorType: Sendable {
        case invalidFormat
        case processingFailed
        case insufficientData
        case ocrFailed
    }

    // MARK: - Memory & Resource Errors

    case memoryPressure
    case resourceUnavailable(String)

    // MARK: - LocalizedError Implementation

    var errorDescription: String? {
        switch self {
        case .serviceInitializationFailed(let service, _):
            return "Failed to initialize \(service) service"
        case .serviceUnavailable(let service):
            return "\(service) service is currently unavailable"
        case .dependencyResolutionFailed(let dependency):
            return "Could not resolve dependency: \(dependency)"
        case .databaseError(let type, let context):
            return "Database error: \(type)\(context.map { " - \($0)" } ?? "")"
        case .networkError(let type, let context):
            return "Network error: \(type)\(context.map { " - \($0)" } ?? "")"
        case .syncError(let type, let context):
            return "Sync error: \(type)\(context.map { " - \($0)" } ?? "")"
        case .permissionDenied(let type):
            return "Permission denied for \(type.rawValue)"
        case .dataProcessingError(let type, let context):
            return "Data processing error: \(type)\(context.map { " - \($0)" } ?? "")"
        case .memoryPressure:
            return "Device is running low on memory"
        case .resourceUnavailable(let resource):
            return "Resource unavailable: \(resource)"
        }
    }

    var failureReason: String? {
        switch self {
        case .serviceInitializationFailed(_, let underlying):
            return underlying?.localizedDescription
        case .databaseError(.corruptedData, _):
            return "The database may be corrupted and needs repair"
        case .networkError(.noConnection, _):
            return "No internet connection available"
        case .syncError(.cloudKitUnavailable, _):
            return "iCloud sync is not available"
        case .permissionDenied(let type):
            return "The app needs \(type.rawValue) permission to function properly"
        default:
            return nil
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .networkError(.noConnection, _):
            return "Please check your internet connection and try again"
        case .permissionDenied(.camera):
            return "Please enable camera access in Settings > Privacy & Security > Camera"
        case .permissionDenied(.location):
            return "Please enable location access in Settings > Privacy & Security > Location Services"
        case .syncError(.cloudKitUnavailable, _):
            return "Please check your iCloud settings and try again"
        case .memoryPressure:
            return "Please close other apps to free up memory"
        default:
            return "Please try again or contact support if the problem persists"
        }
    }
}
