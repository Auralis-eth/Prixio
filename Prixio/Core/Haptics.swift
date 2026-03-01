//
//  Haptics.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import UIKit

enum Haptics {
    static func impact() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

