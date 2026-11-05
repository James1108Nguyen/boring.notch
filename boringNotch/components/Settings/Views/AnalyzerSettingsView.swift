//
//  AnalyzerSettingsView.swift
//  boringNotch
//
//  One place for everything about the spectrum analyzer: turning on the
//  audio capture it needs, where it appears, how it looks, what it labels,
//  and how it moves. The analyzer's own defaults are what it always looked
//  like, so this pane changes nothing until it is used.
//

import Defaults
import SwiftUI

struct AnalyzerSettingsView: View {
    @Default(.analyzerColor) private var color
    @Default(.analyzerHeight) private var height
    @Default(.analyzerDynamicRange) private var dynamicRange
    @Default(.analyzerPeakHold) private var peakHold

    private var captureSupported: Bool {
        if #available(macOS 14.2, *) {
            return true
        }
        return false
    }

    private var dynamicRangeBounds: ClosedRange<Double> {
        Double(AnalyzerOptions.dynamicRangeRange.lowerBound)...Double(AnalyzerOptions.dynamicRangeRange.upperBound)
    }

    var body: some View {
        Form {
            generalSection
            appearanceSection
            displaySection
            behaviorSection
            resetSection
        }
        .formStyle(.grouped)
        .accentColor(.effectiveAccent)
        .navigationTitle("Analyzer")
    }

    // MARK: Sections

    private var generalSection: some View {
        Section {
            Defaults.Toggle(key: .realtimeAudioWaveform) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Real-time audio capture")
                    Group {
                        if captureSupported {
                            Text("The analyzer needs this to read the playing app's audio. Requires audio capture permission and uses slightly more CPU. Same switch as Real-time audio waveform in Media.")
                        } else {
                            Text("Requires macOS 14.2 or later.")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .disabled(!captureSupported)

            NormalAnalyzerSettingRow()

            Defaults.Toggle(key: .showSpectrumAnalyzer) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show the analyzer under the player")
                    Text("Also toggled by the waveform button in the notch. Shared by compact mode and the standard layout.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("General")
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker("Color", selection: $color) {
                Text("Blue").tag(AnalyzerColor.blue)
                Text("Album art").tag(AnalyzerColor.albumArt)
                Text("Accent color").tag(AnalyzerColor.accent)
            }

            Slider(value: $height, in: AnalyzerOptions.heightRange, step: 4) {
                HStack {
                    Text("Height")
                    Spacer()
                    Text("\(Int(AnalyzerOptions.clampedHeight(height))) pt")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        } header: {
            Text("Appearance")
        } footer: {
            Text("The height applies when the analyzer is shown under the player. The notch grows by this much when it is open.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var displaySection: some View {
        Section {
            Defaults.Toggle(key: .analyzerShowFrequencyLabels) {
                Text("Frequency labels")
            }
            Defaults.Toggle(key: .analyzerShowPeakLabels) {
                Text("Label the strongest peaks")
            }
            Defaults.Toggle(key: .analyzerShowCursor) {
                Text("Measuring cursor on hover")
            }
        } header: {
            Text("Display")
        }
    }

    private var behaviorSection: some View {
        Section {
            Slider(value: $dynamicRange, in: dynamicRangeBounds, step: 5) {
                HStack {
                    Text("Dynamic range")
                    Spacer()
                    Text("\(Int(AnalyzerOptions.clampedDynamicRange(Float(dynamicRange)))) dB")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Slider(value: $peakHold, in: AnalyzerOptions.peakHoldRange, step: 0.1) {
                HStack {
                    Text("Peak hold")
                    Spacer()
                    Text(
                        "\(AnalyzerOptions.clampedPeakHold(peakHold), format: .number.precision(.fractionLength(1))) s",
                        comment: "Analyzer peak hold, in seconds."
                    )
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
            }
        } header: {
            Text("Behavior")
        } footer: {
            Text("A narrower dynamic range makes the spectrum more dramatic; a wider one shows quieter detail. Peak hold is how long a peak stays before it falls.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var resetSection: some View {
        Section {
            Button("Reset appearance and behavior to defaults") {
                Defaults.reset(
                    .analyzerColor, .analyzerHeight, .analyzerShowFrequencyLabels,
                    .analyzerShowPeakLabels, .analyzerShowCursor,
                    .analyzerDynamicRange, .analyzerPeakHold
                )
            }
        }
    }
}
