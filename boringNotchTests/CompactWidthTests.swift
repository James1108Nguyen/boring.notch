//
//  CompactWidthTests.swift
//  boringNotchTests
//

import CoreGraphics
import Defaults
import XCTest

@testable import boringNotch

final class CompactWidthTests: XCTestCase {
    private var savedWidth: CGFloat = CompactWidth.default

    override func setUp() {
        super.setUp()
        savedWidth = Defaults[.compactOpenWidth]
    }

    override func tearDown() {
        Defaults[.compactOpenWidth] = savedWidth
        super.tearDown()
    }

    func testDefaultKeepsTheOriginalCompactWidth() {
        // Existing users must see no change until they touch the slider.
        XCTAssertEqual(CompactWidth.default, 336)
        XCTAssertTrue(CompactWidth.range.contains(CompactWidth.default))
    }

    func testClampingHoldsValuesInsideTheSupportedRange() {
        XCTAssertEqual(CompactWidth.clamped(0), CompactWidth.range.lowerBound)
        XCTAssertEqual(CompactWidth.clamped(-50), CompactWidth.range.lowerBound)
        XCTAssertEqual(CompactWidth.clamped(10_000), CompactWidth.range.upperBound)
        XCTAssertEqual(CompactWidth.clamped(300), 300)
        XCTAssertEqual(CompactWidth.clamped(CompactWidth.range.lowerBound), CompactWidth.range.lowerBound)
        XCTAssertEqual(CompactWidth.clamped(CompactWidth.range.upperBound), CompactWidth.range.upperBound)
    }

    func testClampingRejectsNonFiniteValues() {
        XCTAssertEqual(CompactWidth.clamped(.nan), CompactWidth.default)
        XCTAssertEqual(CompactWidth.clamped(.infinity), CompactWidth.range.upperBound)
        XCTAssertEqual(CompactWidth.clamped(-.infinity), CompactWidth.range.lowerBound)
    }

    func testRangeFitsInsideTheWindow() {
        // The window is sized for the full layout; compact must never be
        // wider than it or the panel would be clipped.
        XCTAssertLessThanOrEqual(CompactWidth.range.upperBound, windowSize.width)
    }

    func testContentWidthFollowsTheStoredSetting() {
        Defaults[.compactOpenWidth] = 300
        XCTAssertEqual(compactOpenContentWidth, 300)

        // A stale or hand-edited value outside the range is clamped on read.
        Defaults[.compactOpenWidth] = 9_999
        XCTAssertEqual(compactOpenContentWidth, CompactWidth.range.upperBound)
    }
}
