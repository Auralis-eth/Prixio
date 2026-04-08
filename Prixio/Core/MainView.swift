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

            PlaceholderTabView(
                title: "Compare",
                subtitle: "Browse tracked items, compare store prices, and inspect stale entries here."
            )
            .tag(AppTab.compare)
            .tabItem {
                Label("Compare", systemImage: "basket")
            }

            PlaceholderTabView(
                title: "Shopping List",
                subtitle: "Build a trip list, see the best store per item, and route back into Scan from here."
            )
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
