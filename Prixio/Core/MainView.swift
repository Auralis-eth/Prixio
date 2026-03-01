//
//  MainView.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import SwiftUI

struct MainView: View {
    var body: some View {
        TabView {
            ScanRootView()
                .tabItem {
                    Label("Scan", systemImage: "viewfinder")
                }

            PlaceholderTabView(
                title: "Items",
                subtitle: "Saved entries and cheapest-price browsing land here next."
            )
            .tabItem {
                Label("Items", systemImage: "basket")
            }

            PlaceholderTabView(
                title: "Trends",
                subtitle: "Price history and trend charts can be layered onto the saved data model."
            )
            .tabItem {
                Label("Trends", systemImage: "chart.line.uptrend.xyaxis")
            }

            PlaceholderTabView(
                title: "Settings",
                subtitle: "Preferences, store management, and scanner defaults belong in this tab."
            )
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }
}
