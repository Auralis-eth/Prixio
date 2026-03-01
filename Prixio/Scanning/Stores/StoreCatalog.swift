//
//  StoreCatalog.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import CoreLocation

enum StoreCatalog {
    static let commonChains: [(name: String, aliases: [String])] = [
        ("Unknown", []),
        ("Co-op", ["Calgary Co-op", "COOP", "Co-op"]),
        ("Sobeys", ["Sobeys"]),
        ("Safeway", ["Safeway"]),
        ("Real Canadian Superstore", ["Superstore", "Real Canadian Superstore", "RCSS"]),
        ("Walmart", ["Walmart"])
    ]

    static func inferredChain(from text: String) -> String? {
        let lowered = text.lowercased()
        return commonChains.first { chain in
            chain.name != "Unknown" && chain.aliases.contains { lowered.contains($0.lowercased()) }
        }?.name
    }

    static func mapItemIdentifier(name: String, coordinate: CLLocationCoordinate2D?) -> String {
        let lat = coordinate?.latitude ?? 0
        let lon = coordinate?.longitude ?? 0
        return "\(name)-\(lat)-\(lon)"
    }
}
