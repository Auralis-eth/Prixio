import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import Prixio

@MainActor
struct PriceEntryRepositoryTests {
    @Test
    func invalidDraftDoesNotInsertEntry() throws {
        let context = try makeContext()
        let repository = PriceEntryRepository(context: context)

        var draft = validDraft()
        draft.priceText = "not a price"

        try repository.saveEntry(from: draft)

        #expect(try context.fetch(FetchDescriptor<PriceEntry>()).isEmpty)
    }

    @Test
    func existingChainAndLocationAreReused() throws {
        let context = try makeContext()
        let chain = StoreChain(name: "Walmart", aliases: ["Walmart"])
        let location = StoreLocation(displayName: "Walmart Beltline")
        context.insert(chain)
        context.insert(location)
        try context.save()

        var draft = validDraft()
        draft.storeChainName = "Walmart"
        draft.storeLocationName = "Walmart Beltline"

        try PriceEntryRepository(context: context).saveEntry(from: draft)

        let chains = try context.fetch(FetchDescriptor<StoreChain>())
        let locations = try context.fetch(FetchDescriptor<StoreLocation>())
        let entry = try #require(context.fetch(FetchDescriptor<PriceEntry>()).first)

        #expect(chains.count == 1)
        #expect(locations.count == 1)
        #expect(entry.storeChainId == chain.id)
        #expect(entry.storeLocationId == location.id)
        #expect(location.chainId == chain.id)
    }

    @Test
    func unknownChainDoesNotCreateChainRecord() throws {
        let context = try makeContext()
        var draft = validDraft()
        draft.storeChainName = "Unknown"
        draft.storeLocationName = "Corner Market"

        try PriceEntryRepository(context: context).saveEntry(from: draft)

        let chains = try context.fetch(FetchDescriptor<StoreChain>())
        let entry = try #require(context.fetch(FetchDescriptor<PriceEntry>()).first)

        #expect(chains.isEmpty)
        #expect(entry.storeChainId == nil)
        #expect(entry.storeChainNameSnapshot == "Unknown")
    }

    @Test
    func savedPhotoPathUsesCaptureTimestampAndPersistsProvidedData() throws {
        let context = try makeContext()
        var draft = validDraft()
        draft.capturedAt = Date(timeIntervalSince1970: 987_654_321)
        draft.imageData = Data([1, 2, 3, 4])

        try PriceEntryRepository(context: context).saveEntry(from: draft)

        let entry = try #require(context.fetch(FetchDescriptor<PriceEntry>()).first)
        let url = URL(fileURLWithPath: entry.photoAssetId)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(url.lastPathComponent == "scan-987654321.jpg")
        #expect(try Data(contentsOf: url) == Data([1, 2, 3, 4]))
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: PriceEntry.self,
                StoreChain.self,
                StoreLocation.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func validDraft() -> PriceEntryDraft {
        var draft = PriceEntryDraft()
        draft.itemName = "Milk"
        draft.priceText = "4.99"
        draft.selectedUnit = .each
        draft.storeChainName = "Walmart"
        draft.storeChainExplicitlySelected = true
        draft.storeCoordinate = CLLocationCoordinate2D(latitude: 51.04, longitude: -114.07)
        return draft
    }
}
