//
//  DistanceFormatter.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import CoreLocation

enum DistanceFormatter {
    static func text(for meters: CLLocationDistance) -> String {
        if meters < 1000 {
            return "\(Int(meters)) m"
        }

        return String(format: "%.1f km", meters / 1000)
    }
}



