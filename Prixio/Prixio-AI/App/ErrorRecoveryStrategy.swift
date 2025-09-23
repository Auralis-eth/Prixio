import Foundation

/// Error recovery strategy
struct ErrorRecoveryStrategy: Sendable {
    let retryable: Bool
    let maxRetries: Int
    let backoffStrategy: BackoffStrategy
    let fallbackAction: (@Sendable () async throws -> Void)?

    enum BackoffStrategy: Sendable {
        case linear(TimeInterval)
        case exponential
        case fixed(TimeInterval)
    }

    init(
        retryable: Bool = true,
        maxRetries: Int = 3,
        backoffStrategy: BackoffStrategy = .exponential,
        fallbackAction: (@Sendable () async throws -> Void)? = nil
    ) {
        self.retryable = retryable
        self.maxRetries = maxRetries
        self.backoffStrategy = backoffStrategy
        self.fallbackAction = fallbackAction
    }
}
