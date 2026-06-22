//
//  ReceiptReviewView.swift
//  Prixio
//
//  Phase 7 receipt review surface, distinct from the single-tag ConfirmationSheet.
//  Users confirm store/date/totals, correct extracted line items, promote trustworthy
//  lines into price history, and mark the receipt reviewed.
//

import SwiftData
import SwiftUI

struct ReceiptReviewView: View {
    @ObservedObject var viewModel: ReceiptReviewViewModel
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                headerSection
                if !viewModel.reviewIssues.isEmpty {
                    issuesSection
                }
                itemsSection
                discardSection
            }
            .navigationTitle("Review Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Save Draft") {
                        if viewModel.save() {
                            onClose()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if viewModel.markReviewed() {
                            onClose()
                        }
                    }
                }
            }
            .alert(
                "Couldn’t Save",
                isPresented: Binding(
                    get: { viewModel.promotionError != nil },
                    set: { if !$0 { viewModel.promotionError = nil } }
                ),
                presenting: viewModel.promotionError
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
            .alert(
                "Check the Total",
                isPresented: Binding(
                    get: { viewModel.reviewBlockedMessage != nil },
                    set: { if !$0 { viewModel.reviewBlockedMessage = nil } }
                ),
                presenting: viewModel.reviewBlockedMessage
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
            .alert(
                "Couldn’t Save",
                isPresented: Binding(
                    get: { viewModel.saveError != nil },
                    set: { if !$0 { viewModel.saveError = nil } }
                ),
                presenting: viewModel.saveError
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
        }
    }

    @ViewBuilder
    private var headerSection: some View {
        Section("Receipt") {
            ReceiptHeaderEditor(
                capture: viewModel.capture,
                onAmountEdited: { viewModel.recomputeReviewIssues() }
            )
        }
    }

    private var issuesSection: some View {
        Section("Needs a look") {
            ForEach(viewModel.reviewIssues, id: \.self) { issue in
                Label(issue.displayText, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var itemsSection: some View {
        Section {
            ForEach(viewModel.lineItems) { line in
                ReceiptLineRow(
                    line: line,
                    isPromoted: viewModel.isPromoted(line),
                    canPromote: viewModel.canPromote(line),
                    onPromote: { viewModel.promote(line) },
                    onPriceEdited: { viewModel.recomputeReviewIssues() }
                )
            }
        } header: {
            HStack {
                Text("Items")
                Spacer()
                if viewModel.promotableCount > 0 {
                    Text("\(viewModel.promotableCount) can be saved")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("Promote a line to save it as a trusted price for comparison. Receipt totals are kept separate from price history.")
        }
    }

    private var discardSection: some View {
        Section {
            Button("Discard Receipt", role: .destructive) {
                if viewModel.discard() {
                    onClose()
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        } footer: {
            Text("Discarding deletes this receipt and its line items. Only receipts you mark Done count toward spending.")
        }
    }
}

private struct ReceiptHeaderEditor: View {
    @Bindable var capture: ReceiptCapture

    /// Called after any header amount edit so the review surface can re-reconcile the totals issues
    /// (clearing a stale `totalsDoNotAddUp`/`missingTotal`, or re-flagging a newly broken total).
    let onAmountEdited: () -> Void

    // Local edit buffers for the currency fields. Editing the SwiftData `Decimal` directly through a
    // formatting binding reformats on every keystroke (forcing grouping separators that then fail to
    // re-parse, wiping any value ≥ 1000), so we keep the raw text here and only write the parsed
    // `Decimal` back. Mirrors the per-line price editor in `ReceiptLineRow`.
    @State private var totalText = ""
    @State private var subtotalText = ""
    @State private var taxText = ""
    @State private var discountText = ""
    @State private var depositText = ""

    var body: some View {
        if let image = capture.imageData.flatMap(UIImage.init(data:)) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 160)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }

        TextField("Store", text: Binding(
            get: { capture.storeChainNameSnapshot ?? "" },
            set: { capture.storeChainNameSnapshot = $0.isEmpty ? nil : $0 }
        ))

        // A receipt's basket counts toward this category in the spending summary. Defaults to groceries
        // but is editable so a non-grocery receipt doesn't inflate the grocery figure.
        Picker("Category", selection: Binding(
            get: { capture.category },
            set: { capture.category = $0 }
        )) {
            ForEach(ExpenseCategory.allCases) { category in
                Text(category.displayName).tag(category)
            }
        }

        // Spending math is single-currency, so a receipt whose extracted currency isn't the reporting
        // currency is silently excluded. Surfacing the currency here lets the user see and fix a misread
        // (e.g. a CAD receipt read as USD) instead of it quietly counting as $0 spend. The current value
        // is always in the list so an unusual extracted code stays selectable.
        Picker("Currency", selection: Binding(
            get: { capture.currencyCode },
            set: { capture.currencyCode = $0 }
        )) {
            ForEach(currencyOptions, id: \.self) { code in
                Text(code).tag(code)
            }
        }
        if capture.currencyCode != SpendingInsightEngine.reportingCurrency {
            Text("Tracked in \(SpendingInsightEngine.reportingCurrency); a \(capture.currencyCode) receipt won't be added to your spending totals.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        // The purchase date decides which month this receipt's spend lands in, so a wrong/missing
        // extracted date must be correctable. Defaults to the capture date until the user sets it.
        DatePicker(
            "Date",
            selection: Binding(
                get: { capture.purchaseDate ?? capture.capturedAt },
                set: { capture.purchaseDate = $0 }
            ),
            displayedComponents: .date
        )

        // Totals feed spending intelligence directly. They must be editable — including entering a
        // total that extraction missed entirely, otherwise a reviewed receipt silently counts as $0.
        currencyField("Total", text: $totalText) { capture.total = $0 }
            .onAppear { totalText = capture.total.map { CurrencyFormatter.shared.editableString($0) } ?? "" }
        currencyField("Subtotal", text: $subtotalText) { capture.subtotal = $0 }
            .onAppear { subtotalText = capture.subtotal.map { CurrencyFormatter.shared.editableString($0) } ?? "" }
        currencyField("Tax", text: $taxText) { capture.tax = $0 }
            .onAppear { taxText = capture.tax.map { CurrencyFormatter.shared.editableString($0) } ?? "" }
        // Discount and deposit feed the totals reconciliation, so they must be correctable too —
        // otherwise a mis-extracted discount/deposit leaves a "totals don't add up" flag the user
        // can't clear. Empty leaves the value nil (treated as zero by the reconciliation).
        currencyField("Discount", text: $discountText) { capture.discountTotal = $0 }
            .onAppear { discountText = capture.discountTotal.map { CurrencyFormatter.shared.editableString($0) } ?? "" }
        currencyField("Deposit", text: $depositText) { capture.depositTotal = $0 }
            .onAppear { depositText = capture.depositTotal.map { CurrencyFormatter.shared.editableString($0) } ?? "" }
    }

    /// A right-aligned currency text field rendered inside a `LabeledContent`. An empty field clears
    /// the underlying value to `nil`.
    private func currencyField(
        _ label: String,
        text: Binding<String>,
        write: @escaping (Decimal?) -> Void
    ) -> some View {
        LabeledContent(label) {
            TextField("0.00", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(label)
                .onChange(of: text.wrappedValue) { _, newValue in
                    // Drop negatives: a negative header amount would corrupt totals reconciliation and
                    // the spending sums (the shared parser allows negatives for other call sites).
                    write(ReceiptReviewViewModel.normalizedAmount(CurrencyFormatter.shared.price(from: newValue)))
                    // Re-reconcile so an edited total/subtotal/discount/deposit updates the totals issue
                    // instead of leaving the extraction-time flag stale.
                    onAmountEdited()
                }
        }
    }

    /// A short, Canada-first currency list, always including the receipt's current code so an unusual
    /// extracted value stays selectable.
    private var currencyOptions: [String] {
        var seen = Set<String>()
        return (["CAD", "USD", "EUR", "GBP", "AUD", "MXN", "JPY"] + [capture.currencyCode])
            .filter { seen.insert($0).inserted }
    }
}

private struct ReceiptLineRow: View {
    @Bindable var line: ReceiptLineItem
    let isPromoted: Bool
    let canPromote: Bool
    let onPromote: () -> Void
    /// Called after a line price edit so the totals-reconciliation issue (`.totalsDoNotAddUp`) is
    /// re-derived live — fixing a misread line price clears the flag without having to touch a header
    /// amount. Mirrors `onAmountEdited` on the header fields.
    let onPriceEdited: () -> Void

    /// Local edit buffer for the price. Editing the SwiftData value directly through a formatting
    /// binding reformats on every keystroke (forcing grouping separators that then fail to parse, so
    /// any value ≥ 1000 was silently wiped). Keeping the raw text here and only writing the parsed
    /// `Decimal` back avoids that round-trip loss.
    @State private var priceText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Item name", text: Binding(
                    get: { line.itemNameRaw ?? "" },
                    set: { line.itemNameRaw = $0.isEmpty ? nil : $0 }
                ))
                .textInputAutocapitalization(.words)

                if line.needsReview {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Needs review")
                }
            }

            HStack {
                TextField("0.00", text: $priceText)
                    .keyboardType(.decimalPad)
                    .frame(maxWidth: 120)
                    .accessibilityLabel("Price")
                    .onAppear {
                        priceText = line.priceValue.map { CurrencyFormatter.shared.editableString($0) } ?? ""
                    }
                    .onChange(of: priceText) { _, newValue in
                        line.priceValue = CurrencyFormatter.shared.price(from: newValue)
                        onPriceEdited()
                    }

                Spacer()

                if isPromoted {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    Button("Promote", action: onPromote)
                        .buttonStyle(.bordered)
                        .disabled(!canPromote)
                        .accessibilityHint("Saves this item to your price history")
                }
            }
        }
        .padding(.vertical, 2)
    }
}

extension ReceiptReviewIssue {
    var displayText: String {
        switch self {
        case .totalsDoNotAddUp:
            return "The line items don't add up to the printed total."
        case .missingTotal:
            return "No total was found on the receipt."
        case .lowConfidenceLines:
            return "Some lines were hard to read — check them."
        case .partiallyObscured:
            return "Part of the receipt was obscured."
        case .blurOrGlare:
            return "Blur or glare affected the scan."
        case .handwritten:
            return "Handwritten text may be misread."
        case .notAReceipt:
            return "This may not be a receipt."
        case .multipleReceipts:
            return "More than one receipt may be in the image."
        case .pagesTruncated:
            return "Only the first \(PDFReceiptRenderer.maxCompositePages) pages were imported."
        }
    }
}
