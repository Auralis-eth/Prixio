//
//  MainView.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import SwiftUI

struct MainView: View {
    @EnvironmentObject private var navigationModel: AppNavigationModel

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
    }
}
