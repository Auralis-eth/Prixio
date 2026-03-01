//
//  CurrencyFormatter.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import Foundation

enum CurrencyFormatter {
    static func string(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? ""
    }

    static func display(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "CAD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }
}

