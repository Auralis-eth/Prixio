//
//  CurrencyFormatter.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import Foundation

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
        formatter.currencyCode = "CAD"
        return formatter
    }()
    
    func string(_ value: Decimal) -> String {
        decimalFormatter.string(from: value as NSDecimalNumber) ?? ""
    }
    
    func display(_ value: Decimal) -> String {
        currencyFormatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }
}
