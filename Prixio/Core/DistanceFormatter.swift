//
//  DistanceFormatter.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import CoreLocation

extension CLLocationDistance {
    var formatted: String {
        if self < 1000 {
            return "\(Int(self)) m"
        }
        return String(format: "%.1f km", self / 1000)
    }
}
