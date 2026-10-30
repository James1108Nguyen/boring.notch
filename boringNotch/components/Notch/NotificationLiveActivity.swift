//
//  NotificationLiveActivity.swift
//  boringNotch
//

import Defaults
import SwiftUI

private struct NotificationSourceIcon: View {
    let bundleID: String?
    let size: CGFloat

    var body: some View {
        if let bundleID {
            appIcon(for: bundleID)
                .resizable().scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
        } else {
            Image(systemName: "bell")
                .font(.system(size: size * 0.55))
                .frame(width: size, height: size)
        }
    }
}

struct NotificationLiveActivity: View {
    @EnvironmentObject private var vm: BoringViewModel
    let notification: SystemNotification

    @State private var ringScale: CGFloat = 1
    @State private var ringOpacity = 0.0

    private var itemSize: CGFloat {
        max(0, vm.effectiveClosedNotchHeight - 12)
    }

    var body: some View {
        HStack {
            NotificationSourceIcon(bundleID: notification.bundleID, size: itemSize)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)

            ZStack {
                Circle()
                    .stroke(Color.effectiveAccent, lineWidth: 1.5)
                    .scaleEffect(ringScale)
                    .opacity(ringOpacity)
                Circle()
                    .fill(Color.effectiveAccent)
                    .frame(width: 7, height: 7)
            }
            .frame(width: itemSize, height: itemSize)
        }
        .frame(height: vm.effectiveClosedNotchHeight)
        .onAppear { pulse() }
        .onChange(of: notification.id) { _, _ in pulse() }
    }

    private func pulse() {
        ringScale = 1
        ringOpacity = 0.8
        withAnimation(.easeOut(duration: 0.6)) {
            ringScale = 1.8
            ringOpacity = 0
        }
    }
}

struct NotificationExpandedView: View {
    @ObservedObject private var manager = SystemNotificationManager.shared
    let notification: SystemNotification

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: openSourceApp) {
                HStack(alignment: .center, spacing: 12) {
                    NotificationSourceIcon(bundleID: notification.bundleID, size: 46)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(notification.appName ?? "Notification")
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)

                            Text(notification.receivedAt, style: .relative)
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .fixedSize()
                        }

                        if let title = notification.title, title != notification.appName {
                            Text(title)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                        }

                        if let subtitle = notification.subtitle {
                            Text(subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        if let body = notification.body {
                            Text(body)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary.opacity(0.9))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: 300, alignment: .leading)
                }
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(notification.appName ?? "App") notification")
            .accessibilityHint("Opens \(notification.appName ?? "the app")")

            HStack(spacing: 4) {
                if !manager.queuedNotifications.isEmpty {
                    Button {
                        manager.showNextQueued()
                    } label: {
                        Text("+\(manager.queuedNotifications.count)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show next queued notification")
                }

                Button {
                    manager.dismissActive(token: notification.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss notification")
            }
            .padding(.trailing, 4)
        }
        .modifier(NotificationPresenceTracking(manager: manager))
    }

    private func openSourceApp() {
        manager.openAndDismiss(notification)
    }
}

/// Shared by both notification styles: an open notch showing a notification
/// counts as the user being present, unless it opened on its own.
private struct NotificationPresenceTracking: ViewModifier {
    let manager: SystemNotificationManager

    func body(content: Content) -> some View {
        content
            .onAppear {
                // A notch that opened on its own keeps counting down; hovering
                // it still pauses the countdown via the hover handler.
                if !manager.isAutoPresenting {
                    manager.holdActive()
                }
            }
            .onDisappear {
                // While auto-presenting, a newer notification replaces this view;
                // resuming here would cut the newcomer's countdown short.
                if !manager.isAutoPresenting {
                    manager.resumeDismiss()
                }
            }
    }
}

private extension SystemNotificationManager {
    func openAndDismiss(_ notification: SystemNotification) {
        Task {
            guard await open(notification) else { return }
            dismissActive(token: notification.id)
        }
    }
}

/// Compact notification style: sender on the first line, the message on a
/// single second line. Roughly half the height of NotificationExpandedView.
struct NotificationCompactView: View {
    @ObservedObject private var manager = SystemNotificationManager.shared
    @Default(.notificationScrollLongMessages) private var scrollLongMessages
    let notification: SystemNotification

    @State private var isHovering = false

    /// Title is usually the sender; fall back to the app name when there is
    /// no title (or it just repeats the app name).
    private var heading: String {
        if let title = notification.title, title != notification.appName {
            return title
        }
        return notification.appName ?? "Notification"
    }

    private var showsAppName: Bool {
        notification.appName != nil && heading != notification.appName
    }

    private var message: String? {
        let parts = [notification.subtitle, notification.body].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                manager.openAndDismiss(notification)
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    NotificationSourceIcon(bundleID: notification.bundleID, size: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(heading)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)

                            if showsAppName, let appName = notification.appName {
                                Text(appName)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 4)

                            TimelineView(.everyMinute) { _ in
                                Text(notification.receivedAt, format: .relative(presentation: .named, unitsStyle: .narrow))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.tertiary)
                                    .fixedSize()
                            }
                            .opacity(isHovering ? 0 : 1)
                        }

                        if let message {
                            NotificationTickerText(
                                text: message,
                                scrolls: scrollLongMessages,
                                isPaused: isHovering
                            )
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(notification.appName ?? "App") notification")
            .accessibilityHint("Opens \(notification.appName ?? "the app")")

            if isHovering {
                HStack(spacing: 4) {
                    if !manager.queuedNotifications.isEmpty {
                        Button {
                            manager.showNextQueued()
                        } label: {
                            Text("+\(manager.queuedNotifications.count)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.white.opacity(0.14), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Show next queued notification")
                    }

                    Button {
                        manager.dismissActive(token: notification.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: 16)
                            .background(.white.opacity(0.1), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss notification")
                }
                .padding(.trailing, 4)
                .transition(.opacity)
            }
        }
        .frame(width: compactOpenContentWidth)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
        .modifier(NotificationPresenceTracking(manager: manager))
    }
}

/// One line of text. When it doesn't fit and `scrolls` is on, it holds at the
/// start, slides to the end, holds again and starts over; otherwise it is
/// truncated with an ellipsis. Driven by a small loop rather than a SwiftUI
/// animation so it can freeze in place while `isPaused`.
private struct NotificationTickerText: View {
    let text: String
    let scrolls: Bool
    let isPaused: Bool

    @State private var boxWidth: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var phase: Double = 0
    @State private var offset: CGFloat = 0

    private static let hold: Double = 1.5
    private static let pointsPerSecond: Double = 30

    private var overflow: CGFloat {
        scrolls ? max(0, textWidth - boxWidth) : 0
    }

    private struct LoopKey: Equatable {
        let overflow: CGFloat
        let isPaused: Bool
    }

    var body: some View {
        if !scrolls {
            Text(text).lineLimit(1).truncationMode(.tail)
        } else {
            // The hidden copy sets the line height and takes the available
            // width; the visible copy is unconstrained and slides inside it.
            Text(text)
                .lineLimit(1)
                .hidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { boxWidth = $0 }
                .overlay(alignment: .leading) {
                    Text(text)
                        .lineLimit(1)
                        .fixedSize()
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { textWidth = $0 }
                        .offset(x: -offset)
                }
                .clipped()
                .mask(fadeMask)
                .task(id: LoopKey(overflow: overflow, isPaused: isPaused)) {
                    await runLoop()
                }
        }
    }

    /// Soft edges only while there is something hidden to scroll to.
    private var fadeMask: some View {
        LinearGradient(
            stops: overflow > 0
                ? [.init(color: offset > 0 ? .clear : .black, location: 0),
                   .init(color: .black, location: 0.03),
                   .init(color: .black, location: 0.95),
                   .init(color: offset < overflow ? .clear : .black, location: 1)]
                : [.init(color: .black, location: 0), .init(color: .black, location: 1)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func runLoop() async {
        guard overflow > 0 else {
            offset = 0
            return
        }
        guard !isPaused else { return }

        let clock = ContinuousClock()
        var last = clock.now
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
            let now = clock.now
            let delta = now - last
            last = now
            phase += Double(delta.components.seconds) + Double(delta.components.attoseconds) / 1e18
            offset = position(at: phase)
        }
    }

    private func position(at phase: Double) -> CGFloat {
        let scroll = Double(overflow) / Self.pointsPerSecond
        let cycle = Self.hold + scroll + Self.hold
        let t = phase.truncatingRemainder(dividingBy: cycle)
        if t < Self.hold { return 0 }
        if t < Self.hold + scroll { return CGFloat((t - Self.hold) * Self.pointsPerSecond) }
        return overflow
    }
}
