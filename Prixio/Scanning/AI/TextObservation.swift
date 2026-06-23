//
//  TextObservation.swift
//  Prixio
//
//  Source-agnostic line of recognized text. Replaces the hard dependency on
//  OCRTextObservation (Vision) throughout the surviving parsing/scoring helpers,
//  so the validator can re-read the model's own transcription instead of Vision
//  observations.
//

import Foundation

protocol TextObservation: Sendable {
    var string: String { get }
    var confidence: Float { get }
}

struct PlainTextObservation: TextObservation {
    let string: String
    let confidence: Float
}
