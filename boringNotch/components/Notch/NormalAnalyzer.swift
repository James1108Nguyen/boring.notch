//
//  NormalAnalyzer.swift
//  boringNotch
//
//  The spectrum analyzer in the standard (non-compact) layout. Compact mode
//  has always had it; this gives normal mode the same analyzer in one of two
//  places, chosen in Settings › Notch:
//
//    • below the player — the notch grows by the analyzer's height, exactly
//      as compact's does, and a small waveform button shows or hides it. The
//      on/off state is the same showSpectrumAnalyzer switch compact uses.
//    • a third "Analyzer" tab beside Home and Shelf — a page of its own, so
//      the notch keeps its size.
//
//  The rest of the app only needs to know about NormalHomeContainer and
//  NormalAnalyzerPage (ContentView), NormalAnalyzer.tabs (the tab bar) and
//  NormalAnalyzerSettingRow (Settings). NotchHomeView is wrapped, not edited.
//

import Defaults
import SwiftUI

enum NormalAnalyzerStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case belowPlayer
    case tab
    case off

    var id: String { rawValue }
}

extension Defaults.Keys {
    /// Where normal mode shows the analyzer. Declared here, not in
    /// Constants.swift, which upstream edits constantly.
    static let normalAnalyzerStyle = Key<NormalAnalyzerStyle>("normalAnalyzerStyle", default: .belowPlayer)
}

/// The Home and Shelf tabs from TabSelectionView. Named here because inside
/// NormalAnalyzer the bare name `tabs` means the function below.
private let homeAndShelfTabs = tabs

enum NormalAnalyzer {
    /// Height of the analyzer page in the tab style: the opened notch's
    /// content area (190 less the 38 pt tab bar and 12 pt bottom padding).
    static let tabPageHeight: CGFloat = 140

    private static let analyzerTab = TabModel(label: "Analyzer", icon: "waveform", view: .analyzer)
    // Built once: TabModel ids drive the tab bar's selection animation, so
    // they must not change from one render to the next.
    private static let tabsWithAnalyzer = homeAndShelfTabs + [analyzerTab]

    static func tabs(for style: NormalAnalyzerStyle) -> [TabModel] {
        style == .tab ? tabsWithAnalyzer : homeAndShelfTabs
    }

    static func inlineVisible(style: NormalAnalyzerStyle, shown: Bool, page: NotchViews) -> Bool {
        style == .belowPlayer && shown && page == .home
    }

    /// How much taller the opened notch gets for the inline analyzer.
    static func extraHeight(inlineVisible: Bool) -> CGFloat {
        inlineVisible ? compactAnalyzerHeight + compactAnalyzerSpacing : 0
    }

    /// The analyzer page only exists in the tab style. If the style is
    /// switched away while it is the remembered page, show Home instead.
    static func effectivePage(_ page: NotchViews, style: NormalAnalyzerStyle) -> NotchViews {
        page == .analyzer && style != .tab ? .home : page
    }
}

/// Home, with the analyzer strip below it when the style and switch allow.
struct NormalHomeContainer: View {
    @Default(.normalAnalyzerStyle) private var style
    @Default(.showSpectrumAnalyzer) private var shown

    let albumArtNamespace: Namespace.ID
    let horizontalMediaGestureFeedback: CGFloat
    @Binding var isHoveringMusicArea: Bool

    private var inline: Bool {
        NormalAnalyzer.inlineVisible(style: style, shown: shown, page: .home)
    }

    var body: some View {
        // Leading-aligned like the NotchLayout stack Home used to sit in
        // directly: the analyzer is full width, which would otherwise make
        // this stack as wide as the notch and centre Home inside it.
        VStack(alignment: .leading, spacing: 0) {
            NotchHomeView(
                albumArtNamespace: albumArtNamespace,
                horizontalMediaGestureFeedback: horizontalMediaGestureFeedback,
                isHoveringMusicArea: $isHoveringMusicArea
            )

            if inline {
                SpectrumAnalyzerView()
                    .frame(height: compactAnalyzerHeight)
                    .padding(.top, compactAnalyzerSpacing)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(.white.opacity(0.08))
                            .frame(height: 0.5)
                            .padding(.top, compactAnalyzerSpacing / 2)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .overlay(alignment: .bottomLeading) {
            if style == .belowPlayer {
                toggleButton
                    // Stay at the bottom of Home, not of the analyzer strip.
                    .padding(.bottom, NormalAnalyzer.extraHeight(inlineVisible: inline))
            }
        }
    }

    private var toggleButton: some View {
        Button {
            withAnimation(.smooth(duration: 0.3)) { shown.toggle() }
        } label: {
            Image(systemName: "waveform")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(shown ? Color.effectiveAccent : Color.gray)
                .frame(width: 22, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 6)
        .help(shown ? "Hide spectrum analyzer" : "Show spectrum analyzer")
        .accessibilityLabel(shown ? "Hide spectrum analyzer" : "Show spectrum analyzer")
    }
}

/// The page behind the "Analyzer" tab.
struct NormalAnalyzerPage: View {
    @Default(.normalAnalyzerStyle) private var style
    @ObservedObject private var coordinator = BoringViewCoordinator.shared

    let albumArtNamespace: Namespace.ID
    let horizontalMediaGestureFeedback: CGFloat
    @Binding var isHoveringMusicArea: Bool

    var body: some View {
        if NormalAnalyzer.effectivePage(.analyzer, style: style) == .analyzer {
            SpectrumAnalyzerView()
                .frame(maxWidth: .infinity)
                .frame(height: NormalAnalyzer.tabPageHeight)
        } else {
            // The tab is gone (style changed). Draw Home now and make it the
            // current page so the rest of the app agrees.
            NormalHomeContainer(
                albumArtNamespace: albumArtNamespace,
                horizontalMediaGestureFeedback: horizontalMediaGestureFeedback,
                isHoveringMusicArea: $isHoveringMusicArea
            )
            .onAppear { coordinator.currentView = .home }
        }
    }
}

struct NormalAnalyzerSettingRow: View {
    @Default(.normalAnalyzerStyle) private var style

    var body: some View {
        Picker("Analyzer in normal mode", selection: $style) {
            Text("Below the player").tag(NormalAnalyzerStyle.belowPlayer)
            Text("Separate tab").tag(NormalAnalyzerStyle.tab)
            Text("Off").tag(NormalAnalyzerStyle.off)
        }
        if style == .tab {
            Text("The tab sits in the tab bar, which is hidden while the Shelf is turned off.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
