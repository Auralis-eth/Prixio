//
//  CurrencyFormatter.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import Foundation

/// Single source of truth for the app's default currency. v1 is Canada-focused, so the default is
/// CAD; capture can override per-record (e.g. a receipt that prints a different currency). Note that
/// `CurrencyFormatter` still *displays* this one currency app-wide — full multi-currency display is a
/// separate effort (see PriceCaptureAndIntelligence.md).
enum AppCurrency {
    static let defaultCode = "CAD"
}

struct CurrencyFormatter {
    static let shared = CurrencyFormatter()
    
    private let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()
    
    private let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = AppCurrency.defaultCode
        return formatter
    }()

    /// Grouping-separator-free formatter for editable numeric fields, so the rendered string always
    /// round-trips back through `price(from:)`.
    private let editableFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter
    }()

    func string(_ value: Decimal) -> String {
        decimalFormatter.string(from: value as NSDecimalNumber) ?? ""
    }

    func display(_ value: Decimal) -> String {
        currencyFormatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }

    /// A grouping-separator-free string for editable price fields. Unlike `string(_:)` (whose
    /// grouping separators corrupt `Decimal(string:)` parsing for values ≥ 1000), this round-trips
    /// cleanly through `price(from:)`.
    func editableString(_ value: Decimal) -> String {
        editableFormatter.string(from: value as NSDecimalNumber) ?? ""
    }

    /// Parses user-entered price text tolerantly. Accepts a comma or period decimal separator; the
    /// editable string is grouping-free, so any comma is treated as a decimal mark. Returns `nil` for
    /// empty or malformed input rather than silently accepting a partial numeric prefix.
    func price(from text: String) -> Decimal? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard
            !normalized.isEmpty,
            normalized.range(of: #"^-?\d+(\.\d+)?$"#, options: .regularExpression) != nil
        else {
            return nil
        }
        return Decimal(string: normalized)
    }
}
