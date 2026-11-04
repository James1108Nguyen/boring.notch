//
//  CompactPageTests.swift
//  boringNotchTests
//

import XCTest

@testable import boringNotch

final class CompactPageTests: XCTestCase {
    func testShelfShowsOnlyWhenEverythingAllowsIt() {
        XCTAssertEqual(
            CompactPage.resolve(allowShelf: true, shelfEnabled: true, currentView: .shelf),
            .shelf
        )
    }

    func testPlayerIsTheDefaultPage() {
        XCTAssertEqual(
            CompactPage.resolve(allowShelf: true, shelfEnabled: true, currentView: .home),
            .player
        )
    }

    func testCompactIgnoresTheShelfUnlessTheUserOptedIn() {
        // Upstream behaviour: a drag sets currentView = .shelf, but compact
        // keeps showing the player. The opt-in must not change that.
        XCTAssertEqual(
            CompactPage.resolve(allowShelf: false, shelfEnabled: true, currentView: .shelf),
            .player
        )
    }

    func testDisablingTheShelfFeatureWinsOverTheCompactOptIn() {
        XCTAssertEqual(
            CompactPage.resolve(allowShelf: true, shelfEnabled: false, currentView: .shelf),
            .player
        )
    }

    func testPageOpposite() {
        XCTAssertEqual(CompactPage.player.toggled, .shelf)
        XCTAssertEqual(CompactPage.shelf.toggled, .player)
        XCTAssertEqual(CompactPage.shelf.notchView, .shelf)
        XCTAssertEqual(CompactPage.player.notchView, .home)
    }

    func testMusicHoverIsOnlyActiveOnThePlayerPage() {
        XCTAssertTrue(CompactPage.player.allowsMusicHover(pointerInside: true))
        XCTAssertFalse(CompactPage.player.allowsMusicHover(pointerInside: false))
        // On the shelf, horizontal swipes must scroll files, not skip tracks.
        XCTAssertFalse(CompactPage.shelf.allowsMusicHover(pointerInside: true))
    }
}

final class CompactShelfLayoutTests: XCTestCase {
    private let cap = CompactShelfLayout.maxHeight

    func testShelfMatchesAPlayerThatIsShorterThanTheCap() {
        // Player without the analyzer: the shelf takes exactly its size, so
        // switching pages does not resize the notch.
        XCTAssertEqual(CompactShelfLayout.height(forPlayerHeight: 134), 134)
        XCTAssertEqual(CompactShelfLayout.height(forPlayerHeight: cap), cap)
    }

    func testShelfDoesNotStretchWithTheAnalyzer() {
        // With the analyzer open the player is ~92 pt taller; the shelf must
        // stay at its own size instead of ballooning around its contents.
        XCTAssertEqual(CompactShelfLayout.height(forPlayerHeight: 226), cap)
        XCTAssertEqual(CompactShelfLayout.height(forPlayerHeight: 10_000), cap)
    }

    func testShelfUsesTheCapUntilThePlayerHasBeenMeasured() {
        XCTAssertEqual(CompactShelfLayout.height(forPlayerHeight: 0), cap)
        XCTAssertEqual(CompactShelfLayout.height(forPlayerHeight: -5), cap)
        XCTAssertEqual(CompactShelfLayout.height(forPlayerHeight: .nan), cap)
    }

    func testAirDropTileStaysNarrowSoTheDropZoneKeepsMostOfTheWidth() {
        let available = CompactWidth.default - 2 * CompactShelfLayout.horizontalPadding
        let share = CompactShelfLayout.airDropWidth / available
        XCTAssertLessThan(share, 0.4)
        // FileShareView lays out a 55 pt circle inside 18 pt of padding.
        XCTAssertGreaterThanOrEqual(CompactShelfLayout.airDropWidth, 55 + 2 * 18)
    }

    func testDropZoneIsWiderThanTheAirDropTileAtEveryCompactWidth() {
        for width in [CompactWidth.range.lowerBound, CompactWidth.default, CompactWidth.range.upperBound] {
            let dropZone = CompactShelfLayout.dropZoneWidth(forContentWidth: width)
            XCTAssertGreaterThan(dropZone, CompactShelfLayout.airDropWidth, "at \(width) pt")
        }
    }
}
