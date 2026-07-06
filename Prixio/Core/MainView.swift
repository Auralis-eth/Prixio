//
//  MainView.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import SwiftData
import SwiftUI

struct MainView: View {
    @EnvironmentObject private var navigationModel: AppNavigationModel
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView(selection: $navigationModel.selectedTab) {
            ScanRootView()
                .tag(AppTab.scan)
                .tabItem {
                    Label("Scan", systemImage: "viewfinder")
                }

            CompareRootView()
                .tag(AppTab.compare)
                .tabItem {
                    Label("Compare", systemImage: "basket")
                }

            ShoppingListRootView()
                .tag(AppTab.shopping)
                .tabItem {
                    Label("Shopping List", systemImage: "checklist")
                }

            SpendingRootView()
                .tag(AppTab.spending)
                .tabItem {
                    Label("Spending", systemImage: "creditcard")
                }

            SettingsView()
                .tag(AppTab.settings)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .task {
            // Launch sweep: flyer prices expired past the grace period are deleted so
            // the store doesn't grow forever (recently-expired ones stay visible in
            // the saved-prices manager).
            _ = try? FlyerPriceRecordRepository(context: modelContext).deleteLongExpired()

            await scheduleWeeklyBrief()
        }
    }

    /// Composes the household brief from the store and (re)schedules the weekly
    /// notification with it, so the pending brief always reflects the latest data
    /// as of this launch.
    private func scheduleWeeklyBrief() async {
        let entries = (try? modelContext.fetch(FetchDescriptor<PriceEntry>())) ?? []
        let receipts = (try? modelContext.fetch(FetchDescriptor<ReceiptCapture>())) ?? []
        let flyerRecords = (try? modelContext.fetch(FetchDescriptor<FlyerPriceRecord>())) ?? []
        let restockRules = (try? modelContext.fetch(FetchDescriptor<RestockRule>())) ?? []
        let lists = (try? modelContext.fetch(FetchDescriptor<ShoppingList>())) ?? []

        let brief = WeeklyBriefEngine.compose(
            entries: entries,
            receipts: receipts,
            flyerRecords: flyerRecords,
            restockRules: restockRules,
            listItemKeys: lists.filter { !$0.isArchived }.flatMap(\.items).map(\.itemKey)
        )
        await WeeklyBriefNotifier().scheduleNextBrief(facts: brief.facts)
    }
}
