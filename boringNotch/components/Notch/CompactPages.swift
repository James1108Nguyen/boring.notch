//
//  CompactPages.swift
//  boringNotch
//
//  Pages for the compact opened notch. Compact mode used to show only the
//  player; this lets it also show the Shelf (AirDrop + dropped files)
//  without growing: the Shelf page is laid over the player and takes
//  exactly the player's size, so switching pages never resizes the notch.
//
//  Everything lives here so the rest of the app only has to know about
//  CompactContainerView. It composes the standard Shelf pieces
//  (FileShareView, ShelfItemView, ShelfStateViewModel) rather than copying
//  them, so a change to their API fails to compile instead of silently
//  drifting. The page itself is the existing BoringViewCoordinator
//  .currentView, so the drag-to-open flow that already sets it to .shelf
//  works here unchanged.
//

import Defaults
import SwiftUI
import UniformTypeIdentifiers

extension Defaults.Keys {
    /// Lets the compact notch show the Shelf. Off by default, which keeps
    /// compact mode exactly as it was: player only, currentView ignored.
    static let compactAllowShelf = Key<Bool>("compactAllowShelf", default: false)
}

enum CompactPage: Equatable {
    case player
    case shelf

    static func resolve(allowShelf: Bool, shelfEnabled: Bool, currentView: NotchViews) -> CompactPage {
        allowShelf && shelfEnabled && currentView == .shelf ? .shelf : .player
    }

    var toggled: CompactPage {
        self == .player ? .shelf : .player
    }

    var notchView: NotchViews {
        self == .player ? .home : .shelf
    }

    /// Horizontal swipes change the track only over the player; over the
    /// shelf they belong to the file list.
    func allowsMusicHover(pointerInside: Bool) -> Bool {
        pointerInside && self == .player
    }
}

/// Sizes of the compact Shelf page. The page matches the player's height so
/// switching never resizes the notch — except when the player has grown
/// (e.g. an open spectrum analyzer adds ~92 pt): the shelf then keeps its own
/// size rather than stretching around two files and an AirDrop tile.
enum CompactShelfLayout {
    /// The compact player without anything extra is ~134 pt tall; this leaves
    /// a little room above that so the shelf can always match it exactly.
    static let maxHeight: CGFloat = 144
    static let horizontalPadding: CGFloat = 12
    static let spacing: CGFloat = 8
    /// FileShareView lays out a 55 pt circle inside 18 pt of padding, so this
    /// is about as narrow as the standard AirDrop tile can go unmodified. It
    /// keeps AirDrop to a third of the width — in the full layout it is about
    /// a quarter — so the drop zone gets most of the room.
    static let airDropWidth: CGFloat = 104

    static func height(forPlayerHeight playerHeight: CGFloat) -> CGFloat {
        // Until the player has been measured (0, or not a number) use the cap.
        guard playerHeight.isFinite, playerHeight > 0 else { return maxHeight }
        return min(playerHeight, maxHeight)
    }

    static func dropZoneWidth(forContentWidth width: CGFloat) -> CGFloat {
        width - 2 * horizontalPadding - spacing - airDropWidth
    }
}

struct CompactContainerView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    @Default(.compactAllowShelf) private var allowShelf
    @Default(.boringShelf) private var shelfEnabled

    let albumArtNamespace: Namespace.ID
    let horizontalMediaGestureFeedback: CGFloat
    @Binding var isHoveringMusicArea: Bool

    @State private var pointerInside = false
    /// The player's natural height, kept up to date even while it is hidden.
    @State private var playerHeight: CGFloat = 0

    private var pagesEnabled: Bool { allowShelf && shelfEnabled }

    private var page: CompactPage {
        CompactPage.resolve(
            allowShelf: allowShelf,
            shelfEnabled: shelfEnabled,
            currentView: coordinator.currentView
        )
    }

    var body: some View {
        // The player stays in the layout (just invisible and inert) while the
        // shelf is up, because it is what sizes the container: the shelf is
        // an overlay and so takes that size exactly. Its own height is read
        // before the frame below, which on the shelf page caps the container
        // so a tall player (open analyzer) does not stretch the shelf.
        CompactHomeView(
            albumArtNamespace: albumArtNamespace,
            horizontalMediaGestureFeedback: horizontalMediaGestureFeedback
        )
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { playerHeight = $0 }
        .frame(
            height: page == .shelf ? CompactShelfLayout.height(forPlayerHeight: playerHeight) : nil,
            alignment: .top
        )
        .opacity(page == .shelf ? 0 : 1)
        .allowsHitTesting(page == .player)
        .accessibilityHidden(page == .shelf)
        .overlay {
            if page == .shelf {
                CompactShelfView(dropInteraction: vm.dropInteraction)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topLeading) {
            if pagesEnabled {
                pageButton
            }
        }
        .onHover { hovering in
            pointerInside = hovering
            syncMusicHover()
        }
        .onChange(of: page) { _, _ in syncMusicHover() }
        .onDisappear { isHoveringMusicArea = false }
    }

    private func syncMusicHover() {
        isHoveringMusicArea = page.allowsMusicHover(pointerInside: pointerInside)
    }

    /// Sits in the strip beside the hardware notch, mirroring the battery
    /// indicator on the other side (which is also offset up out of the
    /// player's own bounds).
    private var pageButton: some View {
        Button {
            withAnimation(.smooth(duration: 0.25)) {
                coordinator.currentView = page.toggled.notchView
            }
        } label: {
            Image(systemName: page == .shelf ? "music.note" : "tray.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.gray)
                .frame(width: 24, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 12)
        .offset(y: -12)
        .help(page == .shelf ? "Show player" : "Show shelf")
        .accessibilityLabel(page == .shelf ? "Show player" : "Show shelf")
    }
}

/// The Shelf laid out for the compact panel, like the full layout shrunk:
/// a narrow AirDrop tile on the left and the file drop zone filling the rest.
private struct CompactShelfView: View {
    let dropInteraction: DropInteractionState
    @StateObject private var shelfState = ShelfStateViewModel.shared
    @State private var quickLook = QuickLookService()

    private let spacing = CompactShelfLayout.spacing
    // The player pads its content 4 pt at the top and 2 pt at the bottom.
    private let topPadding: CGFloat = 4
    private let bottomPadding: CGFloat = 2

    private var displayedItems: [ShelfItem] {
        Defaults[.reverseShelfOrdering] ? Array(shelfState.items.reversed()) : shelfState.items
    }

    var body: some View {
        GeometryReader { geo in
            let side = max(0, geo.size.height - topPadding - bottomPadding)
            HStack(spacing: spacing) {
                FileShareView(dropInteraction: dropInteraction)
                    .frame(width: CompactShelfLayout.airDropWidth, height: side)
                panel
                    .frame(height: side)
            }
            .padding(.horizontal, CompactShelfLayout.horizontalPadding)
            .padding(.top, topPadding)
        }
        .quickLookPresenter(using: quickLook)
    }

    private var panel: some View {
        @Bindable var interaction = dropInteraction

        return RoundedRectangle(cornerRadius: 16)
            .stroke(
                interaction.dragDetectorTargeting
                    ? Color.accentColor.opacity(0.9)
                    : Color.white.opacity(0.1),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10])
            )
            .background {
                // Clicking empty space clears the selection, as in the full
                // Shelf; taps on a file land on the file, not here.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { ShelfSelectionModel.shared.clear() }
            }
            .overlay { content.padding(.horizontal, 6).padding(.vertical, 4) }
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .onDrop(
                of: [.fileURL, .url, .utf8PlainText, .plainText, .data],
                isTargeted: $interaction.dragDetectorTargeting
            ) { providers in
                handleDrop(providers: providers)
            }
    }

    @ViewBuilder
    private var content: some View {
        if shelfState.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down")
                    .symbolVariant(.fill)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white, .gray)
                    .imageScale(.large)

                Text("Drop files here")
                    .foregroundStyle(.gray)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.medium)
            }
        } else {
            ScrollView(.horizontal) {
                LazyHStack(spacing: spacing) {
                    ForEach(displayedItems) { item in
                        ShelfItemView(
                            item: item,
                            quickLookService: quickLook,
                            dropInteraction: dropInteraction
                        )
                    }
                }
            }
            .scrollIndicators(.never)
            .onAppear { shelfState.cleanupInvalidItems() }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !ShelfSelectionModel.shared.isDragging else { return false }
        dropInteraction.dropEvent = true
        shelfState.load(providers)
        return true
    }
}
