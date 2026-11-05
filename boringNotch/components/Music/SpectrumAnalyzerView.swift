//
//  SpectrumAnalyzerView.swift
//  boringNotch
//
//  A Smaart-style real-time analyzer for the compact player: a filled live
//  spectrum with a peak-hold line over it (holds, then falls slowly), 20 Hz
//  to 20 kHz on a log axis, octave labels, the three strongest peaks pinned
//  with their frequency, and a measuring cursor on hover.
//
//  AudioCaptureManager supplies per-band dB values; everything that moves on
//  screen (auto-gain, attack/release, peak hold) happens here, per frame, so
//  the traces stay smooth at the display's refresh rate even though the FFT
//  only runs every 33 ms.
//

import Defaults
import SwiftUI

// MARK: - Frequency axis

enum SpectrumScale {
    static let bandCount = 96
    static let minHz: Double = 20
    static let maxHz: Double = 20_000

    /// Fraction across the log axis (0...1) → Hz.
    static func hz(atFraction x: Double) -> Double {
        exp(log(minHz) + x * (log(maxHz) - log(minHz)))
    }

    /// Hz → fraction across the log axis (0...1).
    static func fraction(ofHz hz: Double) -> Double {
        (log(hz) - log(minHz)) / (log(maxHz) - log(minHz))
    }

    /// Lower/upper edge of each band, log-spaced.
    static func bandEdges(count: Int = bandCount) -> [(lower: Double, upper: Double)] {
        (0..<count).map { i in
            (hz(atFraction: Double(i) / Double(count)), hz(atFraction: Double(i + 1) / Double(count)))
        }
    }

    /// "62 Hz", "1.25k", "12.5k".
    static func label(forHz hz: Double) -> String {
        if hz < 1000 { return "\(Int(hz.rounded())) Hz" }
        let khz = hz / 1000
        let text = String(format: khz < 10 ? "%.2f" : "%.1f", khz)
        return text.replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression) + "k"
    }

    private static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    /// Nearest equal-tempered note, A4 = 440 Hz: 440 → "A4", 62 → "B1".
    static func noteName(forHz hz: Double) -> String {
        let midi = Int((12 * log2(hz / 440) + 69).rounded())
        return noteNames[((midi % 12) + 12) % 12] + "\(midi / 12 - 1)"
    }
}

// MARK: - Band layout (used by AudioCaptureManager)

/// How one analyzer band reads the FFT: bands wider than a bin average their
/// bins; low bands narrower than a bin interpolate between the two nearest.
enum SpectrumBandSource: Equatable {
    case bins(Range<Int>)
    case interpolated(lower: Int, fraction: Float)
}

enum SpectrumBandLayout {
    static func make(sampleRate: Double, fftSize: Int) -> [SpectrumBandSource] {
        let binHz = sampleRate / Double(fftSize)
        let lastBin = fftSize / 2 - 1
        return SpectrumScale.bandEdges().map { edges in
            let first = max(1, Int(ceil(edges.lower / binHz)))
            let end = min(lastBin + 1, Int(ceil(edges.upper / binHz)))
            if end > first {
                return .bins(first..<end)
            }
            let center = min(Double(lastBin) - 1, max(1, sqrt(edges.lower * edges.upper) / binHz))
            let lower = Int(center)
            return .interpolated(lower: lower, fraction: Float(center - Double(lower)))
        }
    }
}

// MARK: - Options

enum AnalyzerColor: String, CaseIterable, Identifiable, Defaults.Serializable {
    case blue
    case albumArt
    case accent

    var id: String { rawValue }
}

/// What Settings › Analyzer can change. Values are clamped when read so a
/// stale or hand-edited preference can't produce an unusable analyzer, and
/// the defaults are what the analyzer always looked like.
enum AnalyzerOptions {
    static let heightRange: ClosedRange<CGFloat> = 60...140
    static let defaultHeight: CGFloat = 84
    static let dynamicRangeRange: ClosedRange<Float> = 40...90
    static let defaultDynamicRange: Float = 60
    static let peakHoldRange: ClosedRange<Double> = 0.1...2.0
    static let defaultPeakHold: Double = 0.4

    static func clampedHeight(_ value: CGFloat) -> CGFloat {
        value.isNaN ? defaultHeight : min(max(value, heightRange.lowerBound), heightRange.upperBound)
    }

    static func clampedDynamicRange(_ value: Float) -> Float {
        value.isNaN ? defaultDynamicRange : min(max(value, dynamicRangeRange.lowerBound), dynamicRangeRange.upperBound)
    }

    static func clampedPeakHold(_ value: Double) -> Double {
        value.isNaN ? defaultPeakHold : min(max(value, peakHoldRange.lowerBound), peakHoldRange.upperBound)
    }
}

extension Defaults.Keys {
    // Declared beside the analyzer rather than in Constants.swift, which
    // upstream edits constantly.
    static let analyzerColor = Key<AnalyzerColor>("analyzerColor", default: .blue)
    static let analyzerHeight = Key<CGFloat>("analyzerHeight", default: AnalyzerOptions.defaultHeight)
    static let analyzerShowFrequencyLabels = Key<Bool>("analyzerShowFrequencyLabels", default: true)
    static let analyzerShowPeakLabels = Key<Bool>("analyzerShowPeakLabels", default: true)
    static let analyzerShowCursor = Key<Bool>("analyzerShowCursor", default: true)
    static let analyzerDynamicRange = Key<Double>("analyzerDynamicRange", default: Double(AnalyzerOptions.defaultDynamicRange))
    static let analyzerPeakHold = Key<Double>("analyzerPeakHold", default: AnalyzerOptions.defaultPeakHold)
}

// MARK: - Motion

/// Turns raw band levels into what's drawn: auto-gained, smoothed live
/// trace plus a peak-hold trace. A class so the Canvas can advance it each
/// frame without triggering view updates.
final class SpectrumAnalyzerState {
    /// dB below the loudest band that still shows above the floor.
    var dynamicRange: Float = AnalyzerOptions.defaultDynamicRange
    /// How long a peak stays put before it starts to fall.
    var peakHoldSeconds: Double = AnalyzerOptions.defaultPeakHold

    private(set) var live = [Float](repeating: 0, count: SpectrumScale.bandCount)
    private(set) var peak = [Float](repeating: 0, count: SpectrumScale.bandCount)
    private var raw = [Float](repeating: 0, count: SpectrumScale.bandCount)
    private var smoothed = [Float](repeating: 0, count: SpectrumScale.bandCount)
    private var peakTime = [Double](repeating: 0, count: SpectrumScale.bandCount)
    private var reference: Float?
    private var lastTime: Double?

    /// `levelsDB` is one pink-compensated dB value per band, or nil when
    /// nothing is being captured (the traces then fall to the floor).
    func advance(levelsDB: [Float]?, now: Double) {
        let dt = Float(min(0.05, max(0, now - (lastTime ?? now))))
        lastTime = now

        if let levelsDB, levelsDB.count == raw.count {
            // Auto-gain: the loudest band sits at the top; the reference
            // drifts down slowly so a quiet passage gradually fills the view.
            let loudest = levelsDB.max() ?? -120
            let ref = max(loudest, (reference ?? loudest) - 1.8 * dt)
            reference = ref
            for i in raw.indices {
                raw[i] = min(1, max(0, (levelsDB[i] - (ref - dynamicRange)) / dynamicRange))
            }
        } else {
            for i in raw.indices { raw[i] = 0 }
        }

        // Fast attack, short release: the live fill follows the music.
        let attack = 1 - exp(-dt / 0.015)
        let release = 1 - exp(-dt / 0.09)
        for i in smoothed.indices {
            smoothed[i] += (raw[i] - smoothed[i]) * (raw[i] > smoothed[i] ? attack : release)
        }
        // Blur sideways for display only, so it doesn't compound frame to frame.
        live = Self.blurred(Self.blurred(smoothed))

        // Peak: jumps up at once, holds, then falls — slowly at first.
        for i in peak.indices {
            if live[i] >= peak[i] {
                peak[i] = live[i]
                peakTime[i] = now
            } else {
                let age = now - peakTime[i] - peakHoldSeconds
                if age > 0 {
                    let speed = 0.12 + 0.3 * Float(min(1, age))
                    peak[i] = max(live[i], peak[i] - dt * speed)
                }
            }
        }
    }

    private static func blurred(_ values: [Float]) -> [Float] {
        values.indices.map { i in
            0.25 * values[max(0, i - 1)] + 0.5 * values[i] + 0.25 * values[min(values.count - 1, i + 1)]
        }
    }

    /// The strongest local maxima of the peak trace, at least
    /// `minSeparation` of the axis apart, loudest first.
    static func peakMarkers(
        in trace: [Float],
        maxCount: Int = 3,
        minSeparation: Double = 0.06,
        threshold: Float = 0.2
    ) -> [(fraction: Double, level: Float)] {
        guard trace.count > 2 else { return [] }
        var candidates: [(fraction: Double, level: Float)] = []
        for i in 1..<(trace.count - 1) where trace[i] > threshold && trace[i] > trace[i - 1] && trace[i] >= trace[i + 1] {
            candidates.append((Double(i) / Double(trace.count - 1), trace[i]))
        }
        var chosen: [(fraction: Double, level: Float)] = []
        for candidate in candidates.sorted(by: { $0.level > $1.level }) {
            guard chosen.allSatisfy({ abs($0.fraction - candidate.fraction) > minSeparation }) else { continue }
            chosen.append(candidate)
            if chosen.count == maxCount { break }
        }
        return chosen
    }

    /// Catmull-Rom sample of a band trace at a fraction across the axis.
    static func sample(_ trace: [Float], at fraction: Double) -> Float {
        let last = trace.count - 1
        let position = min(Double(last), max(0, fraction * Double(last)))
        let i = Int(position)
        let t = Float(position - Double(i))
        let a = trace[max(0, i - 1)], b = trace[i], c = trace[min(last, i + 1)], d = trace[min(last, i + 2)]
        let value = b + 0.5 * t * (c - a + t * (2 * a - 5 * b + 4 * c - d + t * (3 * (b - c) + d - a)))
        return min(1, max(0, value))
    }
}

// MARK: - View

struct SpectrumAnalyzerView: View {
    @ObservedObject private var capture = AudioCaptureManager.shared
    @Default(.realtimeAudioWaveform) private var captureEnabled
    @Default(.analyzerColor) private var colorMode
    @Default(.analyzerShowFrequencyLabels) private var showFrequencyLabels
    @Default(.analyzerShowPeakLabels) private var showPeakLabels
    @Default(.analyzerShowCursor) private var showCursor
    @Default(.analyzerDynamicRange) private var dynamicRange
    @Default(.analyzerPeakHold) private var peakHold
    @State private var state = SpectrumAnalyzerState()
    @State private var cursorX: CGFloat?

    private static let octaveTicks: [Double] = [31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    private static let labelFont = Font.system(size: 8.5, design: .monospaced)
    private static let markerColor = Color(red: 1, green: 0.82, blue: 0.35)
    private static let blueFill = Color(red: 0.35, green: 0.7, blue: 1)
    private static let blueGlow = Color(red: 0.63, green: 0.86, blue: 1)

    /// Read per frame (not observed) so the album-art tint follows the track
    /// without re-rendering the view for every unrelated music update.
    private var fillColor: Color {
        switch colorMode {
        case .blue: Self.blueFill
        case .albumArt: Color(nsColor: MusicManager.shared.avgColor).ensureMinimumBrightness(factor: 0.6)
        case .accent: Color.effectiveAccent
        }
    }

    private var glowColor: Color {
        colorMode == .blue ? Self.blueGlow : fillColor
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                state.dynamicRange = AnalyzerOptions.clampedDynamicRange(Float(dynamicRange))
                state.peakHoldSeconds = AnalyzerOptions.clampedPeakHold(peakHold)
                state.advance(
                    levelsDB: capture.isCapturing ? capture.latestSpectrumSnapshot() : nil,
                    now: timeline.date.timeIntervalSinceReferenceDate
                )
                draw(in: &context, size: size)
            }
        }
        .overlay {
            if !capture.isCapturing {
                Text(captureEnabled
                     ? "Play something to see its spectrum"
                     : "Turn on Real-time audio waveform in Settings › Media")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location): cursorX = showCursor ? location.x : nil
            case .ended: cursorX = nil
            }
        }
        .onAppear { AudioCaptureManager.shared.beginSpectrum() }
        .onDisappear { AudioCaptureManager.shared.endSpectrum() }
        .accessibilityLabel("Spectrum analyzer")
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        // Room for the peak labels above and the octave labels below, which
        // the plot reclaims when they are switched off.
        let top: CGFloat = showPeakLabels ? 13 : 4
        let bottom: CGFloat = showFrequencyLabels ? 12 : 2
        let plot = CGRect(x: 0, y: top, width: size.width, height: max(1, size.height - top - bottom))
        let x = { (fraction: Double) in plot.minX + CGFloat(fraction) * plot.width }
        let y = { (level: Float) in plot.maxY - CGFloat(pow(level, 0.8)) * plot.height }

        // Grid
        for k in 1..<6 {
            let gy = plot.minY + plot.height * CGFloat(k) / 6
            context.stroke(Path { $0.move(to: CGPoint(x: plot.minX, y: gy)); $0.addLine(to: CGPoint(x: plot.maxX, y: gy)) },
                           with: .color(.white.opacity(0.07)), lineWidth: 0.5)
        }
        for hz in Self.octaveTicks {
            let gx = x(SpectrumScale.fraction(ofHz: hz))
            let strong = hz == 1000
            context.stroke(Path { $0.move(to: CGPoint(x: gx, y: plot.minY)); $0.addLine(to: CGPoint(x: gx, y: plot.maxY)) },
                           with: .color(.white.opacity(strong ? 0.14 : 0.06)), lineWidth: 0.5)
            if showFrequencyLabels {
                let text = hz >= 1000 ? "\(Int(hz / 1000))k" : (hz == 31.5 ? "31.5" : "\(Int(hz))")
                context.draw(Text(text).font(Self.labelFont).foregroundColor(.white.opacity(0.45)),
                             at: CGPoint(x: gx, y: size.height), anchor: .bottom)
            }
        }

        // Traces
        let steps = max(24, Int(plot.width / 1.5))
        let livePoints = (0...steps).map { j -> CGPoint in
            let f = Double(j) / Double(steps)
            return CGPoint(x: x(f), y: y(SpectrumAnalyzerState.sample(state.live, at: f)))
        }
        let peakPoints = (0...steps).map { j -> CGPoint in
            let f = Double(j) / Double(steps)
            return CGPoint(x: x(f), y: y(SpectrumAnalyzerState.sample(state.peak, at: f)))
        }

        var fill = Self.smoothPath(through: livePoints)
        fill.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
        fill.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
        fill.closeSubpath()
        let tint = fillColor
        context.fill(fill, with: .linearGradient(
            Gradient(colors: [tint.opacity(0.6), tint.opacity(0.05)]),
            startPoint: CGPoint(x: 0, y: plot.minY), endPoint: CGPoint(x: 0, y: plot.maxY)
        ))

        context.drawLayer { layer in
            layer.addFilter(.shadow(color: glowColor.opacity(0.8), radius: 3))
            layer.stroke(Self.smoothPath(through: peakPoints), with: .color(.white.opacity(0.95)),
                         style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }

        // Pinned peaks
        if showPeakLabels {
            for marker in SpectrumAnalyzerState.peakMarkers(in: state.peak) {
                let point = CGPoint(x: x(marker.fraction), y: y(marker.level))
                context.fill(Path(ellipseIn: CGRect(x: point.x - 2.2, y: point.y - 2.2, width: 4.4, height: 4.4)),
                             with: .color(Self.markerColor))
                let label = SpectrumScale.label(forHz: SpectrumScale.hz(atFraction: marker.fraction))
                drawTag(label, in: &context, size: size, near: CGPoint(x: point.x, y: max(6, point.y - 8)), centered: true)
            }
        }

        // Measuring cursor
        if showCursor, let cursorX {
            let gx = min(plot.maxX, max(plot.minX, cursorX))
            let f = Double((gx - plot.minX) / plot.width)
            context.stroke(Path { $0.move(to: CGPoint(x: gx, y: plot.minY)); $0.addLine(to: CGPoint(x: gx, y: plot.maxY)) },
                           with: .color(Self.markerColor.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            let hz = SpectrumScale.hz(atFraction: f)
            let level = SpectrumAnalyzerState.sample(state.live, at: f)
            let db = Int((-(1 - level) * state.dynamicRange).rounded())
            let readout = "\(SpectrumScale.label(forHz: hz)) · \(db) dB · \(SpectrumScale.noteName(forHz: hz))"
            drawTag(readout, in: &context, size: size, near: CGPoint(x: gx + 6, y: plot.minY + 8), centered: false)
        }
    }

    /// A small dark tag with yellow monospaced text, kept inside the canvas.
    private func drawTag(_ string: String, in context: inout GraphicsContext, size: CGSize, near point: CGPoint, centered: Bool) {
        let text = context.resolve(Text(string).font(Self.labelFont).foregroundColor(Self.markerColor))
        let textSize = text.measure(in: size)
        let width = textSize.width + 6
        let height = textSize.height + 1
        var originX = centered ? point.x - width / 2 : point.x
        if !centered && originX + width > size.width { originX = point.x - 12 - width }
        originX = min(size.width - width, max(0, originX))
        let rect = CGRect(x: originX, y: point.y - height / 2, width: width, height: height)
        context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(.black.opacity(0.75)))
        context.draw(text, at: CGPoint(x: rect.midX, y: rect.midY))
    }

    /// Catmull-Rom spline through the points, as cubic Béziers.
    private static func smoothPath(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for i in 0..<(points.count - 1) {
            let p0 = points[max(0, i - 1)], p1 = points[i], p2 = points[i + 1], p3 = points[min(points.count - 1, i + 2)]
            path.addCurve(
                to: p2,
                control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            )
        }
        return path
    }
}
