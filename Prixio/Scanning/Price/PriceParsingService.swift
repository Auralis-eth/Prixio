//
//  PriceParsingService.swift
//  Prixio
//
//  Created by Daniel Bell on 3/1/26.
//

import Foundation
import FoundationModels

enum PriceParsingService {

    private struct ProductFamilyCluster {
        var observations: [OCRTextObservation]
        var keywordFrequency: [String: Int]
        var firstIndex: Int
        var lastIndex: Int
    }

    private struct ObservationSignals {
        let keywords: Set<String>
        let hasPriceSignal: Bool
        let hasSizeSignal: Bool
        let hasPromotionSignal: Bool
    }

    private struct VocabularySignal {
        var frequency: Int
        var lineIndexes: [Int]
    }

    private static let currencyPattern = #"\$?\s*(\d+[.,]\d{2})"#
    private static let multiBuyPattern = #"(\d+)\s*(?:/|for)\s*\$?\s*(\d+(?:[.,]\d{2})?)"#
    private static let splitCurrencyPattern = #"(^|[^\d])(\d{1,3})\s*(?:\n|\s)\s*(\d{2})(?=$|[^\d])"#
    private static let impliedCurrencyPattern = #"(^|[^\d])(\d{3,4})(?=$|[^\d])"#
    private static let simplePricePattern = #"\$?\s*\d+[.,]\d{2}"#
    private static let quantityFractionPattern = #"\b(\d+)\s*/\s*(\d+)\s*(?:lb|lbs|kg|l|liter|litre)\b"#
    private static let quantityDecimalPattern = #"\b(\d+(?:[.,]\d+)?)\s*(?:lb|lbs|kg|l|liter|litre)\b"#
    private static let monthNamePattern = #"\b(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december)\b"#
    private static let shelfCodePattern = #"^[A-Z0-9]{2,}(?:[/\-][A-Z0-9]{2,})+$"#
    private static let skuLikeTokenPattern = #"^[A-Z]*\d+[A-Z\d\-\/]*$"#
    private static let poundsPerKilogram = Decimal(string: "2.2046226218")!
    private static let supportedOCRLinePattern = #"^[\p{Latin}\p{N}\p{P}\p{Zs}]+$"#
    private static let familyStopWords: Set<String> = [
        "a", "an", "and", "at", "buy", "each", "for", "from", "in", "is", "of", "on", "or", "price",
        "sale", "save", "selected", "the", "to", "varieties", "with"
    ]
    private static let explicitTokenCorrections: [String: String] = [
        "tutch": "dutch",
        "sparkli": "sparkling",
        "chese": "cheese",
        "chees": "cheese",
        "bbqma": "bbq"
    ]
    private static let receiptMarkers = [
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

    static func extract(from observations: [OCRTextObservation]) -> OCRResult {
        // TODO: move each to a new struct, call as function
        let supportedObservations = observations.filter {
            isSupportedOCRLine($0.string)
        }
        let cleanedObservations = removeObviousNoise(from: supportedObservations)
        let normalizedObservations = applyContextualNormalization(to: cleanedObservations)
        let consolidatedObservations = normalizedObservations.consolidateObservations()
        let productFamilies = buildProductFamilies(from: consolidatedObservations)
        let primaryFamily = primaryFamily(from: productFamilies)
        let text = consolidatedObservations.map(\.string)

        
        // TODO: Foundation Model the text
        // https://developer.apple.com/documentation/FoundationModels
        let session = LanguageModelSession(instructions: Instructions {
            """
            You are a Retail Shelf Assistant. Translate raw OCR text from store shelf images into clean, structured product entries.

            PERSONA: High-precision retail data extractor. Convert OCR noise into a single, accurate shopping list entry.

            EXTRACTION RULES

            Product Identification:
            - Combine brand + variety/flavor + size into one descriptor (e.g., "Oreo Double Stuf 15.35oz")
            - If a brand name appears multiple times, treat it as the target product
            - Ignore category signage, neighboring items, shelf location codes, and stock numbers

            Price Identification (priority order):
            1. Promotional price — "Buy X for $Y" or "2 for $X" always takes precedence
            2. Standard format — $X.XX or X.XX near keywords: "Sale", "Each", "lb", "Price"
            3. Raw digit clusters — interpret 3–4 digit strings near the product as currency (e.g., "499" → "$4.99")

            De-Noising:
            - Remove duplicates, OCR artifacts (e.g., "|||", "___", "---"), barcodes, and unrelated metadata
            - Discard partial text from neighboring products

            ERROR HANDLING
            - No price found → Price: Price not detected
            - Text too garbled to identify product → Unable to identify item from OCR data
            """
        })
        let prompt = Prompt {
            "Summarize this OCR text from my purchase for my record keeping:"
            text.map { Prompt($0) }
        }
        Task {
            do {
                let summary = try await session.respond(to: prompt).content
                print(summary)
            } catch let error as LanguageModelSession.GenerationError {
//                switch error {
//                case .historyTokenExpired:
//                    print("History Token expired.")
//                case .exceededContextWindowSize(let string):
//                    print("Exceeded context window size. Generated: \(string)")
//                case .assetsUnavailable(_):
//                    <#code#>
//                case .guardrailViolation(_):
//                    <#code#>
//                case .unsupportedGuide(_):
//                    <#code#>
//                case .unsupportedLanguageOrLocale(_):
//                    <#code#>
//                case .decodingFailure(_):
//                    <#code#>
//                case .rateLimited(_):
//                    <#code#>
//                case .concurrentRequests(_):
//                    <#code#>
//                case .refusal(_, _):
//                    <#code#>
//                default:
//                    print(error)
//                }
                
                if let failureReason = error.failureReason {
                    print(failureReason)
                }
                if let recoverySuggestion = error.recoverySuggestion {
                    print(recoverySuggestion)
                }
                if let helpAnchor = error.helpAnchor {
                    print(helpAnchor)
                }
            } catch {
                print(error.localizedDescription)
            }
        }
        
        
        
        let normalizedText = text.joined(separator: "\n").replacingOccurrences(of: ",", with: ".")
        let priceCandidates = primaryFamily?.priceCandidates ?? extractPriceCandidates(from: consolidatedObservations)
        let unitScopeText = primaryFamily?.supportingLines.joined(separator: "\n") ?? ""
        let unit = detectUnit(in: unitScopeText.isEmpty ? normalizedText : unitScopeText)
        let lines = (unitScopeText.isEmpty ? normalizedText : unitScopeText)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let itemNameHint = lines.first { line in
            !line.contains("$") && detectUnit(in: line) == nil && !line.contains(where: { $0.isNumber })
        }

        let resolvedQuantity = priceCandidates.first?.quantity ?? detectQuantity(
            in: unitScopeText.isEmpty ? normalizedText : unitScopeText,
            unit: unit
        )

        return OCRResult(
            rawText: text.joined(separator: "\n"),
            itemNameHint: itemNameHint,
            price: priceCandidates.first?.value,
            unit: unit,
            quantity: resolvedQuantity,
            confidence: priceCandidates.first?.confidence ?? averageConfidence(in: consolidatedObservations) ?? 0.1,
            priceCandidates: priceCandidates,
            productFamilies: productFamilies
        )
    }

    private static func isSupportedOCRLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }

        guard let regex = try? NSRegularExpression(pattern: supportedOCRLinePattern) else {
            return true
        }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        return regex.firstMatch(in: trimmed, range: range) != nil
    }

    private static func removeObviousNoise(from observations: [OCRTextObservation]) -> [OCRTextObservation] {
        var seenKeys = Set<String>()

        return observations.compactMap { observation in
            let sanitized = observation.string.sanitizeOCRLine()
            guard !sanitized.isEmpty else {
                return nil
            }

            guard !isObviousNoiseLine(sanitized) else {
                return nil
            }

            let key = sanitized.normalizedWords().joined(separator: " ")
            guard !key.isEmpty else {
                return nil
            }

            guard seenKeys.insert(key).inserted else {
                return nil
            }

            return OCRTextObservation(string: sanitized, confidence: observation.confidence)
        }
    }

    private static func isObviousNoiseLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return true
        }

        let words = trimmed.normalizedWords()
        guard !words.isEmpty else {
            return true
        }

        let hasDigits = trimmed.contains(where: \.isNumber)
        let hasLetters = trimmed.unicodeScalars.contains { CharacterSet.letters.contains($0) }
        let hasPriceSignal = containsPriceSignal(in: trimmed)
        let hasUnitSignal = detectUnit(in: trimmed) != nil || containsExplicitSizeToken(in: trimmed)

        if isLikelyShelfCode(trimmed) || isLikelySKU(trimmed) {
            return true
        }

        if !hasLetters && hasDigits && !hasPriceSignal {
            return true
        }

        if words.count == 1 && !hasPriceSignal && !hasUnitSignal {
            let token = words[0]
            if hasDigits {
                return true
            }
            if token.count <= 3 {
                return true
            }
            if token.count >= 7 && !containsVowel(token) {
                return true
            }
        }

        if words.count == 2 && !hasPriceSignal && !hasUnitSignal && words.allSatisfy({ $0.count <= 3 }) {
            return true
        }

        return false
    }

    private static func containsPriceSignal(in text: String) -> Bool {
        if text.contains("$") {
            return true
        }

        guard let regex = try? NSRegularExpression(pattern: simplePricePattern) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    private static func isLikelyShelfCode(_ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: shelfCodePattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    private static func isLikelySKU(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 4 else {
            return false
        }
        guard compact.contains(where: \.isNumber) else {
            return false
        }
        guard compact.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else {
            return false
        }
        guard let regex = try? NSRegularExpression(pattern: skuLikeTokenPattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(compact.startIndex..., in: compact)
        return regex.firstMatch(in: compact, range: range) != nil
    }

    private static func containsVowel(_ token: String) -> Bool {
        token.range(of: "[aeiou]", options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func applyContextualNormalization(to observations: [OCRTextObservation]) -> [OCRTextObservation] {
        let vocabularyFrequency = contextualVocabulary(from: observations)

        return observations.enumerated().map { index, observation in
            let repairedPackText = repairPackSizeNoise(in: observation.string)
            let correctedTokens = repairedPackText
                .split(whereSeparator: \.isWhitespace)
                .map { token in
                    correctedToken(
                        String(token),
                        vocabularyFrequency: vocabularyFrequency,
                        observationConfidence: observation.confidence,
                        lineIndex: index
                    )
                }
                .joined(separator: " ")

            return OCRTextObservation(
                string: correctedTokens.sanitizeOCRLine(),
                confidence: observation.confidence
            )
        }
    }

    private static func contextualVocabulary(from observations: [OCRTextObservation]) -> [String: VocabularySignal] {
        observations.enumerated().reduce(into: [:]) { frequency, entry in
            let index = entry.offset
            let observation = entry.element
            let words = observation.string.normalizedWords()
            for word in words where word.count >= 4 {
                if var signal = frequency[word] {
                    signal.frequency += 1
                    signal.lineIndexes.append(index)
                    frequency[word] = signal
                } else {
                    frequency[word] = VocabularySignal(frequency: 1, lineIndexes: [index])
                }
            }
        }
    }

    private static func correctedToken(
        _ token: String,
        vocabularyFrequency: [String: VocabularySignal],
        observationConfidence: Float,
        lineIndex: Int
    ) -> String {
        let characterSet = CharacterSet.alphanumerics
        let prefix = String(token.prefix { scalar in
            guard let value = scalar.unicodeScalars.first else {
                return false
            }
            return !characterSet.contains(value)
        })
        let suffix = String(token.reversed().prefix { scalar in
            guard let value = scalar.unicodeScalars.first else {
                return false
            }
            return !characterSet.contains(value)
        }.reversed())
        let coreStartIndex = token.index(token.startIndex, offsetBy: prefix.count)
        let coreEndIndex = token.index(token.endIndex, offsetBy: -suffix.count)
        guard coreStartIndex <= coreEndIndex else {
            return token
        }
        let core = String(token[coreStartIndex..<coreEndIndex])
        guard !core.isEmpty else {
            return token
        }

        let normalizedCore = core.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if let explicit = explicitTokenCorrections[normalizedCore.lowercased()] {
            return prefix + applyCasePattern(from: core, to: explicit) + suffix
        }

        let lowerCore = normalizedCore.lowercased()
        guard lowerCore.count >= 4 else {
            return token
        }
        guard vocabularyFrequency[lowerCore] == nil else {
            return token
        }

        let nearMatches = vocabularyFrequency.filter { candidate, signal in
            signal.frequency >= 2
                && candidate.first == lowerCore.first
                && lowerCore.editDistanceAtMostOne(candidate)
                && supportsContextualCorrection(
                    signal: signal,
                    observationConfidence: observationConfidence,
                    lineIndex: lineIndex
                )
        }
        guard let best = nearMatches.max(by: { lhs, rhs in lhs.value.frequency < rhs.value.frequency })?.key else {
            return token
        }

        return prefix + applyCasePattern(from: core, to: best) + suffix
    }

    private static func supportsContextualCorrection(
        signal: VocabularySignal,
        observationConfidence: Float,
        lineIndex: Int
    ) -> Bool {
        let hasNearbySupport = signal.lineIndexes.contains { abs($0 - lineIndex) <= 2 }

        if observationConfidence >= 0.5 {
            return hasNearbySupport || signal.frequency >= 3
        }

        return hasNearbySupport && signal.frequency >= 3
    }

    private static func applyCasePattern(from source: String, to replacement: String) -> String {
        if source == source.uppercased() {
            return replacement.uppercased()
        }
        if source == source.lowercased() {
            return replacement.lowercased()
        }
        if source.prefix(1) == source.prefix(1).uppercased() {
            return replacement.prefix(1).uppercased() + replacement.dropFirst().lowercased()
        }
        return replacement
    }

    private static func repairPackSizeNoise(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(\d{1,2})\s*[xX]\s*(\d{3,4})\s*m[lL]"#) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        var result = text
        let matches = regex.matches(in: text, range: range).reversed()

        for match in matches {
            guard
                let packRange = Range(match.range(at: 1), in: result),
                let volumeRange = Range(match.range(at: 2), in: result)
            else {
                continue
            }

            let packCount = String(result[packRange])
            let rawVolume = String(result[volumeRange])
            let correctedVolume = correctedVolumeToken(rawVolume)
            let replacement = "\(packCount) x \(correctedVolume) mL"

            let fullRange = match.range(at: 0)
            let location = fullRange.location
            let length = fullRange.length
            let current = result as NSString
            result = current.replacingCharacters(in: NSRange(location: location, length: length), with: replacement)
        }

        return result
    }

    private static func correctedVolumeToken(_ token: String) -> String {
        guard token.count == 4 else {
            return token
        }
        let chars = Array(token)
        if chars[1] == chars[2] {
            return "\(chars[0])\(chars[2])\(chars[3])"
        }
        if chars[2] == chars[3] {
            return "\(chars[0])\(chars[1])\(chars[3])"
        }
        return token
    }

    private static func buildProductFamilies(from observations: [OCRTextObservation]) -> [ProductFamily] {
        var clusters: [ProductFamilyCluster] = []

        for (index, observation) in observations.enumerated() {
            let lineSignals = signals(for: observation.string)
            guard !lineSignals.keywords.isEmpty || lineSignals.hasPriceSignal else {
                continue
            }

            if let bestIndex = bestClusterIndex(
                for: lineSignals,
                at: index,
                in: clusters
            ) {
                clusters[bestIndex].observations.append(observation)
                clusters[bestIndex].lastIndex = index
                for keyword in lineSignals.keywords {
                    clusters[bestIndex].keywordFrequency[keyword, default: 0] += 1
                }
            } else {
                let keywordFrequency = lineSignals.keywords.reduce(into: [:]) { result, keyword in
                    result[keyword, default: 0] += 1
                }
                clusters.append(
                    ProductFamilyCluster(
                        observations: [observation],
                        keywordFrequency: keywordFrequency,
                        firstIndex: index,
                        lastIndex: index
                    )
                )
            }
        }

        return clusters
            .sorted { $0.firstIndex < $1.firstIndex }
            .enumerated()
            .map { offset, cluster in
                let prices = extractPriceCandidates(from: cluster.observations)
                let supportingLines = cluster.observations.map(\.string)
                let title = familyTitle(from: cluster.observations)
                let keywords = sortedKeywords(from: cluster.keywordFrequency)
                return ProductFamily(
                    id: "family-\(offset)-\(title.lowercased())",
                    title: title,
                    supportingLines: supportingLines,
                    keywords: keywords,
                    itemNameHint: supportingLines.first(where: { line in
                        !line.contains("$") && detectUnit(in: line) == nil && !line.contains(where: \.isNumber)
                    }),
                    priceCandidates: prices
                )
            }
    }

    private static func primaryFamily(from families: [ProductFamily]) -> ProductFamily? {
        families.max { lhs, rhs in
            let lhsPrice = lhs.priceCandidates.first
            let rhsPrice = rhs.priceCandidates.first

            if (lhsPrice?.priority ?? 0) != (rhsPrice?.priority ?? 0) {
                return (lhsPrice?.priority ?? 0) < (rhsPrice?.priority ?? 0)
            }
            if (lhsPrice?.confidence ?? 0) != (rhsPrice?.confidence ?? 0) {
                return (lhsPrice?.confidence ?? 0) < (rhsPrice?.confidence ?? 0)
            }
            let lhsProductSignal = productLineSignalScore(for: lhs)
            let rhsProductSignal = productLineSignalScore(for: rhs)
            if lhsProductSignal != rhsProductSignal {
                return lhsProductSignal < rhsProductSignal
            }
            let lhsPriceProximity = familyPriceProximityScore(for: lhs)
            let rhsPriceProximity = familyPriceProximityScore(for: rhs)
            if lhsPriceProximity != rhsPriceProximity {
                return lhsPriceProximity < rhsPriceProximity
            }
            let lhsRecency = familyRecencyScore(for: lhs)
            let rhsRecency = familyRecencyScore(for: rhs)
            if lhsRecency != rhsRecency {
                return lhsRecency < rhsRecency
            }
            return lhs.keywords.count < rhs.keywords.count
        }
    }

    private static func productLineSignalScore(for family: ProductFamily) -> Int {
        let descriptiveLines = family.supportingLines.filter { line in
            !containsPriceSignal(in: line) && line.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) })
        }
        let strongKeywords = family.keywords.filter { $0.count >= 4 }.count
        return (descriptiveLines.count * 2) + strongKeywords
    }

    private static func familyPriceProximityScore(for family: ProductFamily) -> Int {
        let lines = family.supportingLines
        let priceIndices = lines.enumerated().compactMap { entry in
            containsPriceSignal(in: entry.element) ? entry.offset : nil
        }
        let descriptorIndices = lines.enumerated().compactMap { entry in
            let line = entry.element
            let hasLetters = line.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) })
            return (!containsPriceSignal(in: line) && hasLetters) ? entry.offset : nil
        }
        guard !priceIndices.isEmpty, !descriptorIndices.isEmpty else {
            return 0
        }

        let bestDistance = priceIndices.flatMap { priceIndex in
            descriptorIndices.map { abs($0 - priceIndex) }
        }.min() ?? Int.max
        return max(0, 4 - bestDistance)
    }

    private static func familyRecencyScore(for family: ProductFamily) -> Int {
        let components = family.id.components(separatedBy: "-")
        guard components.count >= 2, let offset = Int(components[1]) else {
            return 0
        }
        return offset
    }

    private static func signals(for line: String) -> ObservationSignals {
        let words = line.normalizedWords()
        let hasExplicitSizePattern = containsExplicitSizeToken(in: line)
        let keywordSet = Set(words.filter { word in
            if familyStopWords.contains(word) {
                return false
            }
            guard word.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else {
                return false
            }
            if word.count >= 3 {
                return true
            }
            return isSizeToken(word)
        })
        let lowered = line.lowercased()
        return ObservationSignals(
            keywords: keywordSet,
            hasPriceSignal: containsPriceSignal(in: line),
            hasSizeSignal: hasExplicitSizePattern || words.contains { token in
                isSizeToken(token)
            },
            hasPromotionSignal: lowered.contains("buy ") || lowered.contains(" for ") || lowered.contains("/")
        )
    }

    private static func isSizeToken(_ word: String) -> Bool {
        word.range(of: #"^\d{1,4}(g|kg|ml|l|oz|lb|pk|ct)$"#, options: .regularExpression) != nil
    }

    private static func containsExplicitSizeToken(in line: String) -> Bool {
        let words = line.normalizedWords()
        if words.contains(where: { isSizeToken($0) }) {
            return true
        }
        return line.range(
            of: #"\d{1,4}\s*(ml|g|kg|l|oz|lb|pk|ct)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func bestClusterIndex(
        for signals: ObservationSignals,
        at lineIndex: Int,
        in clusters: [ProductFamilyCluster]
    ) -> Int? {
        struct ClusterScore {
            let index: Int
            let score: Int
            let distance: Int
            let anchorCount: Int
        }

        var scores: [ClusterScore] = []

        for (index, cluster) in clusters.enumerated() {
            let clusterKeywords = Set(cluster.keywordFrequency.keys)
            let sharedKeywordCount = signals.keywords.intersection(clusterKeywords).count
            let distance = abs(lineIndex - cluster.lastIndex)
            let proximityScore = max(0, 2 - distance)
            let anchorCount = cluster.keywordFrequency.keys.filter { $0.count >= 4 }.count
            let score =
                (sharedKeywordCount * 3)
                + proximityScore
                + (signals.hasPriceSignal ? 1 : 0)
                + (signals.hasSizeSignal ? 1 : 0)
                + (signals.hasPromotionSignal ? 1 : 0)
            scores.append(ClusterScore(index: index, score: score, distance: distance, anchorCount: anchorCount))
        }

        guard let best = scores.max(by: { lhs, rhs in lhs.score < rhs.score }) else {
            return nil
        }

        let sortedScores = scores.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.distance < rhs.distance
        }
        let secondBest = sortedScores.dropFirst().first

        let hasGenericSignals = signals.keywords.isEmpty
            && (signals.hasPriceSignal || signals.hasSizeSignal || signals.hasPromotionSignal)
        if hasGenericSignals {
            if clusters.count > 1 {
                let scoreGap = best.score - (secondBest?.score ?? 0)
                let strongerThanNext = scoreGap >= 2
                let hasStrongAnchor = best.anchorCount >= 2
                let isNear = best.distance <= 1
                guard best.score >= 4, hasStrongAnchor, isNear, strongerThanNext else {
                    return nil
                }
                return best.index
            }

            let relaxedThreshold = best.score >= 2
            return relaxedThreshold ? best.index : nil
        }

        guard best.score >= 3 else {
            return nil
        }
        return best.index
    }

    private static func familyTitle(from observations: [OCRTextObservation]) -> String {
        let descriptiveLine = observations
            .map(\.string)
            .first(where: { line in
                !containsPriceSignal(in: line) && line.contains(where: { !$0.isNumber })
            })

        return descriptiveLine ?? observations.first?.string ?? "Uncategorized Item"
    }

    private static func sortedKeywords(from frequency: [String: Int]) -> [String] {
        frequency
            .sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value
                }
                return lhs.key < rhs.key
            }
            .map(\.key)
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

    private static func extractPriceCandidates(from observations: [OCRTextObservation]) -> [PriceCandidate] {
        var candidates: [PriceCandidate] = []
        let normalizedObservations = observations.map { observation in
            OCRTextObservation(
                string: observation.string.replacingOccurrences(of: ",", with: "."),
                confidence: observation.confidence
            )
        }

        for observation in normalizedObservations {
            candidates.append(contentsOf: extractInlinePriceCandidates(from: observation))
        }

        if let regex = try? NSRegularExpression(pattern: splitCurrencyPattern) {
            let combinedObservations = zip(normalizedObservations, normalizedObservations.dropFirst()).map { lhs, rhs in
                OCRTextObservation(
                    string: "\(lhs.string)\n\(rhs.string)",
                    confidence: min(lhs.confidence, rhs.confidence)
                )
            }

            for observation in combinedObservations {
                let text = observation.string
                let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                for match in matches {
                    guard
                        let dollarsRange = Range(match.range(at: 2), in: text),
                        let centsRange = Range(match.range(at: 3), in: text),
                        let candidate = splitCurrencyCandidate(
                            dollarsText: String(text[dollarsRange]),
                            centsText: String(text[centsRange]),
                            sourceText: text,
                            confidence: observation.confidence
                        )
                    else {
                        continue
                    }

                    if candidates.contains(where: { $0.value == candidate.value && $0.quantity == nil }) {
                        continue
                    }

                    candidates.append(candidate)
                }
            }
        }

        return candidates.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }

            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }

            return lhs.value > rhs.value
        }
    }

    private static func extractInlinePriceCandidates(from observation: OCRTextObservation) -> [PriceCandidate] {
        var candidates: [PriceCandidate] = []
        let text = observation.string

        if let regex = try? NSRegularExpression(pattern: multiBuyPattern, options: [.caseInsensitive]) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                guard
                    let quantityRange = Range(match.range(at: 1), in: text),
                    let priceRange = Range(match.range(at: 2), in: text),
                    let quantity = Decimal(string: String(text[quantityRange])),
                    let price = Decimal(string: String(text[priceRange]))
                else {
                    continue
                }

                candidates.append(
                    PriceCandidate(
                        label: "\(quantity) for $\(price)",
                        value: price,
                        quantity: quantity,
                        priority: 4,
                        sourceText: observation.string,
                        confidence: observation.confidence
                    )
                )
            }
        }

        if let regex = try? NSRegularExpression(pattern: currencyPattern) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if shouldIgnoreDirectPriceLine(text) {
                    continue
                }

                guard
                    let range = Range(match.range(at: 1), in: text),
                    let price = Decimal(string: String(text[range]))
                else {
                    continue
                }

                if candidates.contains(where: { $0.value == price && $0.quantity == nil }) {
                    continue
                }

                candidates.append(
                    PriceCandidate(
                        label: "$\(price)",
                        value: price,
                        quantity: nil,
                        priority: contextualPricePriority(in: observation.string, basePriority: 3),
                        sourceText: observation.string,
                        confidence: observation.confidence
                    )
                )
            }
        }

        if let regex = try? NSRegularExpression(pattern: impliedCurrencyPattern) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if shouldIgnoreImpliedCurrencyLine(text) {
                    continue
                }

                guard
                    let range = Range(match.range(at: 2), in: text),
                    let candidate = impliedCurrencyCandidate(
                        from: String(text[range]),
                        sourceText: observation.string,
                        confidence: observation.confidence
                    )
                else {
                    continue
                }

                if candidates.contains(where: { $0.value == candidate.value && $0.quantity == nil }) {
                    continue
                }

                candidates.append(candidate)
            }
        }

        return candidates
    }

    private static func splitCurrencyCandidate(
        dollarsText: String,
        centsText: String,
        sourceText: String,
        confidence: Float
    ) -> PriceCandidate? {
        guard
            let dollars = Decimal(string: dollarsText),
            let cents = Decimal(string: centsText),
            cents < 100
        else {
            return nil
        }

        let value = dollars + (cents / 100)
        return PriceCandidate(
            label: "$\(value)",
            value: value,
            quantity: nil,
            priority: 2,
            sourceText: sourceText,
            confidence: confidence
        )
    }

    private static func impliedCurrencyCandidate(
        from text: String,
        sourceText: String,
        confidence: Float
    ) -> PriceCandidate? {
        guard
            text.count >= 3,
            let integerValue = Int(text)
        else {
            return nil
        }

        let dollars = integerValue / 100
        let cents = integerValue % 100
        guard dollars > 0 else {
            return nil
        }

        let valueString = "\(dollars).\(String(format: "%02d", cents))"
        guard let value = Decimal(string: valueString) else {
            return nil
        }

        return PriceCandidate(
            label: "$\(value)",
            value: value,
            quantity: nil,
            priority: 1,
            sourceText: sourceText,
            confidence: confidence
        )
    }

    private static func averageConfidence(in observations: [OCRTextObservation]) -> Float? {
        guard !observations.isEmpty else {
            return nil
        }

        let total = observations.reduce(Float.zero) { partialResult, observation in
            partialResult + observation.confidence
        }
        return total / Float(observations.count)
    }

    private static func detectUnit(in text: String) -> UnitType? {
        let lowered = text.lowercased()

        if lowered.contains("100 g") || lowered.contains("100g") {
            return .hundredGrams
        }
        if lowered.contains(" lbs") || lowered.contains("/lb") || lowered.contains(" lb") {
            return .lb
        }
        if lowered.contains("/kg") || lowered.contains(" kg") {
            return .kg
        }
        if lowered.contains(" ea") || lowered.contains(" each") {
            return .each
        }
        if lowered.contains(" l") || lowered.contains("/l") {
            return .liter
        }

        return nil
    }

    private static func detectQuantity(in text: String, unit: UnitType?) -> Decimal? {
        guard let unit else {
            return nil
        }

        let lowered = text.lowercased().replacingOccurrences(of: ",", with: ".")

        if unit == .lb {
            if lowered.contains("/lb") || lowered.contains(" per lb") || lowered.contains(" lbs") {
                return Decimal(1)
            }
        } else if unit == .kg, lowered.contains("/kg") || lowered.contains(" per kg") {
            return Decimal(1)
        } else if unit == .liter, lowered.contains("/l") || lowered.contains(" per l") {
            return Decimal(1)
        }

        if let regex = try? NSRegularExpression(pattern: quantityFractionPattern, options: [.caseInsensitive]) {
            let matches = regex.matches(in: lowered, range: NSRange(lowered.startIndex..., in: lowered))
            for match in matches {
                guard
                    let numeratorRange = Range(match.range(at: 1), in: lowered),
                    let denominatorRange = Range(match.range(at: 2), in: lowered),
                    let numerator = Decimal(string: String(lowered[numeratorRange])),
                    let denominator = Decimal(string: String(lowered[denominatorRange])),
                    denominator > 0
                else {
                    continue
                }
                return numerator / denominator
            }
        }

        if let regex = try? NSRegularExpression(pattern: quantityDecimalPattern, options: [.caseInsensitive]) {
            let matches = regex.matches(in: lowered, range: NSRange(lowered.startIndex..., in: lowered))
            for match in matches {
                guard
                    let quantityRange = Range(match.range(at: 1), in: lowered),
                    let quantity = Decimal(string: String(lowered[quantityRange])),
                    quantity > 0
                else {
                    continue
                }
                return quantity
            }
        }

        return nil
    }

    private static func contextualPricePriority(in text: String, basePriority: Int) -> Int {
        let lowered = text.lowercased()

        if lowered.contains("member") || lowered.contains("club") || lowered.contains("loyalty") {
            return min(4, basePriority + 1)
        }
        if lowered.contains("regular") || lowered.contains(" was ") || lowered.hasPrefix("was ") {
            return max(1, basePriority - 1)
        }

        return basePriority
    }

    private static func shouldIgnoreDirectPriceLine(_ text: String) -> Bool {
        let lowered = text.lowercased()

        if lowered.contains("save") {
            return true
        }
        if containsPhoneNumber(in: lowered) {
            return true
        }
        if looksLikeDateLine(lowered) {
            return true
        }

        return false
    }

    private static func shouldIgnoreImpliedCurrencyLine(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return containsPhoneNumber(in: lowered) || looksLikeDateLine(lowered)
    }

    private static func containsPhoneNumber(in text: String) -> Bool {
        text.range(of: #"\d{10,}"#, options: .regularExpression) != nil
    }

    private static func looksLikeDateLine(_ text: String) -> Bool {
        guard text.range(of: monthNamePattern, options: [.regularExpression, .caseInsensitive]) != nil else {
            return false
        }

        let hasDay = text.range(of: #"\b([12]?\d|3[01])\b"#, options: .regularExpression) != nil
        let hasYear = text.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) != nil
        return hasDay || hasYear
    }

#if DEBUG
    static func _test_consolidateObservations(_ observations: [OCRTextObservation]) -> [OCRTextObservation] {
        observations.consolidateObservations()
    }

    static func _test_buildProductFamilies(from observations: [OCRTextObservation]) -> [ProductFamily] {
        buildProductFamilies(from: observations)
    }

    static func _test_primaryFamily(from families: [ProductFamily]) -> ProductFamily? {
        primaryFamily(from: families)
    }
#endif
}
