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
            FlyerProcessingPOCRootView()
                .tag(AppTab.flyers)
                .tabItem {
                    Label("Flyers", systemImage: "newspaper")
                }

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
        }
    }
}
