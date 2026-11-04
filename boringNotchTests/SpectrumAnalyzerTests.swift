//
//  SpectrumAnalyzerTests.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import XCTest
@testable import boringNotch

final class SpectrumAnalyzerTests: XCTestCase {
    func testAxisSpansTwentyHertzToTwentyKilohertz() {
        XCTAssertEqual(SpectrumScale.hz(atFraction: 0), 20, accuracy: 1e-9)
        XCTAssertEqual(SpectrumScale.hz(atFraction: 1), 20_000, accuracy: 1e-6)
        XCTAssertEqual(SpectrumScale.fraction(ofHz: 632.455), 0.5, accuracy: 1e-4)
    }

    func testLabelsAndNotes() {
        XCTAssertEqual(SpectrumScale.label(forHz: 62.4), "62 Hz")
        XCTAssertEqual(SpectrumScale.label(forHz: 1250), "1.25k")
        XCTAssertEqual(SpectrumScale.label(forHz: 2000), "2k")
        XCTAssertEqual(SpectrumScale.label(forHz: 12_500), "12.5k")
        XCTAssertEqual(SpectrumScale.noteName(forHz: 440), "A4")
        XCTAssertEqual(SpectrumScale.noteName(forHz: 261.63), "C4")
        XCTAssertEqual(SpectrumScale.noteName(forHz: 41.2), "E1")
    }

    func testBandLayoutInterpolatesNarrowLowBandsAndAveragesWideOnes() {
        let layout = SpectrumBandLayout.make(sampleRate: 48_000, fftSize: 8192)
        XCTAssertEqual(layout.count, SpectrumScale.bandCount)
        guard case .interpolated(let lower, let fraction) = layout[0] else {
            return XCTFail("20 Hz band is narrower than a 5.9 Hz bin and should interpolate")
        }
        XCTAssertGreaterThanOrEqual(lower, 1)
        XCTAssert((0..<1).contains(fraction))
        guard case .bins(let range) = layout[layout.count - 1] else {
            return XCTFail("top band spans many bins and should average them")
        }
        XCTAssertGreaterThan(range.count, 1)
        XCTAssertLessThanOrEqual(range.upperBound, 4096)
    }

    func testBandLayoutStaysInsideTheSpectrumAtLowSampleRates() {
        for source in SpectrumBandLayout.make(sampleRate: 16_000, fftSize: 8192) {
            switch source {
            case .bins(let range): XCTAssertLessThanOrEqual(range.upperBound, 4096)
            case .interpolated(let lower, _): XCTAssertLessThan(lower + 1, 4096)
            }
        }
    }

    func testPeakJumpsUpThenHoldsBeforeFalling() {
        let state = SpectrumAnalyzerState()
        var loud = [Float](repeating: -80, count: SpectrumScale.bandCount)
        for i in 34...46 { loud[i] = -10 }
        var t = 0.0
        for _ in 0..<30 { state.advance(levelsDB: loud, now: t); t += 1.0 / 60 }
        let held = state.peak[40]
        XCTAssertGreaterThan(held, 0.8)

        let quiet = [Float](repeating: -80, count: SpectrumScale.bandCount)
        // Within the hold time the peak stays put while the live trace drops.
        for _ in 0..<12 { state.advance(levelsDB: quiet, now: t); t += 1.0 / 60 }
        XCTAssertEqual(state.peak[40], held, accuracy: 0.001)
        XCTAssertLessThan(state.live[40], held)

        // After the hold it falls, but slowly rather than snapping down.
        for _ in 0..<30 { state.advance(levelsDB: quiet, now: t); t += 1.0 / 60 }
        XCTAssertLessThan(state.peak[40], held)
        XCTAssertGreaterThan(state.peak[40], held - 0.3)
    }

    func testNoCaptureLetsTracesFallToTheFloor() {
        let state = SpectrumAnalyzerState()
        let loud = [Float](repeating: -10, count: SpectrumScale.bandCount)
        var t = 0.0
        for _ in 0..<10 { state.advance(levelsDB: loud, now: t); t += 1.0 / 60 }
        for _ in 0..<600 { state.advance(levelsDB: nil, now: t); t += 1.0 / 60 }
        XCTAssertLessThan(state.live.max() ?? 1, 0.01)
        XCTAssertLessThan(state.peak.max() ?? 1, 0.01)
    }

    func testPeakMarkersPickTheLoudestSeparatedMaxima() {
        var trace = [Float](repeating: 0.1, count: 96)
        trace[10] = 0.9; trace[11] = 0.85   // one hump: only its top counts
        trace[40] = 0.7
        trace[42] = 0.75                    // too close to 40: dropped
        trace[80] = 0.5
        trace[90] = 0.15                    // below threshold
        let markers = SpectrumAnalyzerState.peakMarkers(in: trace)
        XCTAssertEqual(markers.map(\.level), [0.9, 0.75, 0.5])
        XCTAssertEqual(markers[0].fraction, 10.0 / 95, accuracy: 1e-9)
    }
}
