import Foundation
import UIKit
import Vision
@testable import Prixio

private final class ImageFixtureBundleToken: NSObject {}

enum ImageFixtureTestSupport {
    static func loadImage(
        named name: String,
        fileExtension: String = "png"
    ) throws -> UIImage {
        if let bundleImage = loadImageFromBundles(named: name, fileExtension: fileExtension) {
            return bundleImage
        }

        let sourceDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        let fileURL = sourceDirectory.appendingPathComponent("\(name).\(fileExtension)")
        guard
            let data = try? Data(contentsOf: fileURL),
            let image = UIImage(data: data)
        else {
            throw FixtureError.missingImage(fileURL.path)
        }

        return image
    }

    static func extractObservations(from image: UIImage) async throws -> [OCRTextObservation] {
        let cgImage: CGImage
        if let existingCGImage = image.cgImage {
            cgImage = existingCGImage
        } else {
            guard let renderedImage = image.preparingForDisplay(),
                  let preparedCGImage = renderedImage.cgImage else {
                throw FixtureError.unreadableImage
            }
            cgImage = preparedCGImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = (request.results as? [VNRecognizedTextObservation] ?? []).compactMap { observation in
                    observation.topCandidates(1).first.map { candidate in
                        OCRTextObservation(
                            string: candidate.string,
                            confidence: candidate.confidence,
                            boundingBox: observation.boundingBox
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

    private static func loadImageFromBundles(
        named name: String,
        fileExtension: String
    ) -> UIImage? {
        let candidateBundles = [
            Bundle(for: ImageFixtureBundleToken.self),
            Bundle.main
        ] + Bundle.allBundles + Bundle.allFrameworks

        let searchedBundles = Array(NSOrderedSet(array: candidateBundles)).compactMap { $0 as? Bundle }
        for bundle in searchedBundles {
            guard let url = bundle.url(forResource: name, withExtension: fileExtension) else {
                continue
            }
            if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                return image
            }
        }

        return nil
    }

    enum FixtureError: LocalizedError {
        case missingImage(String)
        case unreadableImage

        var errorDescription: String? {
            switch self {
            case .missingImage(let path):
                return "Missing image fixture at \(path)"
            case .unreadableImage:
                return "Unable to create a CGImage from the fixture image"
            }
        }
    }
}
