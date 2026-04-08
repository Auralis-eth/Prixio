//
//  OCRService.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import CoreImage
import UIKit
import Vision

struct OCRService {
    struct Configuration {
        var allowsFallbackVariant = true
        var minimumObservationCountForSinglePass = 3
        var minimumAverageConfidenceForSinglePass: Float = 0.55
    }

    enum ImageVariant: String, Sendable {
        case normalized
        case highContrast
    }

    struct PreprocessingResult: Sendable {
        let variant: ImageVariant
        let orientationNormalized: Bool
        let contrastEnhanced: Bool
        let imageSize: CGSize
    }

    struct ObservationResult: Sendable {
        let observations: [OCRTextObservation]
        let preprocessing: PreprocessingResult
        let attemptedFallback: Bool
        let qualityReport: OCRQualityReport
    }

    private let configuration: Configuration
    private let ciContext = CIContext(options: nil)

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    func extractOCR(from image: UIImage) async -> OCRResult {
        let observationResult: ObservationResult

        do {
            observationResult = try await extractObservations(from: image)
        } catch {
            observationResult = ObservationResult(
                observations: [],
                preprocessing: PreprocessingResult(
                    variant: .normalized,
                    orientationNormalized: image.imageOrientation != .up,
                    contrastEnhanced: false,
                    imageSize: image.size
                ),
                attemptedFallback: false,
                qualityReport: OCRQualityReport(
                    selectedVariant: ImageVariant.normalized.rawValue,
                    attemptedFallback: false,
                    observationCount: 0,
                    priceSignalCount: 0,
                    descriptorCount: 0,
                    averageConfidence: 0,
                    confidenceSpread: 0,
                    selectedVariantScore: 0
                )
            )
        }

#if DEBUG
        debugLog(observationResult)
#endif

        if observationResult.observations.isEmpty {
            var result = await PriceParsingService.extract(from: [OCRTextObservation(string: "", confidence: 0)])
            result.ocrQualityReport = observationResult.qualityReport
            return result
        }

        var result = await PriceParsingService.extract(from: observationResult.observations)
        result.ocrQualityReport = observationResult.qualityReport
        return result
    }

    func extractObservations(from image: UIImage) async throws -> ObservationResult {
        let primaryVariant = try buildVariantImage(.normalized, from: image)
        let primaryObservations = try await performVisionOCR(on: primaryVariant.image)

        guard shouldTryFallbackVariant(primaryObservations) else {
            return ObservationResult(
                observations: primaryObservations,
                preprocessing: primaryVariant.preprocessing,
                attemptedFallback: false,
                qualityReport: buildQualityReport(
                    observations: primaryObservations,
                    preprocessing: primaryVariant.preprocessing,
                    attemptedFallback: false
                )
            )
        }

        guard configuration.allowsFallbackVariant else {
            return ObservationResult(
                observations: primaryObservations,
                preprocessing: primaryVariant.preprocessing,
                attemptedFallback: false,
                qualityReport: buildQualityReport(
                    observations: primaryObservations,
                    preprocessing: primaryVariant.preprocessing,
                    attemptedFallback: false
                )
            )
        }

        let fallbackVariant = try buildVariantImage(.highContrast, from: image)
        let fallbackObservations = try await performVisionOCR(on: fallbackVariant.image)
        let preferredResult = choosePreferredResult(
            primary: (primaryObservations, primaryVariant.preprocessing),
            fallback: (fallbackObservations, fallbackVariant.preprocessing)
        )

        return ObservationResult(
            observations: preferredResult.0,
            preprocessing: preferredResult.1,
            attemptedFallback: true,
            qualityReport: buildQualityReport(
                observations: preferredResult.0,
                preprocessing: preferredResult.1,
                attemptedFallback: true
            )
        )
    }

    private func buildVariantImage(
        _ variant: ImageVariant,
        from image: UIImage
    ) throws -> (image: CGImage, preprocessing: PreprocessingResult) {
        let normalizedImage = try normalizedImageForOCR(from: image)
        switch variant {
        case .normalized:
            return (
                image: normalizedImage,
                preprocessing: PreprocessingResult(
                    variant: .normalized,
                    orientationNormalized: image.imageOrientation != .up || image.cgImage == nil,
                    contrastEnhanced: false,
                    imageSize: CGSize(width: normalizedImage.width, height: normalizedImage.height)
                )
            )
        case .highContrast:
            let enhancedImage = try highContrastImage(from: normalizedImage)
            return (
                image: enhancedImage,
                preprocessing: PreprocessingResult(
                    variant: .highContrast,
                    orientationNormalized: image.imageOrientation != .up || image.cgImage == nil,
                    contrastEnhanced: true,
                    imageSize: CGSize(width: enhancedImage.width, height: enhancedImage.height)
                )
            )
        }
    }

    private func normalizedImageForOCR(from image: UIImage) throws -> CGImage {
        if image.imageOrientation == .up, let cgImage = image.cgImage {
            return cgImage
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        let renderedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }

        guard let cgImage = renderedImage.cgImage else {
            throw OCRServiceError.unreadableImage
        }

        return cgImage
    }

    private func highContrastImage(from cgImage: CGImage) throws -> CGImage {
        let input = CIImage(cgImage: cgImage)
        let filtered = input
            .applyingFilter(
                "CIColorControls",
                parameters: [
                    kCIInputSaturationKey: 0,
                    kCIInputContrastKey: 1.35,
                    kCIInputBrightnessKey: 0.02
                ]
            )
            .applyingFilter(
                "CIHighlightShadowAdjust",
                parameters: [
                    "inputHighlightAmount": 0.7,
                    "inputShadowAmount": 0.0
                ]
            )

        guard let output = ciContext.createCGImage(filtered, from: filtered.extent) else {
            throw OCRServiceError.preprocessingFailed
        }

        return output
    }

    private func performVisionOCR(on cgImage: CGImage) async throws -> [OCRTextObservation] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = (request.results as? [VNRecognizedTextObservation] ?? []).compactMap { observation in
                    let candidates = observation.topCandidates(2)
                    return candidates.first.map { candidate in
                        OCRTextObservation(
                            string: candidate.string,
                            confidence: candidate.confidence,
                            boundingBox: observation.boundingBox,
                            alternateStrings: alternateStrings(
                                for: candidate.string,
                                from: candidates.dropFirst().map(\.string)
                            )
                        )
                    }
                }
                continuation.resume(returning: observations)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "en-CA", "fr-CA"]

            let handler = VNImageRequestHandler(cgImage: cgImage)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func shouldTryFallbackVariant(_ observations: [OCRTextObservation]) -> Bool {
        guard !observations.isEmpty else {
            return true
        }

        if observations.count < configuration.minimumObservationCountForSinglePass {
            return true
        }

        let averageConfidence = observations.reduce(Float.zero) { $0 + $1.confidence } / Float(observations.count)
        if averageConfidence < configuration.minimumAverageConfidenceForSinglePass {
            return true
        }

        return observations.contains(where: { isLikelyPriceSignal(in: $0.string) }) == false
    }

    private func choosePreferredResult(
        primary: ([OCRTextObservation], PreprocessingResult),
        fallback: ([OCRTextObservation], PreprocessingResult)
    ) -> ([OCRTextObservation], PreprocessingResult) {
        let primaryScore = score(primary.0)
        let fallbackScore = score(fallback.0)
        return fallbackScore > primaryScore ? fallback : primary
    }

    private func score(_ observations: [OCRTextObservation]) -> Float {
        qualityMetrics(for: observations).score
    }

    private func buildQualityReport(
        observations: [OCRTextObservation],
        preprocessing: PreprocessingResult,
        attemptedFallback: Bool
    ) -> OCRQualityReport {
        let metrics = qualityMetrics(for: observations)
        return OCRQualityReport(
            selectedVariant: preprocessing.variant.rawValue,
            attemptedFallback: attemptedFallback,
            observationCount: observations.count,
            priceSignalCount: metrics.priceSignalCount,
            descriptorCount: metrics.descriptorCount,
            averageConfidence: metrics.averageConfidence,
            confidenceSpread: metrics.confidenceSpread,
            selectedVariantScore: metrics.score
        )
    }

    private func qualityMetrics(for observations: [OCRTextObservation]) -> (
        averageConfidence: Float,
        confidenceSpread: Float,
        priceSignalCount: Int,
        descriptorCount: Int,
        score: Float
    ) {
        guard !observations.isEmpty else {
            return (0, 0, 0, 0, 0)
        }

        let confidences = observations.map(\.confidence)
        let averageConfidence = confidences.reduce(Float.zero, +) / Float(observations.count)
        let minimumConfidence = confidences.min() ?? 0
        let maximumConfidence = confidences.max() ?? 0
        let priceSignalCount = observations.reduce(into: 0) { count, observation in
            if isLikelyPriceSignal(in: observation.string) {
                count += 1
            }
        }
        let descriptorCount = observations.reduce(into: 0) { count, observation in
            if isLikelyDescriptor(in: observation.string) {
                count += 1
            }
        }
        let confidenceSpread = maximumConfidence - minimumConfidence
        let score = averageConfidence
            + Float(observations.count) * 0.04
            + Float(priceSignalCount) * 0.3
            + Float(descriptorCount) * 0.06

        return (averageConfidence, confidenceSpread, priceSignalCount, descriptorCount, score)
    }

    private func isLikelyPriceSignal(in text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }

        if PriceParsingService.containsPriceSignal(in: trimmed) {
            return true
        }

        let compactPricePattern = #"^\$?\d{3,4}$"#
        return trimmed.range(of: compactPricePattern, options: .regularExpression) != nil
    }

    private func isLikelyDescriptor(in text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }

        let tokenCount = trimmed.split(whereSeparator: \.isWhitespace).count
        if tokenCount >= 2 {
            return true
        }

        let alphaCount = trimmed.unicodeScalars.filter(CharacterSet.letters.contains).count
        return alphaCount >= 6
    }

    private func alternateStrings(
        for primary: String,
        from candidates: [String]
    ) -> [String] {
        guard shouldPreserveAlternateCandidates(for: primary, candidates: candidates) else {
            return []
        }
        return candidates
    }

    private func shouldPreserveAlternateCandidates(
        for primary: String,
        candidates: [String]
    ) -> Bool {
        isLikelyPriceSignal(in: primary) || candidates.contains(where: isLikelyPriceSignal(in:))
    }

#if DEBUG
    private func debugLog(_ result: ObservationResult) {
        let summary = result.observations.map(\.string).prefix(5).joined(separator: " | ")
        print("========== OCR SERVICE ==========")
        print("variant: \(result.preprocessing.variant.rawValue)")
        print("attemptedFallback: \(result.attemptedFallback)")
        print("orientationNormalized: \(result.preprocessing.orientationNormalized)")
        print("contrastEnhanced: \(result.preprocessing.contrastEnhanced)")
        print("imageSize: \(Int(result.preprocessing.imageSize.width))x\(Int(result.preprocessing.imageSize.height))")
        print("observationCount: \(result.observations.count)")
        print("priceSignalCount: \(result.qualityReport.priceSignalCount)")
        print("descriptorCount: \(result.qualityReport.descriptorCount)")
        print("averageConfidence: \(result.qualityReport.averageConfidence)")
        print("confidenceSpread: \(result.qualityReport.confidenceSpread)")
        print("selectedVariantScore: \(result.qualityReport.selectedVariantScore)")
        print("preview: \(summary)")
        print("===============================")
    }
#endif
}

enum OCRServiceError: Error {
    case unreadableImage
    case preprocessingFailed
}

extension UIImage {
    func extractOCR() async -> OCRResult {
        await OCRService().extractOCR(from: self)
    }
}
