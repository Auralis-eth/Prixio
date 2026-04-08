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

            PlaceholderTabView(
                title: "Settings",
                subtitle: "Preferences, store management, and scanner defaults belong in this tab."
            )
            .tag(AppTab.settings)
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }
}
