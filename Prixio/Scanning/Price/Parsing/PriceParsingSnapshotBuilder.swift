//
//  PriceParsingSnapshotBuilder.swift
//  Prixio
//

import CoreGraphics
import Foundation

struct PriceParsingSnapshotBuilder {
    func buildHeuristicSnapshot(from observations: [OCRTextObservation]) -> PriceParsingService.HeuristicExtractionSnapshot {
        let supportedObservations = PriceParsingService.orderObservationsInReadingOrder(observations.filter {
            PriceParsingService.isSupportedOCRLine($0.string)
        })
        let spatialGroups = PriceParsingService.makeSpatialObservationGroups(from: supportedObservations)
        let strongestGroupObservations = bestFocusedObservations(
            from: spatialGroups,
            fallback: supportedObservations
        )
        let focusedObservations = strongestGroupObservations
        let cleanedObservations = bestAvailableObservations(
            focusedObservations: focusedObservations,
            strongestGroupObservations: strongestGroupObservations,
            supportedObservations: supportedObservations
        )
        let normalizedObservations = PriceParsingService.applyContextualNormalization(to: cleanedObservations)
        let consolidatedObservations = normalizedObservations.consolidateObservations()
        let supportedLines = consolidatedObservations.isEmpty ? normalizedObservations : consolidatedObservations
        let rawText = supportedLines.map(\.string).joined(separator: "\n")
        let normalizedText = rawText.replacingOccurrences(of: ",", with: ".")
        let unitScopeText = supportedLines.map(\.string).joined(separator: "\n")
        let candidateScorer = PriceCandidateScorer()
        let unitResolver = PriceParsingUnitResolver()
        let itemNameResolver = PriceParsingItemNameResolver()
        let consolidatedPriceCandidates = candidateScorer.extractPriceCandidates(from: consolidatedObservations)
        let extractedPriceCandidates = consolidatedPriceCandidates.isEmpty
            ? candidateScorer.extractPriceCandidates(from: normalizedObservations)
            : consolidatedPriceCandidates
        let priceCandidates = candidateScorer.scorePriceCandidates(
            extractedPriceCandidates,
            in: supportedLines
        )
        let detectedUnit = unitResolver.detectUnit(in: unitScopeText.isEmpty ? normalizedText : unitScopeText)
        let lines = (unitScopeText.isEmpty ? normalizedText : unitScopeText)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let itemNameHint = itemNameResolver.extractItemNameHint(
            from: supportedLines,
            priceCandidates: priceCandidates
        )
        let resolvedQuantity = unitResolver.inferResolvedQuantity(
            from: supportedLines,
            priceCandidates: priceCandidates,
            detectedUnit: detectedUnit,
            fallbackText: unitScopeText.isEmpty ? normalizedText : unitScopeText
        )
        let heuristicConfidence = priceCandidates.first?.confidence ?? PriceParsingService.averageConfidence(in: consolidatedObservations) ?? 0.1

        return PriceParsingService.HeuristicExtractionSnapshot(
            supportedObservations: supportedObservations,
            spatialGroups: spatialGroups,
            cleanedObservations: cleanedObservations,
            normalizedObservations: normalizedObservations,
            consolidatedObservations: supportedLines,
            rawText: rawText,
            normalizedText: normalizedText,
            lines: lines,
            priceCandidates: priceCandidates,
            detectedUnit: detectedUnit,
            itemNameHint: itemNameHint,
            resolvedQuantity: resolvedQuantity,
            heuristicConfidence: heuristicConfidence
        )
    }

    func shouldFallbackFromFocusedObservations(
        sourceObservations: [OCRTextObservation],
        cleanedObservations: [OCRTextObservation]
    ) -> Bool {
        guard !sourceObservations.isEmpty else {
            return false
        }

        guard !cleanedObservations.isEmpty else {
            return true
        }

        let sourceHasPriceSignal = sourceObservations.contains { PriceParsingService.containsPriceSignal(in: $0.string) }
        let cleanedHasPriceSignal = cleanedObservations.contains { PriceParsingService.containsPriceSignal(in: $0.string) }
        if sourceHasPriceSignal && !cleanedHasPriceSignal {
            return true
        }

        let sourceHasDescription = sourceObservations.contains { PriceParsingService.isDescriptiveObservation($0) }
        let cleanedHasDescription = cleanedObservations.contains { PriceParsingService.isDescriptiveObservation($0) }
        if sourceHasDescription && !cleanedHasDescription {
            return true
        }

        if sourceObservations.count >= 2 && cleanedObservations.count < 2 && (sourceHasPriceSignal || sourceHasDescription) {
            return true
        }

        return false
    }

    func makeFallbackObservationSet(
        focusedObservations: [OCRTextObservation],
        strongestGroupObservations: [OCRTextObservation],
        supportedObservations: [OCRTextObservation]
    ) -> [(source: [OCRTextObservation], cleaned: [OCRTextObservation])] {
        [
            (
                source: focusedObservations,
                cleaned: PriceParsingService.removeObviousNoise(from: focusedObservations)
            ),
            (
                source: strongestGroupObservations,
                cleaned: PriceParsingService.removeObviousNoise(from: strongestGroupObservations)
            ),
            (
                source: supportedObservations,
                cleaned: PriceParsingService.removeObviousNoise(from: supportedObservations)
            ),
            (
                source: PriceParsingService.minimallySanitizedObservations(from: supportedObservations),
                cleaned: PriceParsingService.minimallySanitizedObservations(from: supportedObservations)
            )
        ]
    }

    func bestAvailableObservations(
        focusedObservations: [OCRTextObservation],
        strongestGroupObservations: [OCRTextObservation],
        supportedObservations: [OCRTextObservation]
    ) -> [OCRTextObservation] {
        let fallbackSets = makeFallbackObservationSet(
            focusedObservations: focusedObservations,
            strongestGroupObservations: strongestGroupObservations,
            supportedObservations: supportedObservations
        )

        for fallback in fallbackSets {
            if !shouldFallbackFromFocusedObservations(
                sourceObservations: fallback.source,
                cleanedObservations: fallback.cleaned
            ) {
                return fallback.cleaned
            }
        }

        return fallbackSets.last?.cleaned ?? []
    }

    func bestFocusedObservations(
        from spatialGroups: [PriceParsingService.SpatialObservationGroup],
        fallback: [OCRTextObservation]
    ) -> [OCRTextObservation] {
        let candidates = focusedObservationCandidates(from: spatialGroups)
        guard let bestCandidate = candidates.max(by: { lhs, rhs in lhs.score < rhs.score }) else {
            return spatialGroups.first?.observations ?? fallback
        }

        return bestCandidate.observations
    }

    func focusedObservationCandidates(
        from spatialGroups: [PriceParsingService.SpatialObservationGroup]
    ) -> [(observations: [OCRTextObservation], score: Float)] {
        guard !spatialGroups.isEmpty else {
            return []
        }

        var candidates: [(observations: [OCRTextObservation], score: Float)] = spatialGroups.map { group in
            let ordered = PriceParsingService.orderObservationsInReadingOrder(group.observations)
            return (observations: ordered, score: focusedObservationScore(for: ordered))
        }

        for primaryIndex in spatialGroups.indices {
            for secondaryIndex in spatialGroups.indices where secondaryIndex != primaryIndex {
                let primaryGroup = spatialGroups[primaryIndex]
                let secondaryGroup = spatialGroups[secondaryIndex]
                guard shouldMergeFocusedObservationGroups(primaryGroup, secondaryGroup) else {
                    continue
                }

                let merged = PriceParsingService.orderObservationsInReadingOrder(
                    primaryGroup.observations + secondaryGroup.observations
                )
                candidates.append((observations: merged, score: focusedObservationScore(for: merged)))
            }
        }

        return candidates
    }

    func focusedObservationScore(for observations: [OCRTextObservation]) -> Float {
        let cleanedObservations = PriceParsingService.removeObviousNoise(from: observations)
        let priceSignalCount = cleanedObservations.filter {
            PriceParsingService.containsPriceSignal(in: $0.string)
        }.count
        let descriptiveCount = cleanedObservations.filter {
            PriceParsingService.isDescriptiveObservation($0)
        }.count
        let priceDominanceBonus: Float = priceSignalCount >= 2 ? 2 : 0
        let descriptiveBonus: Float = descriptiveCount >= 2 ? 1 : 0
        let confidenceScore = PriceParsingService.averageConfidence(in: cleanedObservations) ?? 0

        return Float(cleanedObservations.count) * 1.5
            + Float(priceSignalCount) * 2.5
            + Float(descriptiveCount) * 1.5
            + priceDominanceBonus
            + descriptiveBonus
            + confidenceScore
    }

    func shouldMergeFocusedObservationGroups(
        _ lhs: PriceParsingService.SpatialObservationGroup,
        _ rhs: PriceParsingService.SpatialObservationGroup
    ) -> Bool {
        guard
            let lhsFrame = PriceParsingService.spatialFrame(for: lhs.observations),
            let rhsFrame = PriceParsingService.spatialFrame(for: rhs.observations)
        else {
            return false
        }

        let verticalGap = max(0, lhsFrame.minY - rhsFrame.maxY, rhsFrame.minY - lhsFrame.maxY)
        guard verticalGap <= 0.12 else {
            return false
        }

        let horizontalGap = max(0, lhsFrame.minX - rhsFrame.maxX, rhsFrame.minX - lhsFrame.maxX)
        guard horizontalGap <= 0.28 else {
            return false
        }

        let lhsHasPriceSignal = lhs.observations.contains { PriceParsingService.containsPriceSignal(in: $0.string) }
        let rhsHasPriceSignal = rhs.observations.contains { PriceParsingService.containsPriceSignal(in: $0.string) }
        let lhsHasDescription = lhs.observations.contains { PriceParsingService.isDescriptiveObservation($0) }
        let rhsHasDescription = rhs.observations.contains { PriceParsingService.isDescriptiveObservation($0) }
        let lhsPriceSignalCount = lhs.observations.filter { PriceParsingService.containsPriceSignal(in: $0.string) }.count
        let rhsPriceSignalCount = rhs.observations.filter { PriceParsingService.containsPriceSignal(in: $0.string) }.count
        let lhsDescriptiveCount = lhs.observations.filter { PriceParsingService.isDescriptiveObservation($0) }.count
        let rhsDescriptiveCount = rhs.observations.filter { PriceParsingService.isDescriptiveObservation($0) }.count
        let lhsIsPriceDominant = lhsPriceSignalCount > lhsDescriptiveCount
        let rhsIsPriceDominant = rhsPriceSignalCount > rhsDescriptiveCount
        let lhsIsDescriptionDominant = lhsDescriptiveCount > lhsPriceSignalCount
        let rhsIsDescriptionDominant = rhsDescriptiveCount > rhsPriceSignalCount

        let addsMissingPriceOrDescription = (
            lhsHasDescription && !lhsHasPriceSignal && rhsIsPriceDominant
        ) || (
            rhsHasDescription && !rhsHasPriceSignal && lhsIsPriceDominant
        ) || (
            lhsHasPriceSignal && !lhsHasDescription && rhsIsDescriptionDominant
        ) || (
            rhsHasPriceSignal && !rhsHasDescription && lhsIsDescriptionDominant
        )
        guard addsMissingPriceOrDescription else {
            return false
        }

        return true
    }
}

extension PriceParsingService {
    static func isSupportedOCRLine(_ line: String) -> Bool {
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

    static func orderObservationsInReadingOrder(_ observations: [OCRTextObservation]) -> [OCRTextObservation] {
        observations.enumerated().sorted { lhs, rhs in
            guard let lhsBox = lhs.element.boundingBox, let rhsBox = rhs.element.boundingBox else {
                return lhs.offset < rhs.offset
            }

            let rowTolerance = max(lhsBox.height, rhsBox.height) * 0.6
            let verticalDelta = abs(lhsBox.midY - rhsBox.midY)
            if verticalDelta > rowTolerance {
                return lhsBox.midY > rhsBox.midY
            }

            if lhsBox.minX != rhsBox.minX {
                return lhsBox.minX < rhsBox.minX
            }

            return lhs.offset < rhs.offset
        }
        .map(\.element)
    }

    static func makeSpatialObservationGroups(from observations: [OCRTextObservation]) -> [SpatialObservationGroup] {
        guard observations.contains(where: { $0.boundingBox != nil }) else {
            return observations.isEmpty ? [] : [SpatialObservationGroup(observations: observations, score: spatialGroupScore(for: observations))]
        }

        var groupedObservations: [[OCRTextObservation]] = []

        for observation in observations {
            guard let boundingBox = observation.boundingBox else {
                if groupedObservations.isEmpty {
                    groupedObservations.append([observation])
                } else {
                    groupedObservations[groupedObservations.count - 1].append(observation)
                }
                continue
            }

            if let index = groupedObservations.lastIndex(where: { shouldJoinSpatialGroup(observation: observation, boundingBox: boundingBox, group: $0) }) {
                groupedObservations[index].append(observation)
            } else {
                groupedObservations.append([observation])
            }
        }

        return groupedObservations
            .map { group in
                SpatialObservationGroup(
                    observations: group,
                    score: spatialGroupScore(for: group)
                )
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return lhs.observations.count > rhs.observations.count
            }
    }

    static func shouldJoinSpatialGroup(
        observation: OCRTextObservation,
        boundingBox: CGRect,
        group: [OCRTextObservation]
    ) -> Bool {
        guard let groupFrame = spatialFrame(for: group) else {
            return false
        }

        let verticalGap = max(0, groupFrame.minY - boundingBox.maxY, boundingBox.minY - groupFrame.maxY)
        guard verticalGap <= 0.12 else {
            return false
        }

        let horizontalOverlap = groupFrame.intersection(boundingBox).width
        let minimumWidth = min(groupFrame.width, boundingBox.width)
        let overlapRatio = minimumWidth > 0 ? horizontalOverlap / minimumWidth : 0
        let centerDistance = abs(groupFrame.midX - boundingBox.midX)
        let sameColumn = overlapRatio >= 0.35 || centerDistance <= max(groupFrame.width, boundingBox.width) * 0.9

        if sameColumn {
            return true
        }

        let verticalOverlap = groupFrame.intersection(boundingBox).height
        let minimumHeight = min(groupFrame.height, boundingBox.height)
        let verticalOverlapRatio = minimumHeight > 0 ? verticalOverlap / minimumHeight : 0
        let horizontalGap = max(0, boundingBox.minX - groupFrame.maxX, groupFrame.minX - boundingBox.maxX)
        let observationHasPriceSignal = containsPriceSignal(in: observation.string)
        let groupHasPriceSignal = group.contains { containsPriceSignal(in: $0.string) }
        let looksLikeShelfTagRow = verticalOverlapRatio >= 0.45
            && horizontalGap <= 0.28
            && (observationHasPriceSignal || groupHasPriceSignal)

        return looksLikeShelfTagRow
    }

    static func spatialFrame(for observations: [OCRTextObservation]) -> CGRect? {
        observations.compactMap(\.boundingBox).reduce(nil) { partialResult, next in
            guard let partialResult else {
                return next
            }
            return partialResult.union(next)
        }
    }

    static func spatialGroupScore(for observations: [OCRTextObservation]) -> Float {
        let lineScore = Float(observations.count) * 1.5
        let priceScore = Float(observations.filter { containsPriceSignal(in: $0.string) }.count) * 2
        let descriptiveScore = Float(observations.filter { observation in
            isDescriptiveObservation(observation)
        }.count) * 1.25
        let confidenceScore = observations.map(\.confidence).reduce(0, +) / Float(max(1, observations.count))
        return lineScore + priceScore + descriptiveScore + confidenceScore
    }

    static func isDescriptiveObservation(_ observation: OCRTextObservation) -> Bool {
        let line = observation.string
        return line.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) })
            && !containsPriceSignal(in: line)
    }

    static func removeObviousNoise(from observations: [OCRTextObservation]) -> [OCRTextObservation] {
        var seenKeys = Set<String>()
        let shouldPreserveNumericPriceFragments = observations.filter {
            containsPriceSignal(in: $0.string) || isDescriptiveObservation($0)
        }.count >= 3

        return observations.compactMap { observation in
            let sanitized = observation.string.sanitizeOCRLine()
            guard !sanitized.isEmpty else {
                return nil
            }

            guard
                shouldPreserveNumericPriceLikeLine(
                    sanitized,
                    inPriceDenseContext: shouldPreserveNumericPriceFragments
                ) || !isObviousNoiseLine(sanitized)
            else {
                return nil
            }

            let key = sanitized.normalizedWords().joined(separator: " ")
            guard !key.isEmpty else {
                return nil
            }

            guard seenKeys.insert(key).inserted else {
                return nil
            }

            return OCRTextObservation(
                string: sanitized,
                confidence: observation.confidence,
                boundingBox: observation.boundingBox
            )
        }
    }

    static func minimallySanitizedObservations(from observations: [OCRTextObservation]) -> [OCRTextObservation] {
        var seenKeys = Set<String>()

        return observations.compactMap { observation in
            let sanitized = observation.string.sanitizeOCRLine()
            guard !sanitized.isEmpty else {
                return nil
            }

            let normalizedKey = sanitized.comparisonNormalizedWords().joined(separator: " ")
            let key = normalizedKey.isEmpty ? sanitized.lowercased() : normalizedKey
            guard seenKeys.insert(key).inserted else {
                return nil
            }

            return OCRTextObservation(
                string: sanitized,
                confidence: observation.confidence,
                boundingBox: observation.boundingBox
            )
        }
    }

    static func isObviousNoiseLine(_ line: String) -> Bool {
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
        let hasUnitSignal = PriceParsingUnitResolver().detectUnit(in: trimmed) != nil
            || containsExplicitSizeToken(in: trimmed)
        let hasOCRVariantEvidence = trimmed.digitsAsLettersCount() >= 2

        if (isLikelyShelfCode(trimmed) || (isLikelySKU(trimmed) && !hasOCRVariantEvidence)) && !hasUnitSignal {
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

    static func shouldPreserveNumericPriceLikeLine(
        _ line: String,
        inPriceDenseContext: Bool
    ) -> Bool {
        guard inPriceDenseContext else {
            return false
        }
        guard line.range(of: #"^\d{3,4}$"#, options: .regularExpression) != nil else {
            return false
        }

        return canonicalPriceAmount(from: line) != nil
    }

    static func containsPriceSignal(in text: String) -> Bool {
        if text.contains("$") {
            return true
        }

        guard let regex = try? NSRegularExpression(pattern: simplePricePattern) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    static func isLikelyShelfCode(_ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: shelfCodePattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    static func isLikelySKU(_ text: String) -> Bool {
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

    static func containsVowel(_ token: String) -> Bool {
        token.range(of: "[aeiou]", options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func applyContextualNormalization(to observations: [OCRTextObservation]) -> [OCRTextObservation] {
        let vocabularyFrequency = contextualVocabulary(from: observations)

        return observations.enumerated().map { index, observation in
            let repairedPackText = repairPackSizeNoise(in: observation.string)
            let repairedPriceText = repairPriceTokenNoise(in: repairedPackText)
            let correctedTokens = repairedPriceText
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
                confidence: observation.confidence,
                boundingBox: observation.boundingBox
            )
        }
    }

    static func repairPriceTokenNoise(in text: String) -> String {
        let mergedUnitSpacing = repairMergedPriceUnitTokens(in: text)
        let splitDecimals = repairSplitPriceTokens(in: mergedUnitSpacing)
        let decimalVariants = repairDecimalCommaPriceTokens(in: splitDecimals)
        return canonicalizeStandalonePriceLine(in: decimalVariants)
    }

    static func contextualVocabulary(from observations: [OCRTextObservation]) -> [String: VocabularySignal] {
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

    static func correctedToken(
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

    static func supportsContextualCorrection(
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

    static func applyCasePattern(from source: String, to replacement: String) -> String {
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

    static func repairPackSizeNoise(in text: String) -> String {
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
            let current = result as NSString
            result = current.replacingCharacters(in: NSRange(location: fullRange.location, length: fullRange.length), with: replacement)
        }

        return result
    }

    static func repairMergedPriceUnitTokens(in text: String) -> String {
        let slashSeparated = text.replacingOccurrences(
            of: #"(?i)([\$s]?\d{1,4}(?:[.,]\d{2})?)(/(?:lb|lbs|kg|l))"#,
            with: "$1 $2",
            options: .regularExpression
        )
        return slashSeparated.replacingOccurrences(
            of: #"(?i)([\$s]?\d{1,4}(?:[.,]\d{2})?)(ea|each|lb|lbs|kg|l)\b"#,
            with: "$1 $2",
            options: .regularExpression
        )
    }

    static func repairSplitPriceTokens(in text: String) -> String {
        text.replacingOccurrences(
            of: #"(?i)(?<!\d)([\$s]?\d{1,2})\s+(\d{2})(?=\s*(?:/(?:lb|lbs|kg|l)|lb|lbs|kg|l|ea|each|$))"#,
            with: "$1.$2",
            options: .regularExpression
        )
    }

    static func repairDecimalCommaPriceTokens(in text: String) -> String {
        text.replacingOccurrences(
            of: #"(?i)(?<!\d)([\$s]?\d+),(\d{2})(?!\d)"#,
            with: "$1.$2",
            options: .regularExpression
        )
    }

    static func canonicalizeStandalonePriceLine(in text: String) -> String {
        let trimmed = text.sanitizeOCRLine()
        guard
            let regex = try? NSRegularExpression(
                pattern: #"(?i)^([\$s]?)(\d{1,4}(?:\.\d{2})?)(?:\s+|)(/(?:lb|lbs|kg|l)|lb|lbs|kg|l|ea|each)?$"#
            ),
            let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
            let amountRange = Range(match.range(at: 2), in: trimmed)
        else {
            return trimmed
        }

        let currencyMarker = Range(match.range(at: 1), in: trimmed).map { String(trimmed[$0]) } ?? ""
        let amountText = String(trimmed[amountRange])
        let unitText = Range(match.range(at: 3), in: trimmed).map { String(trimmed[$0]).lowercased() } ?? ""
        let hasStrongPriceContext = !currencyMarker.isEmpty || !unitText.isEmpty || amountText.contains(".")
        guard hasStrongPriceContext, let canonicalAmount = canonicalPriceAmount(from: amountText) else {
            return trimmed
        }

        let suffix = unitText.isEmpty ? "" : " \(unitText)"
        return "$\(canonicalAmount)\(suffix)"
    }

    static func canonicalPriceAmount(from text: String) -> String? {
        if text.contains(".") {
            guard Decimal(string: text) != nil else {
                return nil
            }

            let parts = text.split(separator: ".", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                return text
            }
            let dollars = parts[0]
            let cents = String(parts[1].prefix(2)).padding(
                toLength: 2,
                withPad: "0",
                startingAt: 0
            )
            return "\(dollars).\(cents)"
        }

        guard
            text.count >= 3,
            text.count <= 4,
            let integerValue = Int(text)
        else {
            return nil
        }

        let dollars = integerValue / 100
        let cents = integerValue % 100
        guard dollars > 0 else {
            return nil
        }

        return "\(dollars).\(String(format: "%02d", cents))"
    }

    static func correctedVolumeToken(_ token: String) -> String {
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

    static func isSizeToken(_ word: String) -> Bool {
        word.range(of: #"^\d{1,4}(g|kg|ml|l|oz|lb|pk|ct)$"#, options: .regularExpression) != nil
    }

    static func containsExplicitSizeToken(in line: String) -> Bool {
        let words = line.normalizedWords()
        if words.contains(where: { isSizeToken($0) }) {
            return true
        }
        if line.range(
            of: #"\d{1,2}\s*[x×]\s*\d{1,4}(?:\.\d+)?\s*(ml|g|kg|l|oz)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return true
        }
        return line.range(
            of: #"\d{1,4}\s*(ml|g|kg|l|oz|lb|pk|ct|count|pack)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    static func averageConfidence(in observations: [OCRTextObservation]) -> Float? {
        guard !observations.isEmpty else {
            return nil
        }

        let total = observations.reduce(Float.zero) { partialResult, observation in
            partialResult + observation.confidence
        }
        return total / Float(observations.count)
    }
}
