//
//  CameraController.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import AVFoundation
import Combine
import UIKit

final class CameraController: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "Prixio.CameraSession")
    private let photoOutput = AVCapturePhotoOutput()
    private var isConfigured = false
    private var captureContinuation: CheckedContinuation<UIImage?, Error>?

    func prepare() async {
        if authorizationStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            await MainActor.run {
                authorizationStatus = granted ? .authorized : .denied
            }
        }

        guard authorizationStatus == .authorized else {
            return
        }

        if !isConfigured {
            await configureSession()
        }
        await startSession()
    }

    func capturePhoto(flashEnabled: Bool) async throws -> UIImage? {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                let settings = AVCapturePhotoSettings()
                if self.photoOutput.supportedFlashModes.contains(flashEnabled ? .on : .off) {
                    settings.flashMode = flashEnabled ? .on : .off
                }
                self.captureContinuation = continuation
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    func resumePreview() async {
        guard authorizationStatus == .authorized else {
            return
        }

        if !isConfigured {
            await configureSession()
        }
        await startSession()
    }

    private func configureSession() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                guard !self.isConfigured else {
                    continuation.resume()
                    return
                }

                self.session.beginConfiguration()
                self.session.sessionPreset = .photo

                defer {
                    self.session.commitConfiguration()
                    continuation.resume()
                }

                guard
                    let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                    let input = try? AVCaptureDeviceInput(device: device),
                    self.session.canAddInput(input),
                    self.session.canAddOutput(self.photoOutput)
                else {
                    return
                }

                self.session.addInput(input)
                self.session.addOutput(self.photoOutput)
                self.isConfigured = true
            }
        }
    }

    private func startSession() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                continuation.resume()
            }
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            Task { @MainActor in
                captureContinuation?.resume(throwing: error)
                captureContinuation = nil
            }
            return
        }

        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        Task { @MainActor in
            captureContinuation?.resume(returning: image)
            captureContinuation = nil
        }
    }
}
