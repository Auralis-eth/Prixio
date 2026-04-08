import Testing
@testable import Prixio

@MainActor
struct AppNavigationModelTests {
    @Test
    func launchScanStoresItemNameAndOptionalPreferredChain() {
        let navigationModel = AppNavigationModel()

        navigationModel.launchScan(itemName: "Milk", preferredChainName: "Co-op")

        #expect(navigationModel.selectedTab == .scan)
        #expect(
            navigationModel.pendingScanLaunchRequest ==
            ScanLaunchRequest(itemName: "Milk", preferredChainName: "Co-op")
        )
    }

    @Test
    func launchScanAllowsMissingPreferredChain() {
        let navigationModel = AppNavigationModel()

        navigationModel.launchScan(itemName: "Bananas")

        #expect(
            navigationModel.pendingScanLaunchRequest ==
            ScanLaunchRequest(itemName: "Bananas", preferredChainName: nil)
        )
    }

    @Test
    func consumingLaunchRequestClearsPendingState() {
        let navigationModel = AppNavigationModel()
        navigationModel.launchScan(itemName: "Yogurt", preferredChainName: "Sobeys")

        let request = navigationModel.consumePendingScanLaunchRequest()

        #expect(request == ScanLaunchRequest(itemName: "Yogurt", preferredChainName: "Sobeys"))
        #expect(navigationModel.pendingScanLaunchRequest == nil)
    }

    @Test
    func applyingLaunchRequestUpdatesScanDraft() {
        let viewModel = ScanViewModel()

        viewModel.applyLaunchRequest(
            ScanLaunchRequest(itemName: "Eggs", preferredChainName: "Walmart")
        )

        #expect(viewModel.draft.itemName == "Eggs")
        #expect(viewModel.draft.storeChainName == "Walmart")
        #expect(viewModel.draft.storeChainExplicitlySelected == true)
    }
}
