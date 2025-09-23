
import Foundation
import OSLog

class Logging {

    static let shared = Logging()

    // MARK: - Properties

    private let subsystem = "com.prixio.app"
    private var loggers: [LogCategory: Logger] = [:]

    // MARK: - Initialization

    private init() {
        setupLoggers()
    }

    private func setupLoggers() {
        for category in LogCategory.allCases {
            loggers[category] = Logger(subsystem: subsystem, category: category.rawValue)
        }
    }

    // MARK: - Logging Methods

    func info(
        _ message: String,
        category: LogCategory = .general,
        metadata: [String: Any] = [:]
    ) {
        let logger = loggers[category] ?? loggers[.general]!
        let metadataString = formatMetadata(metadata)

        logger.info("\(message)\(metadataString)")
    }

    func debug(
        _ message: String,
        category: LogCategory = .general,
        metadata: [String: Any] = [:]
    ) {
        let logger = loggers[category] ?? loggers[.general]!
        let metadataString = formatMetadata(metadata)

        logger.debug("\(message)\(metadataString)")
    }

    func error(
        _ message: String,
        error: Error? = nil,
        category: LogCategory = .general,
        metadata: [String: Any] = [:]
    ) {
        let logger = loggers[category] ?? loggers[.general]!
        var combinedMetadata = metadata

        if let error = error {
            combinedMetadata["error"] = String(describing: error)
        }

        let metadataString = formatMetadata(combinedMetadata)

        logger.error("\(message)\(metadataString)")
    }

    func warning(
        _ message: String,
        category: LogCategory = .general,
        metadata: [String: Any] = [:]
    ) {
        let logger = loggers[category] ?? loggers[.general]!
        let metadataString = formatMetadata(metadata)

        logger.warning("\(message)\(metadataString)")
    }

    // MARK: - Private Methods

    private func formatMetadata(_ metadata: [String: Any]) -> String {
        guard !metadata.isEmpty else { return "" }

        let metadataString = metadata
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")

        return " [\(metadataString)]"
    }
}

/// Log categories for organized logging
enum LogCategory: String, CaseIterable, Sendable {
    case general = "general"
    case network = "network"
    case database = "database"
    case sync = "sync"
    case ml = "ml"
    case lifecycle = "lifecycle"
    case ui = "ui"
    case performance = "performance"
}
