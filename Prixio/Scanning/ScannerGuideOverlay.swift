//
//  ScannerGuideOverlay.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import SwiftUI

struct ScannerGuideOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            let frameWidth = min(geometry.size.width - 48, 320)

            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .strokeBorder(.white.opacity(0.34), lineWidth: 2)
                    .frame(width: frameWidth, height: frameWidth * 1.1)
                    .overlay(alignment: .topLeading) {
                        CornerBracket()
                            .stroke(.white, lineWidth: 4)
                            .frame(width: 36, height: 36)
                            .padding(14)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        CornerBracket(rotation: .degrees(180))
                            .stroke(.white, lineWidth: 4)
                            .frame(width: 36, height: 36)
                            .padding(14)
                    }

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.white.opacity(0.08))
                    .frame(width: frameWidth - 32, height: 120)
                    .overlay {
                        Text("Aim the tag inside the frame, then tap the shutter.")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(18)
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct CornerBracket: Shape {
    var rotation: Angle = .zero

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path.applying(CGAffineTransform(rotationAngle: CGFloat(rotation.radians)))
    }
}
