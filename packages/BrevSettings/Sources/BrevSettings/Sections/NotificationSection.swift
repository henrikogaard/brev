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
#if os(macOS)
import ServiceManagement
#endif
import SwiftUI
import UserNotifications
#if os(iOS)
import UIKit
#endif

struct NotificationSection: View {
    @Environment(\.brevTheme) private var theme
    @State private var settings: NotificationSettings
    @State private var authorizationStatus: BrevSettingsNotificationAuthStatus = .notDetermined
    @State private var isRequestingAuthorization = false
    @State private var lastTestResult: String?
    #if os(macOS)
    @State private var launchAtLoginController = LaunchAtLoginController()
    @State private var launchAtLoginStatus: SMAppService.Status = .notRegistered
    #endif

    private let settingsStore: SettingsPersistenceStore
    private let accounts: [BrevAccount]
    private let authorizationStatusProvider: () async -> BrevSettingsNotificationAuthStatus

    /// - Parameter authorizationStatus: Reads the system permission; tests inject a fixed status
    ///   because the notification center is unavailable in a test host.
    init(
        settingsStore: SettingsPersistenceStore = .standard,
        accounts: [BrevAccount] = [],
        authorizationStatus: @escaping () async -> BrevSettingsNotificationAuthStatus = {
            let systemSettings = await UNUserNotificationCenter.current().notificationSettings()
            return BrevSettingsNotificationAuthStatus.map(systemSettings.authorizationStatus)
        }
    ) {
        self.settingsStore = settingsStore
        self.accounts = accounts
        authorizationStatusProvider = authorizationStatus
        _settings = State(initialValue: settingsStore.notificationSettings())
    }

    var body: some View {
        SectionScaffold(
            title: String(localized: "Notifications", bundle: .module),
            subtitle: String(localized: "Choose what deserves an interruption.", bundle: .module)
        ) {
            SettingsGroupStack {
                notificationGroup
                #if os(macOS)
                backgroundMailGroup
                #endif
                accountScopeGroup
                quietHoursGroup
            }
        }
        .task { await refreshAuthorizationStatus() }
        #if os(macOS)
            .task { launchAtLoginStatus = launchAtLoginController.status }
        #endif
    }

    /// ADR-0075: explicit opt-in for keeping the fetch loop and menu-bar
    /// status alive with no window open, plus the launch-at-login sub-toggle.
    #if os(macOS)
    private var backgroundMailGroup: some View {
        SettingsGroup(
            title: String(localized: "Background mail", bundle: .module),
            subtitle: String(localized: "Run checks while no window is open.", bundle: .module),
            symbolName: "envelope.badge"
        ) {
            SettingsRowStack(spacing: BrevSpacing.md) {
                SettingsToggleRow(
                    symbolName: "envelope.badge",
                    title: String(localized: "Keep checking mail in the background", bundle: .module),
                    subtitle: String(
                        localized: "Brev keeps running and checking mail with no window open, and shows its status in the menu bar.",
                        bundle: .module
                    ),
                    isOn: backgroundMailBinding
                )

                if settings.backgroundMailEnabled,
                   LaunchAtLoginAvailability.isAvailable(
                       bundleIdentifier: Bundle.main.bundleIdentifier
                   ) {
                    SettingsToggleRow(
                        symbolName: "power",
                        title: String(localized: "Open Brev at login", bundle: .module),
                        subtitle: launchAtLoginSubtitle,
                        isOn: Binding(
                            get: { launchAtLoginStatus == .enabled },
                            set: { newValue in
                                try? launchAtLoginController.setEnabled(newValue)
                                settings.launchAtLoginRequested = newValue
                                settingsStore.save(settings)
                                launchAtLoginStatus = launchAtLoginController.status
                            }
                        ),
                        isEnabled: launchAtLoginStatus != .requiresApproval
                    )
                    if launchAtLoginStatus == .requiresApproval {
                        SettingsButton(
                            String(localized: "Open Login Items Settings…", bundle: .module),
                            style: .secondary
                        ) {
                            launchAtLoginController.openSystemSettings()
                        }
                    }
                }

                if settings.backgroundMailEnabled,
                   FetchScheduleSettings.load().interval == .manual {
                    SettingsInfoCallout(
                        symbolName: "hand.raised",
                        message: String(
                            localized: "Your fetch schedule is set to Manually, so background checking only listens for server pushes.",
                            bundle: .module
                        ),
                        tone: .info
                    )
                }
            }
        }
    }

    private var launchAtLoginSubtitle: String {
        switch launchAtLoginStatus {
        case .requiresApproval:
            return String(
                localized: "macOS needs your approval in System Settings first.",
                bundle: .module
            )
        default:
            return String(
                localized: "Start Brev automatically when you sign in to this Mac.",
                bundle: .module
            )
        }
    }
    #endif

    private var notificationGroup: some View {
        SettingsGroup(
            title: String(localized: "Notifications", bundle: .module),
            subtitle: notificationGroupFooter,
            symbolName: "bell"
        ) {
            SettingsRowStack {
                SettingsToggleRow(
                    symbolName: "bell.badge",
                    title: String(localized: "Enable notifications", bundle: .module),
                    subtitle: String(localized: "Receive alerts when new messages arrive.", bundle: .module),
                    isOn: notificationsEnabledBinding
                )

                authorizationRow

                SettingsToggleRow(
                    symbolName: "app.badge",
                    title: NotificationPanePresentation.badgeToggleTitle(platform: .current),
                    subtitle: String(localized: "Show unread count on the app icon.", bundle: .module),
                    isOn: binding(for: \.badgeEnabled)
                )

                SettingsPickerRow(
                    symbolName: "number.square",
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
                    isEnabled: NotificationPanePresentation
                        .dependentRowsEnabled(notificationsEnabled: settings.notificationsEnabled)
                )

                SettingsToggleRow(
                    symbolName: "text.bubble",
                    title: String(localized: "Show message previews", bundle: .module),
                    subtitle: String(localized: "Display sender and subject in notifications.", bundle: .module),
                    isOn: showPreviewsBinding,
                    isEnabled: NotificationPanePresentation
                        .dependentRowsEnabled(notificationsEnabled: settings.notificationsEnabled)
                )

                testNotificationButton

                #if os(macOS)
                SettingsInfoCallout(
                    symbolName: "bell",
                    message: NotificationDeliveryExpectation.settingsCalloutMessage,
                    tone: .info
                )
                #endif
            }
        }
    }

    private var notificationGroupFooter: String {
        #if os(iOS)
        NotificationPanePresentation.deliveryFooter(platform: .iOS)
        #else
        String(localized: "Control how new messages alert you.", bundle: .module)
        #endif
    }

    private var accountScopeGroup: some View {
        SettingsGroup(
            title: String(localized: "Accounts", bundle: .module),
            subtitle: String(localized: "Choose which accounts can produce notifications, badges, and sounds.", bundle: .module),
            symbolName: "person.2.badge.gearshape"
        ) {
            SettingsRowStack {
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
                        #if os(iOS)
                        NavigationLink {
                            accountOverrideForm(account)
                        } label: {
                            accountOverrideLabel(account)
                        }
                        #else
                        accountOverrideCard(account)
                        #endif
                    }
                }
            }
        }
    }

    #if os(iOS)
    private func accountOverrideLabel(_ account: BrevAccount) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
            Text(account.displayName.isEmpty ? account.emailAddress : account.displayName)
                .brevFont(.body)
                .foregroundStyle(theme.textPrimary.color)
            Text(account.emailAddress)
                .brevFont(.footnote)
                .foregroundStyle(theme.textSecondary.color)
        }
        .accessibilityElement(children: .combine)
    }

    /// Per-account switches live one level down, as in iOS Settings, instead
    /// of three toggles nested in a card for every account.
    private func accountOverrideForm(_ account: BrevAccount) -> some View {
        Form {
            Section {
                accountOverrideToggles(account)
            } footer: {
                Text("Choose which alerts this account can produce.", bundle: .module)
                    .brevFont(.footnote)
                    .foregroundStyle(theme.textSecondary.color)
            }
            .listRowBackground(theme.bgPrimary.color)
        }
        .settingsFormChrome()
        .navigationTitle(account.displayName.isEmpty ? account.emailAddress : account.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
    #endif

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

            accountOverrideToggles(account)
        }
        .padding(BrevSpacing.md)
        .settingsInlineSurface()
    }

    @ViewBuilder
    private func accountOverrideToggles(_ account: BrevAccount) -> some View {
        Group {
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
                symbolName: "app.badge",
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
    }

    private var quietHoursGroup: some View {
        SettingsGroup(
            title: String(localized: "Quiet hours", bundle: .module),
            subtitle: quietHoursFooter,
            symbolName: "moon.zzz"
        ) {
            SettingsRowStack {
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

                    #if os(macOS)
                    SettingsInfoCallout(
                        symbolName: "clock",
                        message: NotificationDeliveryExpectation.quietHoursCalloutMessage,
                        tone: .info
                    )
                    #endif
                }
            }
        }
    }

    private var quietHoursFooter: String {
        #if os(iOS)
        NotificationDeliveryExpectation.quietHoursCalloutMessage
        #else
        String(localized: "Silence notifications during specific hours.", bundle: .module)
        #endif
    }

    @ViewBuilder
    private var hourOptions: some View {
        ForEach(0 ..< 24, id: \.self) { hour in
            Text(NotificationSettings.hourLabel(hour)).tag(hour)
        }
    }

    @ViewBuilder
    private var authorizationRow: some View {
        #if os(iOS)
        iOSAuthorizationRows
        #else
        macAuthorizationRow
        #endif
    }

    #if os(iOS)
    /// The permission state as a plain value row, followed by the one action
    /// it allows: ask, or jump to the app's page in the Settings app.
    @ViewBuilder
    private var iOSAuthorizationRows: some View {
        LabeledContent {
            Text(authorizationStatus.displayTitle)
                .foregroundStyle(theme.textSecondary.color)
        } label: {
            Text("Permission", bundle: .module)
                .foregroundStyle(theme.textPrimary.color)
        }
        .brevFont(.body)
        .accessibilityHint(NotificationPanePresentation.authorizationSubtitle(for: authorizationStatus, platform: .iOS))

        switch NotificationPanePresentation.authorizationAction(for: authorizationStatus) {
        case .requestAccess:
            Button {
                Task { await requestAuthorization() }
            } label: {
                Text(isRequestingAuthorization ? String(localized: "Requesting…", bundle: .module) : String(
                    localized: "Allow Notifications",
                    bundle: .module
                ))
            }
            .foregroundStyle(theme.accent.color)
            .disabled(isRequestingAuthorization)
        case .openSettings:
            Button {
                openAppSettings()
            } label: {
                Text("Open Settings", bundle: .module)
            }
            .foregroundStyle(theme.accent.color)
            .accessibilityHint(NotificationPanePresentation.authorizationSubtitle(for: .denied, platform: .iOS))
        case .none:
            EmptyView()
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
    #endif

    private var macAuthorizationRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: BrevSpacing.md) {
                authorizationText
                Spacer(minLength: BrevSpacing.sm)
                authorizationActions
            }
            VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                authorizationText
                authorizationActions
            }
        }
        .padding(BrevSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsInlineSurface()
    }

    private var authorizationText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Authorization", bundle: .module)
                .brevFont(.body)
                .foregroundStyle(theme.textPrimary.color)
            Text(authorizationStatus.displaySubtitle)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var authorizationActions: some View {
        HStack(spacing: BrevSpacing.md) {
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

    @ViewBuilder
    private var testNotificationButton: some View {
        #if os(iOS)
        if canFireTestNotification {
            Button {
                Task { await fireTestNotification() }
            } label: {
                Text("Test notification", bundle: .module)
            }
            .foregroundStyle(theme.accent.color)
            if let lastTestResult {
                Text(lastTestResult)
                    .brevFont(.footnote)
                    .foregroundStyle(theme.textSecondary.color)
            }
        }
        #else
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
        #endif
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
        authorizationStatus = await authorizationStatusProvider()
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

    #if os(macOS)
    /// Persists the per-device flag and signals the app to start/stop the
    /// `BackgroundMailCoordinator` and menu-bar item.
    private var backgroundMailBinding: Binding<Bool> {
        Binding(
            get: { settings.backgroundMailEnabled },
            set: { newValue in
                settings.backgroundMailEnabled = newValue
                settingsStore.save(settings)
                NotificationCenter.default.post(
                    name: .brevNotificationSettingsDidChange,
                    object: nil
                )
            }
        )
    }
    #endif

    /// Persists the flag and signals observers — the widget snapshot
    /// republishes immediately so stored previews clear without waiting
    /// for the next badge refresh (ADR-0083).
    private var showPreviewsBinding: Binding<Bool> {
        Binding(
            get: { settings.showPreviews },
            set: { newValue in
                settings.showPreviews = newValue
                settingsStore.save(settings)
                NotificationCenter.default.post(name: .brevNotificationSettingsDidChange, object: nil)
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
