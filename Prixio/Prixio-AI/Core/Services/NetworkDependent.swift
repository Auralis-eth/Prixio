import Foundation

/// Protocol for services that depend on network connectivity
protocol NetworkDependent: AppService {
    var requiresNetwork: Bool { get }
    func handleNetworkChange(_ isConnected: Bool)
}
