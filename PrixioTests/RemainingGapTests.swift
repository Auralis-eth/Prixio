//
//  RemainingGapTests.swift
//  PrixioTests
//
//  Closes the last reliably-testable branches surfaced by the ship-readiness review: the
//  receipt-import JPEG-encoding failure (the only throwing path, previously unexercised), the
//  MonthBucket year-boundary behavior, and the package-mode dominant-unit-family count-tie that
//  is broken by recency (the branch that decides which prices enter every package-mode total).
//

import Foundation
import SwiftData
import Testing
import UIKit
@testable import Prixio

// MARK: - ReceiptImportService error / happy paths

@Suite(.serialized)
@MainActor
struct ReceiptImportServiceErrorTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ReceiptCapture.self, ReceiptLineItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// A 1×1 opaque image that JPEG-encodes successfully.
    private func solidImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }

    @Test
    func importImage_persistsCaptureWithImage_givenEncodableImage() throws {
        let context = try makeContext()
        let service = ReceiptImportService(context: context)

        let capture = try service.importImage(solidImage(), source: .cameraPhoto)

        #expect(capture.imageData != nil)
        #expect(capture.source == .cameraPhoto)
        #expect(capture.reviewState == .pendingReview)
        #expect(try context.fetch(FetchDescriptor<ReceiptCapture>()).count == 1)
    }

    @Test
    func importImage_throwsImageEncodingFailed_givenUnencodableImage() throws {
        let context = try makeContext()
        let service = ReceiptImportService(context: context)

        // An empty UIImage has no backing bitmap, so jpegData(...) returns nil and the service must
        // throw rather than persist an imageless capture the user could never re-review.
        #expect(throws: ReceiptImportError.imageEncodingFailed) {
            try service.importImage(UIImage(), source: .importedImage)
        }
        // Nothing was persisted on the failure path.
        #expect(try context.fetch(FetchDescriptor<ReceiptCapture>()).isEmpty)
    }
}

// MARK: - MonthBucket year boundary

struct MonthBucketBoundaryTests {
    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test
    func contains_isFalseAcrossTheDecemberToJanuaryYearBoundary() {
        let calendar = utcCalendar()
        let january2027 = date(2027, 1, 1, calendar: calendar)

        // Dec 31 of the prior year is a different month AND year -> not contained.
        #expect(!MonthBucket.contains(date(2026, 12, 31, calendar: calendar), month: january2027, calendar: calendar))
        // Mid-January of the same year is contained.
        #expect(MonthBucket.contains(date(2027, 1, 15, calendar: calendar), month: january2027, calendar: calendar))
        // Same month number but a different year is NOT the same bucket.
        #expect(!MonthBucket.contains(date(2026, 1, 15, calendar: calendar), month: january2027, calendar: calendar))
    }

    @Test
    func start_returnsFirstInstantOfMonth_acrossYearBoundary() {
        let calendar = utcCalendar()
        let lateDecember = date(2026, 12, 31, calendar: calendar)

        let start = MonthBucket.start(of: lateDecember, calendar: calendar)
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: start)
        #expect(components.year == 2026)
        #expect(components.month == 12)
        #expect(components.day == 1)
        #expect(components.hour == 0)
    }

    @Test
    func displayName_distinguishesSameMonthInDifferentYears() {
        let calendar = utcCalendar()
        let jan2026 = MonthBucket.displayName(for: date(2026, 1, 10, calendar: calendar), calendar: calendar)
        let jan2027 = MonthBucket.displayName(for: date(2027, 1, 10, calendar: calendar), calendar: calendar)

        #expect(jan2026 != jan2027)
        #expect(jan2027.contains("2027"))
    }
}

// MARK: - Package-mode dominant unit family: count-tie broken by recency

struct DominantUnitTieBreakTests {
    private func entry(price: String, unit: UnitType, capturedDaysAgo: Int, now: Date) -> PriceEntry {
        let captured = Calendar.current.date(byAdding: .day, value: -capturedDaysAgo, to: now) ?? now
        return PriceEntry(
            capturedAt: captured,
            itemNameRaw: "Apples",
            itemNameNormalized: ItemKeyNormalizer.normalize("Apples"),
            priceValue: Decimal(string: price)!,
            unitType: unit,
            photoAssetId: ""
        )
    }

    @Test
    func packageMode_breaksUnitFamilyCountTie_byMoreRecentCapture() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // One $/each and one $/kg observation — a 1–1 count tie. The dominant family is broken by the
        // more recent capture, so the incompatible older family is dropped from the package-mode totals.
        let kgIsNewer = [
            entry(price: "1.00", unit: .each, capturedDaysAgo: 10, now: now),
            entry(price: "5.00", unit: .kg, capturedDaysAgo: 1, now: now)
        ]
        let kgHistory = try #require(PriceInsightEngine.computeItemHistory(
            itemKey: ItemKeyNormalizer.normalize("Apples"),
            displayName: "Apples",
            useNormalizedPricing: false,
            allEntries: kgIsNewer,
            now: now
        ))
        #expect(kgHistory.observationCount == 1)
        #expect(kgHistory.latest.unitType == .kg)
        #expect(kgHistory.latest.price == Decimal(string: "5.00"))

        // Flip recency: now $/each is the more recent capture, so it wins the tie instead.
        let eachIsNewer = [
            entry(price: "5.00", unit: .kg, capturedDaysAgo: 10, now: now),
            entry(price: "1.00", unit: .each, capturedDaysAgo: 1, now: now)
        ]
        let eachHistory = try #require(PriceInsightEngine.computeItemHistory(
            itemKey: ItemKeyNormalizer.normalize("Apples"),
            displayName: "Apples",
            useNormalizedPricing: false,
            allEntries: eachIsNewer,
            now: now
        ))
        #expect(eachHistory.observationCount == 1)
        #expect(eachHistory.latest.unitType == .each)
        #expect(eachHistory.latest.price == Decimal(string: "1.00"))
    }
}
