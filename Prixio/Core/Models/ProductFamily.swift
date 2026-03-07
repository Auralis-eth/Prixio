//
//  ProductFamily.swift
//  Prixio
//
//  Created by Codex on 3/6/26.
//

import Foundation

struct ProductFamily: Identifiable, Equatable {
    let id: String
    let title: String
    let supportingLines: [String]
    let keywords: [String]
    let itemNameHint: String?
    let priceCandidates: [PriceCandidate]
}
