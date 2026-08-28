/*
 Brev - Mail Client for macOS and iOS
 Copyright (c) 2026 Brev contributors

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the conditions in the LICENSE file.
 */

import BrevBackend
import BrevDesign
import BrevThemes
import SwiftUI
import UserNotifications

struct NotificationSection: View {
    @Environment(\.brevTheme) private var theme
    @State private var settings: NotificationSettings
    @State private var authorizationStatus: BrevSettingsNotificationAuthStatus = .notDetermined
    @State private var isRequestingAuthorization = false
    @State private var lastTestResult: String?

    private let settingsStore: SettingsPersistenceStore
    private let accounts: [BrevAccount]

    init(
        settingsStore: SettingsPersistenceStore = .standard,
        accounts: [BrevAccount] = []
    ) {
        self.settingsStore = settingsStore
        self.accounts = accounts
        _settings = State(initialValue: settingsStore.notificationSettings())
    }

    var body: some View {
        SectionScaffold(
            title: String(localized: "Notifications", bundle: .module),
            subtitle: String(localized: "Choose what deserves an interruption.", bundle: .module)
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.xl) {
                notificationGroup
                accountScopeGroup
                quietHoursGroup
            }
        }
        .task { await refreshAuthorizationStatus() }
    }

    private var notificationGroup: some View {
        SettingsGroup(
            title: String(localized: "Notifications", bundle: .module),
            subtitle: String(localized: "Control how new messages alert you.", bundle: .module),
            symbolName: "bell"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                SettingsToggleRow(
                    symbolName: "bell.badge",
                    title: String(localized: "Enable notifications", bundle: .module),
                    subtitle: String(localized: "Receive alerts when new messages arrive.", bundle: .module),
                    isOn: notificationsEnabledBinding
                )

                authorizationRow

                SettingsToggleRow(
                    symbolName: "circlebadge.fill",
                    title: String(localized: "Show dock badge", bundle: .module),
                    subtitle: String(localized: "Show unread count on the app icon.", bundle: .module),
                    isOn: binding(for: \.badgeEnabled)
                )

                SettingsPickerRow(
                    symbolName: "circlebadge.fill",
                    title: String(localized: "App badge", bundle: .module),
                    subtitle: settings.badgePolicy.subtitle,
                    selection: binding(for: \.badgePolicy)
                ) {
                    ForEach(NotificationBadgePolicy.allCases, id: \.self) { policy in
                        Text(policy.title).tag(policy)
                    }
                }

                SettingsToggleRow(
                    symbolName: "speaker.wave.2",
                    title: String(localized: "Notification sound", bundle: .module),
                    subtitle: String(localized: "Play a sound for incoming messages.", bundle: .module),
                    isOn: binding(for: \.soundEnabled),
                    isEnabled: settings.notificationsEnabled
                )

                SettingsToggleRow(
                    symbolName: "text.bubble",
                    title: String(localized: "Show message previews", bundle: .module),
                    subtitle: String(localized: "Display sender and subject in notifications.", bundle: .module),
                    isOn: binding(for: \.showPreviews),
                    isEnabled: settings.notificationsEnabled
                )

                testNotificationButton

                SettingsInfoCallout(
                    symbolName: "bell",
                    message: NotificationDeliveryExpectation.settingsCalloutMessage,
                    tone: .info
                )
            }
        }
    }

    private var accountScopeGroup: some View {
        SettingsGroup(
            title: String(localized: "Accounts", bundle: .module),
            subtitle: String(localized: "Choose which accounts can produce notifications, badges, and sounds.", bundle: .module),
            symbolName: "person.2.badge.gearshape"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                if accounts.isEmpty {
                    SettingsInfoCallout(
                        symbolName: "person.crop.circle.badge.questionmark",
                        message: String(
                            localized: "Connect an account to customize notification scope per mailbox.",
                            bundle: .module
                        ),
                        tone: .info
                    )
                } else {
                    ForEach(accounts) { account in
                        accountOverrideCard(account)
                    }
                }
            }
        }
    }

    private func accountOverrideCard(_ account: BrevAccount) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .brevFont(.body)
                    .foregroundStyle(theme.textPrimary.color)
                Text(account.emailAddress)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
            }

            SettingsToggleRow(
                symbolName: "bell",
                title: String(localized: "Notifications", bundle: .module),
                subtitle: String(localized: "Allow alerts from this account.", bundle: .module),
                isOn: accountOverrideBinding(
                    account.id,
                    keyPath: \.notificationsEnabled
                )
            )

            SettingsToggleRow(
                symbolName: "circlebadge",
                title: String(localized: "Badge", bundle: .module),
                subtitle: String(
                    localized: "Include this account in badge counts when selected accounts are used.",
                    bundle: .module
                ),
                isOn: accountOverrideBinding(
                    account.id,
                    keyPath: \.badgeEnabled
                )
            )

            SettingsToggleRow(
                symbolName: "speaker.wave.2",
                title: String(localized: "Sound", bundle: .module),
                subtitle: String(localized: "Allow notification sounds from this account.", bundle: .module),
                isOn: accountOverrideBinding(
                    account.id,
                    keyPath: \.soundEnabled
                )
            )
        }
        .padding(BrevSpacing.md)
        .background(theme.bgSecondary.color.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: BrevRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: BrevRadius.md)
                .stroke(theme.border.color.opacity(0.45), lineWidth: 1)
        }
    }

    private var quietHoursGroup: some View {
        SettingsGroup(
            title: String(localized: "Quiet hours", bundle: .module),
            subtitle: String(localized: "Silence notifications during specific hours.", bundle: .module),
            symbolName: "moon.zzz"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                SettingsToggleRow(
                    symbolName: "moon.zzz.fill",
                    title: String(localized: "Enable quiet hours", bundle: .module),
                    subtitle: String(localized: "Suppress notifications during configured hours.", bundle: .module),
                    isOn: binding(for: \.quietHoursEnabled)
                )

                if settings.quietHoursEnabled {
                    // `NewMailNotificationPolicy` has always read these two
                    // hours; until now the pane only narrated them, so the
                    // 10 PM - 7 AM default was the only window anyone could
                    // ever have.
                    SettingsPickerRow(
                        symbolName: "moon.stars",
                        title: String(localized: "Starts at", bundle: .module),
                        subtitle: String(localized: "Notifications go quiet from this hour.", bundle: .module),
                        selection: binding(for: \.quietHoursStart),
                        selectionTitle: settings.quietHoursStartLabel
                    ) {
                        hourOptions
                    }

                    SettingsPickerRow(
                        symbolName: "sunrise",
                        title: String(localized: "Ends at", bundle: .module),
                        subtitle: String(localized: "Notifications resume from this hour.", bundle: .module),
                        selection: binding(for: \.quietHoursEnd),
                        selectionTitle: settings.quietHoursEndLabel
                    ) {
                        hourOptions
                    }

                    SettingsInfoCallout(
                        symbolName: "clock",
                        message: NotificationDeliveryExpectation.quietHoursCalloutMessage,
                        tone: .info
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var hourOptions: some View {
        ForEach(0 ..< 24, id: \.self) { hour in
            Text(NotificationSettings.hourLabel(hour)).tag(hour)
        }
    }

    private var authorizationRow: some View {
        HStack(alignment: .center, spacing: BrevSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Authorization", bundle: .module)
                    .brevFont(.body)
                    .foregroundStyle(theme.textPrimary.color)
                Text(authorizationStatus.displaySubtitle)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
            }
            Spacer(minLength: BrevSpacing.sm)
            statusPill
            if authorizationStatus == .notDetermined {
                Button {
                    Task { await requestAuthorization() }
                } label: {
                    Text(isRequestingAuthorization ? String(localized: "Requesting…", bundle: .module) : String(
                        localized: "Request Access",
                        bundle: .module
                    ))
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRequestingAuthorization)
            }
        }
        .padding(BrevSpacing.md)
        .background(theme.bgSecondary.color.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: BrevRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: BrevRadius.md)
                .stroke(theme.border.color.opacity(0.45), lineWidth: 1)
        }
    }

    private var statusPill: some View {
        Text(authorizationStatus.displayTitle)
            .brevFont(.caption)
            .padding(.horizontal, BrevSpacing.sm)
            .padding(.vertical, 2)
            .background(statusPillBackground)
            .foregroundStyle(theme.textPrimary.color)
            .clipShape(Capsule())
    }

    private var statusPillBackground: AnyShapeStyle {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return AnyShapeStyle(theme.accent.color.opacity(0.25))
        case .denied:
            return AnyShapeStyle(theme.danger.color.opacity(0.25))
        case .notDetermined:
            return AnyShapeStyle(theme.textSecondary.color.opacity(0.25))
        }
    }

    private var testNotificationButton: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            Button {
                Task { await fireTestNotification() }
            } label: {
                Label(String(localized: "Test notification", bundle: .module), systemImage: "paperplane")
            }
            .buttonStyle(.bordered)
            .disabled(!canFireTestNotification)
            if let lastTestResult {
                Text(lastTestResult)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
            }
        }
    }

    private var canFireTestNotification: Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        }
    }

    private func requestAuthorization() async {
        guard !isRequestingAuthorization else { return }
        isRequestingAuthorization = true
        defer { isRequestingAuthorization = false }
        let options: UNAuthorizationOptions = [.alert, .badge, .sound, .providesAppNotificationSettings]
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: options)
        } catch {
            // Permission is user-owned; status below reflects the result.
        }
        await refreshAuthorizationStatus()
    }

    private func refreshAuthorizationStatus() async {
        let systemSettings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = BrevSettingsNotificationAuthStatus.map(systemSettings.authorizationStatus)
    }

    private func fireTestNotification() async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Brev test notification", bundle: .module)
        content.body = String(localized: "If you can read this, notifications are working.", bundle: .module)
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "brev.test.\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
            lastTestResult = String(localized: "Delivered at \(Self.timestamp())", bundle: .module)
        } catch {
            lastTestResult = String(localized: "Failed: \(error.localizedDescription)", bundle: .module)
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: Date())
    }

    private func accountOverrideBinding(
        _ accountID: String,
        keyPath: WritableKeyPath<NotificationSettings.AccountOverride, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: {
                settings.accountOverride(for: accountID)[keyPath: keyPath]
            },
            set: { newValue in
                var override = settings.accountOverride(for: accountID)
                override[keyPath: keyPath] = newValue
                settings.setAccountOverride(
                    accountID: accountID,
                    notificationsEnabled: override.notificationsEnabled,
                    badgeEnabled: override.badgeEnabled,
                    soundEnabled: override.soundEnabled
                )
                settingsStore.save(settings)
            }
        )
    }

    private func binding<Value>(
        for keyPath: WritableKeyPath<NotificationSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { newValue in
                settings[keyPath: keyPath] = newValue
                settingsStore.save(settings)
            }
        )
    }

    private var notificationsEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.notificationsEnabled },
            set: { newValue in
                settings.notificationsEnabled = newValue
                settingsStore.save(settings)
                NotificationCenter.default.post(name: .brevNotificationSettingsDidChange, object: nil)
                guard newValue else { return }
                Task {
                    await requestAuthorization()
                    NotificationCenter.default.post(name: .brevNotificationSettingsDidChange, object: nil)
                }
            }
        )
    }
}

/// Mirrors the subset of `UNAuthorizationStatus` the settings UI surfaces.
/// Kept local to `BrevSettings` so the package doesn't import the
/// `BrevMail` notification surface (which would create a circular
/// dependency — `BrevMail` already depends on `BrevSettings`).
public enum BrevSettingsNotificationAuthStatus: String, Sendable, CaseIterable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral

    public var displayTitle: String {
        switch self {
        case .notDetermined: return String(localized: "Not requested", bundle: .module)
        case .denied: return String(localized: "Denied", bundle: .module)
        case .authorized: return String(localized: "Authorized", bundle: .module)
        case .provisional: return String(localized: "Quiet delivery", bundle: .module)
        case .ephemeral: return String(localized: "App-clip only", bundle: .module)
        }
    }

    public var displaySubtitle: String {
        switch self {
        case .notDetermined:
            return String(localized: "Brev hasn't asked for permission yet.", bundle: .module)
        case .denied:
            return String(localized: "Open System Settings to allow notifications from Brev.", bundle: .module)
        case .authorized:
            return String(localized: "Alerts, sounds, and badges are enabled.", bundle: .module)
        case .provisional:
            return String(localized: "Notifications deliver quietly to Notification Center.", bundle: .module)
        case .ephemeral:
            return String(localized: "Allowed only while an app clip is active.", bundle: .module)
        }
    }

    static func map(_ status: UNAuthorizationStatus) -> BrevSettingsNotificationAuthStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        #if os(iOS)
        case .ephemeral: return .ephemeral
        #endif
        @unknown default: return .notDetermined
        }
    }
}
