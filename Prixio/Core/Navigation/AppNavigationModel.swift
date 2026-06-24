import Combine
import Foundation

enum AppTab: Hashable {
    case flyers
    case scan
    case compare
    case shopping
    case spending
    case settings
}

struct ScanLaunchRequest: Equatable {
    let itemName: String
    let preferredChainName: String?
}

@MainActor
final class AppNavigationModel: ObservableObject {
    @Published var selectedTab: AppTab = .scan
    @Published private(set) var pendingScanLaunchRequest: ScanLaunchRequest?

    func launchScan(itemName: String, preferredChainName: String? = nil) {
        pendingScanLaunchRequest = ScanLaunchRequest(
            itemName: itemName,
            preferredChainName: preferredChainName
        )
        selectedTab = .scan
    }

    func consumePendingScanLaunchRequest() -> ScanLaunchRequest? {
        defer {
            pendingScanLaunchRequest = nil
        }
        return pendingScanLaunchRequest
    }
}
