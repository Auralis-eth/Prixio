//
//  OCRService.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import UIKit
@preconcurrency import Vision

final class OCRService {
    func analyze(image: UIImage) async -> OCRResult {
        guard let cgImage = image.cgImage else {
            return PriceParsingService.extract(from: [""])
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

            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: cgImage)
                try? handler.perform([request])
            }
        }
    }
}
