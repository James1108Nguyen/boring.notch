//
//  AnalyzerOptionsTests.swift
//  boringNotchTests
//

import XCTest

@testable import boringNotch

final class AnalyzerOptionsTests: XCTestCase {
    // MARK: Defaults and ranges

    func testDefaultsKeepTheAnalyzerLookingAsItAlwaysHas() {
        // Anyone who never opens the new pane must see no change.
        XCTAssertEqual(AnalyzerOptions.defaultHeight, 84)
        XCTAssertEqual(AnalyzerOptions.defaultDynamicRange, 60)
        XCTAssertEqual(AnalyzerOptions.defaultPeakHold, 0.4)
        XCTAssertTrue(AnalyzerOptions.heightRange.contains(AnalyzerOptions.defaultHeight))
        XCTAssertTrue(AnalyzerOptions.dynamicRangeRange.contains(AnalyzerOptions.defaultDynamicRange))
        XCTAssertTrue(AnalyzerOptions.peakHoldRange.contains(AnalyzerOptions.defaultPeakHold))
    }

    func testColorStorageValuesAreStable() {
        XCTAssertEqual(AnalyzerColor.blue.rawValue, "blue")
        XCTAssertEqual(AnalyzerColor.albumArt.rawValue, "albumArt")
        XCTAssertEqual(AnalyzerColor.accent.rawValue, "accent")
    }

    // MARK: Clamping

    func testHeightIsClampedAndNeverNaN() {
        XCTAssertEqual(AnalyzerOptions.clampedHeight(0), AnalyzerOptions.heightRange.lowerBound)
        XCTAssertEqual(AnalyzerOptions.clampedHeight(10_000), AnalyzerOptions.heightRange.upperBound)
        XCTAssertEqual(AnalyzerOptions.clampedHeight(100), 100)
        XCTAssertEqual(AnalyzerOptions.clampedHeight(.nan), AnalyzerOptions.defaultHeight)
    }

    func testDynamicRangeIsClampedAndNeverNaN() {
        XCTAssertEqual(AnalyzerOptions.clampedDynamicRange(1), AnalyzerOptions.dynamicRangeRange.lowerBound)
        XCTAssertEqual(AnalyzerOptions.clampedDynamicRange(500), AnalyzerOptions.dynamicRangeRange.upperBound)
        XCTAssertEqual(AnalyzerOptions.clampedDynamicRange(.nan), AnalyzerOptions.defaultDynamicRange)
    }

    func testPeakHoldIsClampedAndNeverNaN() {
        XCTAssertEqual(AnalyzerOptions.clampedPeakHold(-3), AnalyzerOptions.peakHoldRange.lowerBound)
        XCTAssertEqual(AnalyzerOptions.clampedPeakHold(99), AnalyzerOptions.peakHoldRange.upperBound)
        XCTAssertEqual(AnalyzerOptions.clampedPeakHold(.nan), AnalyzerOptions.defaultPeakHold)
    }

    // MARK: Window

    func testWindowFitsTheTallestAnalyzerStrip() {
        // The window is created once, so it has to be sized for the largest
        // strip the slider allows or the notch would be clipped.
        let tallest = openNotchSize.height + AnalyzerOptions.heightRange.upperBound
            + compactAnalyzerSpacing + shadowPadding
        XCTAssertLessThanOrEqual(tallest, windowSize.height)
    }

    // MARK: Behaviour

    private func levels(loudBand: Int = 40, loud: Float = 0, others: Float = -30) -> [Float] {
        (0..<SpectrumScale.bandCount).map { $0 == loudBand ? loud : others }
    }

    /// Feeds the same levels for `frames` frames at 60 fps.
    private func settle(_ state: SpectrumAnalyzerState, levels: [Float]?, frames: Int, from start: Double = 0) -> Double {
        var t = start
        for _ in 0..<frames {
            state.advance(levelsDB: levels, now: t)
            t += 1.0 / 60
        }
        return t
    }

    func testWiderDynamicRangeShowsQuietBandsHigher() {
        let narrow = SpectrumAnalyzerState()
        narrow.dynamicRange = 40
        let wide = SpectrumAnalyzerState()
        wide.dynamicRange = 80

        _ = settle(narrow, levels: levels(), frames: 120)
        _ = settle(wide, levels: levels(), frames: 120)

        // A band 30 dB under the loudest one: 25% of a 40 dB range, 62.5% of 80.
        XCTAssertGreaterThan(wide.live[10], narrow.live[10] + 0.2)
    }

    func testLongerPeakHoldKeepsThePeakUpLonger() {
        let short = SpectrumAnalyzerState()
        short.peakHoldSeconds = 0.1
        let long = SpectrumAnalyzerState()
        long.peakHoldSeconds = 2.0

        let tShort = settle(short, levels: levels(), frames: 60)
        let tLong = settle(long, levels: levels(), frames: 60)
        // Then silence for one second.
        _ = settle(short, levels: nil, frames: 60, from: tShort)
        _ = settle(long, levels: nil, frames: 60, from: tLong)

        XCTAssertGreaterThan(long.peak[40], short.peak[40] + 0.1)
    }

    func testDefaultStateMatchesTheDefaults() {
        let state = SpectrumAnalyzerState()
        XCTAssertEqual(state.dynamicRange, AnalyzerOptions.defaultDynamicRange)
        XCTAssertEqual(state.peakHoldSeconds, AnalyzerOptions.defaultPeakHold)
    }
}
