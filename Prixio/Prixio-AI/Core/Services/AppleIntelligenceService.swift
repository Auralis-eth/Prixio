import Foundation
import Vision
import VisionKit
import OSLog
import UIKit

/// Apple Intelligence service for OCR and ML
class AppleIntelligenceService: BaseService, MemoryManaged {

    private var processedImages: Int = 0

    override var dependencies: [String] { [] }

    override init(identifier: String = "AppleIntelligenceService") {
        super.init(identifier: identifier)
    }

    override func performInitialization() throws {
        Logging.shared.info("Initializing Apple Intelligence service")
        // Setup Vision and ML models
    }

    override func performShutdown() throws {
        Logging.shared.info("Shutting down Apple Intelligence service")
    }

    // MARK: - MemoryManaged

    var memoryUsage: Int {
        return processedImages * 1024 // Rough estimate
    }

    func freeMemoryResources() {
        Logging.shared.info("Freeing Apple Intelligence memory resources")
        processedImages = 0
    }

    func optimizeMemoryUsage() {
        Logging.shared.info("Optimizing Apple Intelligence memory usage")
    }

    // MARK: - OCR and Barcode Extraction

    struct OCRResult: Sendable {
        let detectedPrices: [Decimal]
        let currencyCode: String?
        let detectedBarcodes: [String]
        let fullText: String
        let confidence: Double
    }

    /// Perform Apple Intelligence OCR and barcode detection on image data
    func analyzeImageForPricesAndBarcodes(imageData: Data) async throws -> OCRResult {
        processedImages += 1

        // Create CGImage from data
        guard let uiImage = UIImage(data: imageData), let cgImage = uiImage.cgImage else {
            throw NSError(domain: "AppleIntelligenceService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid image data"])
        }

        // Configure requests: text recognition and barcode detection
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true

        let barcodeRequest = VNDetectBarcodesRequest()

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([textRequest, barcodeRequest])

        // Parse text results
        var fullText: String = ""
        var prices: [Decimal] = []
        var currencyCode: String? = nil
        var confidences: [Double] = []

        if let observations = textRequest.results as? [VNRecognizedTextObservation] {
            for obs in observations {
                guard let candidate = obs.topCandidates(1).first else { continue }
                let text = candidate.string
                fullText += text + "\n"
                confidences.append(Double(candidate.confidence))

                // Simple currency and price extraction
                // Match numbers like 12.34 or 1,234.56 possibly prefixed with $/€/£
                let pattern = #"([\$€£])?\s?([0-9]{1,3}(?:,[0-9]{3})*|[0-9]+)(?:\.[0-9]{2})?"#
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let range = NSRange(location: 0, length: text.utf16.count)
                    regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                        guard let match = match else { return }
                        var symbol: String? = nil
                        if match.numberOfRanges >= 2, let symRange = Range(match.range(at: 1), in: text) {
                            symbol = String(text[symRange])
                        }
                        if match.numberOfRanges >= 3, let numRange = Range(match.range(at: 2), in: text) {
                            let numString = String(text[numRange]).replacingOccurrences(of: ",", with: "")
                            if let decimal = Decimal(string: numString) {
                                prices.append(decimal)
                                if currencyCode == nil, let sym = symbol {
                                    currencyCode = Self.currencyCode(forSymbol: sym)
                                }
                            }
                        }
                    }
                }
            }
        }

        // Parse barcode results
        var barcodes: [String] = []
        if let barcodeObs = barcodeRequest.results as? [VNBarcodeObservation] {
            for b in barcodeObs {
                if let payload = b.payloadStringValue {
                    barcodes.append(payload)
                }
            }
        }

        let avgConfidence = confidences.isEmpty ? 0.0 : (confidences.reduce(0, +) / Double(confidences.count))
        return OCRResult(
            detectedPrices: prices,
            currencyCode: currencyCode,
            detectedBarcodes: barcodes,
            fullText: fullText.trimmingCharacters(in: .whitespacesAndNewlines),
            confidence: avgConfidence
        )
    }

    private static func currencyCode(forSymbol symbol: String) -> String? {
        switch symbol {
        case "$": return "USD"
        case "€": return "EUR"
        case "£": return "GBP"
        default: return nil
        }
    }
}
