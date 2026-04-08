//
//  PriceParsingService.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import CoreGraphics
import Foundation

enum PriceParsingService {
    enum SceneClassification: String, Sendable {
        case singleTag
        case multiTag
        case promoCard
        case receiptLike
        case unclear
    }

    enum EvidenceClusterRole: String, Sendable {
        case productText
        case priceColumn
        case promoBanner
        case unitDetail
        case noise
    }

    struct VocabularySignal {
        var frequency: Int
        var lineIndexes: [Int]
    }

    struct UnitDetectionSignal {
        let unit: UnitType
        let score: Int
        let location: String.Index
    }

    struct ItemNameCandidate {
        let line: String
        let score: Int
        let lineIndex: Int
    }

    struct SpatialObservationGroup: Sendable {
        let observations: [OCRTextObservation]
        let score: Float
    }

    struct EvidenceCluster: Sendable {
        let observations: [OCRTextObservation]
        let lines: [String]
        let priceCandidates: [PriceCandidate]
        let itemNameHint: String?
        let detectedUnit: UnitType?
        let resolvedQuantity: Decimal?
        let frame: CGRect?
        let centroid: CGPoint?
        let linkedClusterIndexes: [Int]
        let ownershipConfidence: Float
        let role: EvidenceClusterRole
        let score: Float
    }

    struct HeuristicExtractionSnapshot: Sendable {
        let supportedObservations: [OCRTextObservation]
        let spatialGroups: [SpatialObservationGroup]
        let evidenceClusters: [EvidenceCluster]
        let winningClusterIndex: Int?
        let cleanedObservations: [OCRTextObservation]
        let normalizedObservations: [OCRTextObservation]
        let consolidatedObservations: [OCRTextObservation]
        let rawText: String
        let normalizedText: String
        let lines: [String]
        let sceneClassification: SceneClassification
        let priceCandidates: [PriceCandidate]
        let detectedUnit: UnitType?
        let itemNameHint: String?
        let resolvedQuantity: Decimal?
        let heuristicConfidence: Float
    }

    enum ExtractionWeakness: String, CaseIterable, Sendable {
        case noPriceCandidates
        case multipleCompetingPrices
        case missingItemName
        case missingUnit
        case missingQuantity
        case lowConfidence
        case sparseOCR
        case possibleMultiProductScan
    }

    struct ExtractionAmbiguityReport: Sendable {
        let weaknesses: [ExtractionWeakness]

        var shouldUseFoundationModel: Bool {
            let severeWeaknesses: Set<ExtractionWeakness> = [
                .noPriceCandidates,
                .multipleCompetingPrices,
                .possibleMultiProductScan
            ]
            if !severeWeaknesses.isDisjoint(with: weaknesses) {
                return true
            }

            let weaknessSet = Set(weaknesses)

            if weaknessSet.contains(.sparseOCR) || weaknessSet.contains(.lowConfidence) {
                return weaknessSet.count >= 2
            }

            if weaknessSet.contains(.missingItemName) && weaknessSet.contains(.missingUnit) {
                return true
            }

            return weaknessSet.count >= 3
        }
    }

    static let currencyPattern = #"\$?\s*(\d+[.,]\d{2})"#
    static let multiBuyPattern = #"(\d+)\s*(?:/|for)\s*\$?\s*(\d+(?:[.,]\d{2})?)"#
    static let splitCurrencyPattern = #"(^|[^\d])(\d{1,3})\s*(?:\n|\s)\s*(\d{2})(?=$|[^\d])"#
    static let impliedCurrencyPattern = #"(^|[^\d])(\d{3,4})(?=$|[^\d])"#
    static let simplePricePattern = #"\$?\s*\d+[.,]\d{2}"#
    static let promoMarkerPattern = #"\b(member|club|loyalty|sale|special|deal)\b"#
    static let regularPriceMarkerPattern = #"\b(regular|reg(?:ular)?|was|original|compare)\b"#
    static let depositMarkerPattern = #"\b(deposit|dep|crv|enviro|fee)\b"#
    static let unitLabelPattern = #"\b(ea|each)\b|/(lb|lbs|kg|l|liter|litre|100\s?g)\b"#
    static let quantityFractionPattern = #"\b(\d+)\s*/\s*(\d+)\s*(?:lb|lbs|kg|l|liter|litre)\b"#
    static let quantityDecimalPattern = #"\b(\d+(?:[.,]\d+)?)\s*(?:lb|lbs|kg|l|liter|litre)\b"#
    static let buyGetPattern = #"\bbuy\s+(\d+|one|two|three|four|five)\s+get\s+(\d+|one|two|three|four|five)(?:\s+free)?\b"#
    static let monthNamePattern = #"\b(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december)\b"#
    static let shelfCodePattern = #"^[A-Z0-9]{2,}(?:[/\-][A-Z0-9]{2,})+$"#
    static let skuLikeTokenPattern = #"^[A-Z]*\d+[A-Z\d\-\/]*$"#
    static let poundsPerKilogram = Decimal(string: "2.2046226218")!
    static let supportedOCRLinePattern = #"^[\p{Latin}\p{N}\p{P}\p{Sc}\p{Zs}]+$"#
    static let explicitTokenCorrections: [String: String] = [
        "tutch": "dutch",
        "sparkli": "sparkling",
        "chese": "cheese",
        "chees": "cheese",
        "bbqma": "bbq"
    ]
    static let receiptMarkers = [
        "subtotal",
        "total",
        "tax",
        "hst",
        "gst",
        "change",
        "thank you",
        "receipt",
        "visa",
        "mastercard"
    ]
    static let itemNameIgnoredTokens: Set<String> = [
        "sale",
        "member",
        "members",
        "club",
        "loyalty",
        "special",
        "deal",
        "regular",
        "reg",
        "was",
        "compare",
        "price",
        "ea",
        "each",
        "lb",
        "lbs",
        "kg",
        "l",
        "liter",
        "litre",
        "pk",
        "pack",
        "ct",
        "count",
        "per"
    ]

    /// Converts raw OCR observations into a best-effort structured grocery price result.
    ///
    /// Conceptually, this method runs a parsing pipeline over noisy OCR text: it keeps
    /// lines that look relevant, removes obvious junk, applies OCR-specific
    /// normalization, and consolidates fragmented observations into more coherent text.
    /// From that cleaner input, it extracts likely price candidates, detects the unit
    /// of measure, estimates quantity, and surfaces a likely item-name hint.
    ///
    /// The final `OCRResult` preserves the raw OCR text while also returning the most
    /// plausible structured values and the supporting lines used to infer them.
    ///
    /// - Parameter observations: Raw text observations returned by the OCR layer.
    /// - Returns: A normalized `OCRResult` containing the most likely price metadata
    ///   inferred from those observations.
    static func extract(from observations: [OCRTextObservation]) async -> OCRResult {
        let snapshot = PriceParsingSnapshotBuilder().buildHeuristicSnapshot(from: observations)
        let ambiguity = PriceParsingConfidenceResolver().analyzeAmbiguity(in: snapshot)
        let heuristicResult = PriceParsingConfidenceResolver().makeOCRResult(from: snapshot)

#if DEBUG
        debugLogPipeline(
            observations: observations,
            snapshot: snapshot,
            ambiguity: ambiguity,
            result: heuristicResult,
            stage: "heuristic"
        )
#endif

        let assistedExtractor = PriceParsingAssistedExtractor()

        guard ambiguity.shouldUseFoundationModel else {
            return heuristicResult
        }

        guard !assistedExtractor.shouldSkipFoundationModelEscalation(snapshot: snapshot, ambiguity: ambiguity) else {
            return heuristicResult
        }

        guard let assisted = try? await assistedExtractor.resolveWithFoundationModel(
            snapshot: snapshot,
            ambiguity: ambiguity
        ) else {
            return heuristicResult
        }

        let mergedResult = assistedExtractor.mergeAssistedExtraction(snapshot: snapshot, assisted: assisted)

#if DEBUG
        debugLogPipeline(
            observations: observations,
            snapshot: snapshot,
            ambiguity: ambiguity,
            result: mergedResult,
            stage: "assisted"
        )
#endif

        return mergedResult
    }

    static func normalize(price: Decimal, unit: UnitType, quantity: Decimal?) -> (Decimal, UnitType)? {
        let effectivePrice = unitPrice(price: price, quantity: quantity)

        switch unit {
        case .lb:
            return (effectivePrice * poundsPerKilogram, .kg)
        case .kg:
            return (effectivePrice, .kg)
        case .each:
            return (effectivePrice, .each)
        case .liter:
            return (effectivePrice, .liter)
        case .hundredGrams:
            return (effectivePrice * 10, .kg)
        }
    }

    static func unitPrice(price: Decimal, quantity: Decimal?) -> Decimal {
        guard let quantity, quantity > 0 else {
            return price
        }
        return price / quantity
    }

    static func looksLikeReceipt(text: String) -> Bool {
        let lowered = text.lowercased()
        let markerCount = receiptMarkers.reduce(into: 0) { count, marker in
            if lowered.contains(marker) {
                count += 1
            }
        }
        return markerCount >= 2
    }

#if DEBUG
    static func debugLogPipeline(
        observations: [OCRTextObservation],
        snapshot: HeuristicExtractionSnapshot,
        ambiguity: ExtractionAmbiguityReport,
        result: OCRResult,
        stage: String
    ) {
        print("========== PARSER DEBUG (\(stage.uppercased())) ==========")
        print("raw observations (\(observations.count)):")
        for (index, observation) in observations.enumerated() {
            print("  [\(index)] \(debugDescription(for: observation))")
        }

        print("spatial groups (\(snapshot.spatialGroups.count)):")
        for (index, group) in snapshot.spatialGroups.enumerated() {
            let lines = group.observations.map(\.string).joined(separator: " | ")
            print("  [\(index)] score=\(String(format: "%.3f", group.score)) lines=\(lines)")
        }
        print("evidence clusters (\(snapshot.evidenceClusters.count)):")
        for (index, cluster) in snapshot.evidenceClusters.enumerated() {
            let clusterPrices = cluster.priceCandidates.map { $0.value }
            print(
                "  [\(index)] role=\(cluster.role.rawValue) score=\(String(format: "%.3f", cluster.score)) item=\(cluster.itemNameHint ?? "nil") prices=\(clusterPrices)"
            )
        }
        print("winning cluster index: \(snapshot.winningClusterIndex.map(String.init) ?? "nil")")

        print("cleaned observations: \(snapshot.cleanedObservations.map(\.string))")
        print("normalized observations: \(snapshot.normalizedObservations.map(\.string))")
        print("consolidated observations: \(snapshot.consolidatedObservations.map(\.string))")
        print("scene classification: \(snapshot.sceneClassification.rawValue)")
        print("heuristic confidence: \(snapshot.heuristicConfidence)")
        print("price candidates (\(snapshot.priceCandidates.count)):")
        for (index, candidate) in snapshot.priceCandidates.enumerated() {
            print(
                """
                  [\(index)] value=\(candidate.value) priority=\(candidate.priority) confidence=\(candidate.confidence) source=\(candidate.sourceText) quantity=\(candidate.quantity.map { "\($0)" } ?? "nil")
                """
            )
        }

        print("item name hint: \(snapshot.itemNameHint ?? "nil")")
        print("detected unit: \(snapshot.detectedUnit?.rawValue ?? "nil")")
        print("resolved quantity: \(snapshot.resolvedQuantity.map { "\($0)" } ?? "nil")")
        print("ambiguity weaknesses: \(ambiguity.weaknesses.map(\.rawValue))")
        print("should use foundation model: \(ambiguity.shouldUseFoundationModel)")
        print("result item: \(result.itemNameHint ?? "nil")")
        print("result price: \(result.price.map { "\($0)" } ?? "nil")")
        print("result review: \(result.review.issues.map(\.rawValue)) usedFM=\(result.review.usedFoundationModel)")
        print("supporting lines: \(result.supportingLines)")
        print("============================================")
    }

    static func debugDescription(for observation: OCRTextObservation) -> String {
        let boxDescription: String
        if let box = observation.boundingBox {
            boxDescription = String(
                format: "box=(x:%.3f y:%.3f w:%.3f h:%.3f)",
                box.origin.x,
                box.origin.y,
                box.size.width,
                box.size.height
            )
        } else {
            boxDescription = "box=nil"
        }

        return "\"\(observation.string)\" conf=\(observation.confidence) \(boxDescription)"
    }

    static func _test_buildHeuristicSnapshot(_ observations: [OCRTextObservation]) -> HeuristicExtractionSnapshot {
        PriceParsingSnapshotBuilder().buildHeuristicSnapshot(from: observations)
    }

    static func _test_makeOCRResult(_ observations: [OCRTextObservation]) -> OCRResult {
        let snapshot = PriceParsingSnapshotBuilder().buildHeuristicSnapshot(from: observations)
        return PriceParsingConfidenceResolver().makeOCRResult(from: snapshot)
    }

    static func _test_analyzeAmbiguity(_ observations: [OCRTextObservation]) -> ExtractionAmbiguityReport {
        let snapshot = PriceParsingSnapshotBuilder().buildHeuristicSnapshot(from: observations)
        return PriceParsingConfidenceResolver().analyzeAmbiguity(in: snapshot)
    }

    static func _test_assistedExtractionResult(
        targetLineIndexes: [Int],
        selectedPriceCandidateIndex: Int?,
        selectedPriceKind: AssistedPriceKind,
        canonicalItemName: String?,
        ambiguityNotes: [String],
        confidenceBucket: AssistedConfidenceBucket
    ) -> AssistedExtractionResult {
        AssistedExtractionResult(
            targetLineIndexes: targetLineIndexes,
            selectedPriceCandidateIndex: selectedPriceCandidateIndex,
            selectedPriceKind: selectedPriceKind,
            canonicalItemName: canonicalItemName,
            ambiguityNotes: ambiguityNotes,
            confidenceBucket: confidenceBucket
        )
    }

    static func _test_mergeAssistedExtraction(
        observations: [OCRTextObservation],
        assisted: AssistedExtractionResult
    ) -> OCRResult {
        let snapshot = PriceParsingSnapshotBuilder().buildHeuristicSnapshot(from: observations)
        return PriceParsingAssistedExtractor().mergeAssistedExtraction(snapshot: snapshot, assisted: assisted)
    }

    static func _test_consolidateObservations(_ observations: [OCRTextObservation]) -> [OCRTextObservation] {
        observations.consolidateObservations()
    }
#endif
}
