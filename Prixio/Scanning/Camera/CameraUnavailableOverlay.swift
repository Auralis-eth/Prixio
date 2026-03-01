//
//  CameraUnavailableOverlay.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import SwiftUI
import AVFoundation

struct CameraUnavailableOverlay: View {
    let authorizationStatus: AVAuthorizationStatus
    let onImportPhoto: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "camera.fill")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.white)

            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            Text(subtitle)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.78))
                .frame(maxWidth: 280)

            HStack(spacing: 12) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("Settings+L", destination: url)
                }
                Button("Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else {
                        return
                    }
                    UIApplication.shared.open(url)
                }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)

                Button("Import Photo", action: onImportPhoto)
                    .buttonStyle(.bordered)
                    .tint(.white)
            }
        }
        .padding(24)
    }

    private var title: String {
        switch authorizationStatus {
        case .denied, .restricted:
            return "Camera access is required"
        default:
            return "Preparing camera"
        }
    }

    private var subtitle: String {
        switch authorizationStatus {
        case .denied, .restricted:
            return "Enable camera access in Settings to use the live scanner. You can still import an existing photo."
        default:
            return "Prixio uses the camera to capture price tags and freeze the frame for confirmation."
        }
    }
}
