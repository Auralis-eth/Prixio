//
//  OCRService.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import UIKit
import Vision

extension UIImage {
    func extractOCR() async -> OCRResult {
        guard let cgImage = cgImage else {
            return PriceParsingService.extract(from: [OCRTextObservation(string: "", confidence: 0)])
        }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let textObservations = observations.compactMap { observation in
                    observation.topCandidates(1).first.map { candidate in
                        OCRTextObservation(string: candidate.string, confidence: candidate.confidence)
                    }
                }
                continuation.resume(returning: PriceParsingService.extract(from: textObservations))
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "en-CA", "fr-CA"]

            let handler = VNImageRequestHandler(cgImage: cgImage)
            try? handler.perform([request])
        }
    }
}
