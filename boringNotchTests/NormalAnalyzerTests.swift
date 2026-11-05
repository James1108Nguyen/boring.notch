//
//  NormalAnalyzerTests.swift
//  boringNotchTests
//

import XCTest

@testable import boringNotch

final class NormalAnalyzerTests: XCTestCase {
    // MARK: Style

    func testStyleStorageValuesAreStable() {
        // These are persisted; renaming a case would silently reset users.
        XCTAssertEqual(NormalAnalyzerStyle.belowPlayer.rawValue, "belowPlayer")
        XCTAssertEqual(NormalAnalyzerStyle.tab.rawValue, "tab")
        XCTAssertEqual(NormalAnalyzerStyle.off.rawValue, "off")
        XCTAssertEqual(NormalAnalyzerStyle.allCases.count, 3)
    }

    // MARK: Inline strip

    func testInlineStripShowsOnlyBelowThePlayerWhenSwitchedOnAtHome() {
        XCTAssertTrue(NormalAnalyzer.inlineVisible(style: .belowPlayer, shown: true, page: .home))
    }

    func testInlineStripIsHiddenWhenSwitchedOff() {
        XCTAssertFalse(NormalAnalyzer.inlineVisible(style: .belowPlayer, shown: false, page: .home))
    }

    func testInlineStripNeverShowsForTheOtherStyles() {
        XCTAssertFalse(NormalAnalyzer.inlineVisible(style: .tab, shown: true, page: .home))
        XCTAssertFalse(NormalAnalyzer.inlineVisible(style: .off, shown: true, page: .home))
    }

    func testInlineStripOnlyBelongsToTheHomePage() {
        XCTAssertFalse(NormalAnalyzer.inlineVisible(style: .belowPlayer, shown: true, page: .shelf))
        XCTAssertFalse(NormalAnalyzer.inlineVisible(style: .belowPlayer, shown: true, page: .analyzer))
    }

    // MARK: Height

    func testOpenNotchGrowsByTheSameAmountAsCompactsAnalyzer() {
        XCTAssertEqual(
            NormalAnalyzer.extraHeight(inlineVisible: true),
            compactAnalyzerHeight + compactAnalyzerSpacing
        )
        XCTAssertEqual(NormalAnalyzer.extraHeight(inlineVisible: false), 0)
    }

    func testGrownNotchStillFitsInsideTheWindow() {
        // The window is sized for this; anything taller would be clipped.
        let grown = openNotchSize.height + NormalAnalyzer.extraHeight(inlineVisible: true)
        XCTAssertLessThanOrEqual(grown + shadowPadding, windowSize.height)
    }

    // MARK: Tabs

    func testTabBarGainsAnAnalyzerTabOnlyForTheTabStyle() {
        XCTAssertEqual(NormalAnalyzer.tabs(for: .tab).map(\.view), [.home, .shelf, .analyzer])
        XCTAssertEqual(NormalAnalyzer.tabs(for: .belowPlayer).map(\.view), [.home, .shelf])
        XCTAssertEqual(NormalAnalyzer.tabs(for: .off).map(\.view), [.home, .shelf])
    }

    func testTabsKeepTheirIdentityBetweenCalls() {
        // TabModel ids drive SwiftUI's animation; rebuilding them on every
        // render would restart the selection capsule's animation.
        XCTAssertEqual(NormalAnalyzer.tabs(for: .tab).map(\.id), NormalAnalyzer.tabs(for: .tab).map(\.id))
    }

    // MARK: Stale analyzer page

    func testAnalyzerPageFallsBackToHomeWhenTheTabIsGone() {
        // The user can switch the style away while the analyzer tab is the
        // remembered page.
        XCTAssertEqual(NormalAnalyzer.effectivePage(.analyzer, style: .belowPlayer), .home)
        XCTAssertEqual(NormalAnalyzer.effectivePage(.analyzer, style: .off), .home)
        XCTAssertEqual(NormalAnalyzer.effectivePage(.analyzer, style: .tab), .analyzer)
    }

    func testOtherPagesAreNeverRemapped() {
        for style in NormalAnalyzerStyle.allCases {
            XCTAssertEqual(NormalAnalyzer.effectivePage(.home, style: style), .home)
            XCTAssertEqual(NormalAnalyzer.effectivePage(.shelf, style: style), .shelf)
        }
    }
}
