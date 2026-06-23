import Testing
@testable import Prixio

@MainActor
struct AppNavigationModelTests {
    @Test
    func launchScan_selectsScanTabAndStoresRequest_givenItemAndPreferredStore() throws {
        let navigation = AppNavigationModel()
        navigation.selectedTab = .shopping

        navigation.launchScan(itemName: "Milk", preferredChainName: "Costco")

        #expect(navigation.selectedTab == .scan)
        let request = try #require(navigation.pendingScanLaunchRequest)
        #expect(request.itemName == "Milk")
        #expect(request.preferredChainName == "Costco")
    }

    @Test
    func launchScan_allowsNilPreferredStore() throws {
        let navigation = AppNavigationModel()

        navigation.launchScan(itemName: "Eggs")

        let request = try #require(navigation.pendingScanLaunchRequest)
        #expect(request == ScanLaunchRequest(itemName: "Eggs", preferredChainName: nil))
    }

    @Test
    func consumePendingScanLaunchRequest_returnsRequestOnceAndClearsIt() throws {
        let navigation = AppNavigationModel()
        navigation.launchScan(itemName: "Bread", preferredChainName: "Walmart")

        let first = try #require(navigation.consumePendingScanLaunchRequest())
        let second = navigation.consumePendingScanLaunchRequest()

        #expect(first == ScanLaunchRequest(itemName: "Bread", preferredChainName: "Walmart"))
        #expect(second == nil)
        #expect(navigation.pendingScanLaunchRequest == nil)
    }

    @Test
    func consumePendingScanLaunchRequest_returnsNil_givenNoPendingRequest() {
        let navigation = AppNavigationModel()

        #expect(navigation.consumePendingScanLaunchRequest() == nil)
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
