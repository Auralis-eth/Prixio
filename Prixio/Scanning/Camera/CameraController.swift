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

    /// Becomes `true` once Deferred Start finishes initializing the photo output, meaning the
    /// session can service captures without additional startup latency. Used for diagnostics now
    /// and as a hook for gating the shutter later; the shutter stays enabled regardless because
    /// responsive capture buffers taps that arrive before the photo output is ready.
    @Published private(set) var isCaptureReady = false

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
                // Drop a duplicate request if a capture is already in flight, rather than
                // overwriting (and leaking) the pending continuation. Responsive capture makes
                // rapid shutter taps more likely to land, so this guard matters here.
                guard self.captureContinuation == nil else {
                    continuation.resume(returning: nil)
                    return
                }

                // Request the high-quality pipeline per capture. Must not exceed the photo
                // output's maxPhotoQualityPrioritization, which is set to .quality at configuration.
                settings.photoQualityPrioritization = .quality
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

                // Automatic mode: because preview is rendered by an AVCaptureVideoPreviewLayer (the
                // only non-deferred output), the session runs deferred start a short time after the
                // first preview frame. Defaults to true on iOS 26; set explicitly for clarity.
                self.session.automaticallyRunsDeferredStart = true

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

                // Defer the photo output so it does not block the first preview frame. The
                // *Supported flags are only valid once the output is attached to the session.
                if self.photoOutput.isDeferredStartSupported {
                    self.photoOutput.isDeferredStartEnabled = true
                }

                // Responsive capture buffers a shutter tap that arrives before the deferred photo
                // output has finished starting, so an early capture isn't dropped.
                self.photoOutput.isResponsiveCaptureEnabled = self.photoOutput.isResponsiveCaptureSupported

                // Pair deferred start with a quality-prioritized photo output.
                self.photoOutput.maxPhotoQualityPrioritization = .quality

                // Observe when deferred start runs so we can track capture readiness.
                self.session.setDeferredStartDelegate(self, deferredStartDelegateCallbackQueue: self.sessionQueue)

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
        // Resolve the continuation on sessionQueue so all access to captureContinuation is
        // serialized with capturePhoto's in-flight guard (the photo delegate is called on the
        // output's own queue, not sessionQueue).
        if let error {
            sessionQueue.async {
                let continuation = self.captureContinuation
                self.captureContinuation = nil
                continuation?.resume(throwing: error)
            }
            return
        }

        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        sessionQueue.async {
            let continuation = self.captureContinuation
            self.captureContinuation = nil
            continuation?.resume(returning: image)
        }
    }
}

extension CameraController: AVCaptureSessionDeferredStartDelegate {
    nonisolated func sessionWillRunDeferredStart(_ session: AVCaptureSession) {
        // Deferred outputs (the photo output) are about to start initializing.
    }

    nonisolated func sessionDidRunDeferredStart(_ session: AVCaptureSession) {
        // All deferred outputs are now started; the photo output is ready to capture.
        Task { @MainActor in
            isCaptureReady = true
        }
    }
}
