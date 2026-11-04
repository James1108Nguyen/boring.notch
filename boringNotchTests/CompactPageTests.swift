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
