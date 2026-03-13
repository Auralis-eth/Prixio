//
//  Array+string.swift
//  Prixio
//
//  Created by Daniel Bell on 3/11/26.
//


extension Array where Element == String {
    func containsSubphrase(_ candidate: [String]) -> Bool {
        guard !candidate.isEmpty, count >= candidate.count else {
            return false
        }
        guard count > candidate.count else {
            return false
        }

        for startIndex in 0...(count - candidate.count) {
            let slice = Array(self[startIndex..<(startIndex + candidate.count)])
            if slice == candidate {
                return true
            }
        }

        return false
    }
    
    func isNearMultiWordMatch(_ rhsWords: [String]) -> Bool {
        guard count >= 2, count == rhsWords.count else {
            return false
        }

        var nonExactCount = 0
        for (lhs, rhs) in zip(self, rhsWords) {
            if lhs == rhs {
                continue
            }

            guard lhs.isLikelyOCRTokenVariant(rhs) else {
                return false
            }

            nonExactCount += 1
            if nonExactCount > 1 {
                return false
            }
        }

        return true
    }
}
