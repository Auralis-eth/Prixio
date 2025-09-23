
import Foundation

/// Comprehensive error handling service
class ErrorHandlingService: BaseService {

    private var errorHistory: [ErrorRecord] = []

    override var dependencies: [String] { [] }

    override init(identifier: String = "ErrorHandlingService") {
        super.init(identifier: identifier)
    }

    override func performInitialization() throws {
        Logging.shared.info("Initializing error handling service")
    }

    override func performShutdown() throws {
        Logging.shared.info("Shutting down error handling service")
    }

    func handleError(_ error: Error, context: String = "") {
        let record = ErrorRecord(error: error, context: context, timestamp: Date())
        errorHistory.append(record)

        Logging.shared.error("Handled error: \(error.localizedDescription)", error: error)
    }
}

struct ErrorRecord: Sendable {
    let error: Error
    let context: String
    let timestamp: Date
}
