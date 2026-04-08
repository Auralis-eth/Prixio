import Foundation
import UIKit
@testable import Prixio

private final class ImageFixtureBundleToken: NSObject {}

enum ImageFixtureTestSupport {
    static let allFixtureNames = [
        "Screenshot 2026-04-02 at 3.53.44 PM",
        "IMG_0472",
        "IMG_0473",
        "IMG_0474",
        "IMG_0475",
        "IMG_0476",
        "IMG_0477",
        "IMG_0478",
        "IMG_0479",
        "IMG_0480",
        "IMG_0482",
        "IMG_0483"
    ]

    static let fixtureBatchA = Array(allFixtureNames.prefix(4))
    static let fixtureBatchB = Array(allFixtureNames.dropFirst(4).prefix(4))
    static let fixtureBatchC = Array(allFixtureNames.dropFirst(8))

    static func loadImage(
        named name: String,
        fileExtension: String = "png"
    ) throws -> UIImage {
        if let bundleImage = loadImageFromBundles(named: name, fileExtension: fileExtension) {
            return bundleImage
        }

        let sourceDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let candidateURLs = [
            sourceDirectory.appendingPathComponent("\(name).\(fileExtension)"),
            sourceDirectory.appendingPathComponent("Images/\(name).\(fileExtension)")
        ]

        for fileURL in candidateURLs {
            if let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) {
                return image
            }
        }

        throw FixtureError.missingImage(candidateURLs.map(\.path).joined(separator: ", "))
    }

    static func extractObservationResult(
        from image: UIImage
    ) async throws -> OCRService.ObservationResult {
        try await OCRService().extractObservations(from: image)
    }

    static func extractObservations(from image: UIImage) async throws -> [OCRTextObservation] {
        try await extractObservationResult(from: image).observations
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
            let candidateURLs = [
                bundle.url(forResource: name, withExtension: fileExtension),
                bundle.url(forResource: name, withExtension: fileExtension, subdirectory: "Images")
            ]

            for url in candidateURLs.compactMap({ $0 }) {
                if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                    return image
                }
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
