//
//  SettingsView.swift
//  Prixio
//
//  Created by Daniel Bell on 6/11/26.
//

import FoundationModels
import SwiftData
import SwiftUI

/// The Settings tab. Surfaces app preferences and the status of the
/// on-device / Private Cloud Compute intelligence that powers scanning.
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PriceEntry.capturedAt, order: .reverse) private var entries: [PriceEntry]

    @State private var seedOperationError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    IntelligenceUsageView()
                } header: {
                    Text("On-Device Intelligence")
                } footer: {
                    Text("Prixio uses Apple Intelligence to read and parse price tags. Private Cloud Compute applies a daily usage limit per person.")
                }

                Section {
                    LabeledContent("Seeded records", value: "\(seededRecordCount)")

                    Button(seedButtonTitle) {
                        addTestRecords()
                    }

                    Button("Delete test records", role: .destructive) {
                        deleteTestRecords()
                    }
                    .disabled(seededRecordCount == 0)
                } header: {
                    Text("Compare Test Data")
                } footer: {
                    Text("Adds 100 marked grocery price records for Compare testing. Delete removes only records created by this tool.")
                }
            }
            .navigationTitle("Settings")
            .alert("Test data update failed", isPresented: isShowingSeedOperationError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(seedOperationError ?? "Unknown error")
            }
        }
    }

    private var seededRecordCount: Int {
        TestPriceEntrySeeder.seededCount(in: entries)
    }

    private var seedButtonTitle: String {
        seededRecordCount == 0 ? "Add 100 test records" : "Reset to 100 test records"
    }

    private var isShowingSeedOperationError: Binding<Bool> {
        Binding(
            get: { seedOperationError != nil },
            set: { newValue in
                if !newValue {
                    seedOperationError = nil
                }
            }
        )
    }

    private func addTestRecords() {
        do {
            try TestPriceEntrySeeder.deleteRecords(from: entries, in: modelContext)
            try TestPriceEntrySeeder.insertRecords(into: modelContext)
        } catch {
            seedOperationError = error.localizedDescription
        }
    }

    private func deleteTestRecords() {
        do {
            try TestPriceEntrySeeder.deleteRecords(from: entries, in: modelContext)
        } catch {
            seedOperationError = error.localizedDescription
        }
    }
}

/// Displays the Private Cloud Compute language model's quota status, keeping a
/// person aware of where they sit relative to their daily limit and offering an
/// upgrade path when one is available.
private struct IntelligenceUsageView: View {
    var body: some View {
        if #available(iOS 27.0, *) {
            PrivateCloudComputeUsageView()
        } else {
            Label(
                "Apple Intelligence requires iOS 27 or later.",
                systemImage: "sparkles"
            )
            .foregroundStyle(.secondary)
        }
    }
}

@available(iOS 27.0, *)
private struct PrivateCloudComputeUsageView: View {
    private let model = PrivateCloudComputeLanguageModel()

    var body: some View {
        let quotaUsage = model.quotaUsage

        // Depending on the quota state, display a label to keep a person aware
        // of the status of their daily limit.
        if quotaUsage.isLimitReached {
            Label("Usage limit exceeded", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.red)
        } else if case .belowLimit(let info) = quotaUsage.status {
            if info.isApproachingLimit {
                Label("Nearing usage limit", systemImage: "exclamationmark.circle")
                    .foregroundStyle(Color.orange)
            } else {
                Label("Within usage limit", systemImage: "checkmark.circle")
                    .foregroundStyle(Color.green)
            }
        }

        // When the provider reports a refresh time, let the person know when
        // their daily budget resets.
        if let resetDate = quotaUsage.resetDate {
            LabeledContent("Resets") {
                Text(resetDate, style: .relative)
            }
        }

        // Display a button to present the available upgrade options.
        if let suggestion = quotaUsage.limitIncreaseSuggestion {
            Button("Show options") {
                suggestion.show()
            }
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(
            for: [
                PriceEntry.self,
                StoreChain.self,
                StoreLocation.self,
                ShoppingList.self,
                ShoppingListItem.self
            ],
            inMemory: true
        )
}
