//
//  NotificationSettingsView.swift
//  boringNotch
//
import AppKit
import Defaults
import SwiftUI

private struct NotificationApp: Identifiable {
    let bundleID: String
    let name: String

    var id: String { bundleID }
}

struct NotificationSettingsView: View {
    @Default(.notificationLiveActivity) private var notificationLiveActivity
    @Default(.notificationsFromAllApps) private var notificationsFromAllApps
    @Default(.notificationAllowedApps) private var allowedApps
    @Default(.notificationDisplayDuration) private var displayDuration
    @Default(.notificationStyle) private var notificationStyle
    @State private var isAccessibilityAuthorized = true

    /// Seconds; 0 keeps the notification until it is dismissed.
    private static let displayDurations: [Double] = [2, 3, 5, 8, 10, 15, 30, 0]

    private var selectedApps: [NotificationApp] {
        allowedApps
            .map { NotificationApp(bundleID: $0, name: displayName(for: $0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func sendTest(title: String?, subtitle: String? = nil, body: String) {
        SystemNotificationManager.shared.sendTestNotification(title: title, subtitle: subtitle, body: body)
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .notificationLiveActivity) {
                    Text("Show notifications in the notch")
                }
            } footer: {
                Text("Requires \(AccessibilityPermission.displayName). Only visible banners are mirrored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !isAccessibilityAuthorized {
                Section {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: AccessibilityPermission.systemImageName)
                            .font(.title)
                            .foregroundStyle(Color.effectiveAccent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(AccessibilityPermission.displayName) Required")
                                .font(.headline)
                            Text("Grant \(AccessibilityPermission.displayName) to mirror notification banners.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Grant Access") {
                            Task {
                                let granted = await MediaKeyInterceptor.shared.ensureAccessibilityAuthorization(promptIfNeeded: true)
                                isAccessibilityAuthorized = granted
                            }
                        }
                    }
                }
            }

            Section {
                Defaults.Toggle(key: .notificationAutoExpand) {
                    Text("Expand notch on new notification")
                }

                Picker(selection: $notificationStyle) {
                    ForEach(NotificationStyle.allCases) { style in
                        Text(style.localizedString).tag(style)
                    }
                } label: {
                    Text("Style")
                }
                .pickerStyle(.segmented)

                Defaults.Toggle(key: .notificationScrollLongMessages) {
                    Text("Scroll long messages")
                }
                .disabled(notificationStyle != .compact)

                Picker(selection: $displayDuration) {
                    ForEach(Self.displayDurations, id: \.self) { seconds in
                        if seconds == 0 {
                            Text("Until dismissed").tag(seconds)
                        } else {
                            Text("\(Int(seconds)) seconds").tag(seconds)
                        }
                    }
                } label: {
                    Text("Display duration")
                }
            } header: {
                Text("Display")
            } footer: {
                Text("Hovering over a notification pauses the countdown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!notificationLiveActivity)

            Section {
                Menu("Send test notification") {
                    Button("Short message") {
                        sendTest(title: "Minh Anh", body: "Ok bro 👍")
                    }
                    Button("Long message") {
                        sendTest(title: "Minh Anh", body: "Tối nay đi ăn lẩu không bro? 7h ở chỗ cũ nha, nhớ mang theo cái sạc giùm mình, mình quên ở nhà rồi")
                    }
                    Button("With subtitle") {
                        sendTest(title: "Minh Anh", subtitle: "Nhóm Lẩu Thứ 6", body: "Ai đi thì thả tim nha, mình đặt bàn cho đủ người")
                    }
                    Button("No title") {
                        sendTest(title: nil, body: "A notification without a title shows the app name instead")
                    }
                    Divider()
                    Button("Three in a row") {
                        Task { @MainActor in
                            sendTest(title: "Minh Anh", body: "Tin 1: alo")
                            try? await Task.sleep(for: .seconds(1))
                            sendTest(title: "Hoàng", body: "Tin 2: tới chưa bro, mọi người tới đủ rồi nè")
                            try? await Task.sleep(for: .seconds(1))
                            sendTest(title: "Lan", body: "Tin 3: mình tới trễ 15 phút nhé")
                        }
                    }
                }
                .fixedSize()
            } header: {
                Text("Test")
            } footer: {
                Text("Shows a sample notification in the notch without going through Notification Center.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!notificationLiveActivity)

            Section {
                Defaults.Toggle(key: .notificationsFromAllApps) {
                    Text("From all apps")
                }
                .disabled(!notificationLiveActivity)

                if !notificationsFromAllApps {
                    if selectedApps.isEmpty {
                        Text("No apps selected")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(selectedApps) { app in
                            HStack {
                                appIcon(for: app.bundleID)
                                    .resizable().scaledToFit()
                                    .frame(width: 20, height: 20)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))

                                Text(app.name)
                                Spacer()
                                Button("Remove", role: .destructive) {
                                    allowedApps.remove(app.bundleID)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }

                    Button {
                        chooseApplication()
                    } label: {
                        Label("Add Application…", systemImage: "plus")
                    }
                }
            } header: {
                Text("Apps")
            } footer: {
                if !notificationsFromAllApps {
                    Text("Only selected apps are mirrored. Add applications from your Mac; no preset app list is used.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!notificationLiveActivity)
        }
        .formStyle(.grouped)
        .navigationTitle("Notifications")
        .task {
            isAccessibilityAuthorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
        }
        .onReceive(NotificationCenter.default.publisher(for: .accessibilityAuthorizationChanged)) { notification in
            if let granted = notification.userInfo?["granted"] as? Bool {
                isAccessibilityAuthorized = granted
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task {
                isAccessibilityAuthorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
            }
        }
        .onChange(of: allowedApps) { _, _ in
            SystemNotificationManager.shared.updateFilter()
        }
        .onChange(of: notificationsFromAllApps) { _, _ in
            SystemNotificationManager.shared.updateFilter()
        }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["app"]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { response in
            guard response == .OK else { return }
            let bundleIDs = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
            guard !bundleIDs.isEmpty else { return }
            DispatchQueue.main.async {
                allowedApps.formUnion(bundleIDs)
            }
        }
    }

    private func displayName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let name = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        else {
            return bundleID
        }
        return name
    }
}
