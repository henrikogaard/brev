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

import Foundation

/// Platform whose wording and rows the Notifications pane should use.
enum NotificationPanePlatform {
    case macOS
    case iOS

    /// The platform this build runs on.
    static var current: NotificationPanePlatform {
        #if os(iOS)
        .iOS
        #else
        .macOS
        #endif
    }
}

/// What the authorization row offers for the current permission state.
enum NotificationAuthorizationAction: Equatable {
    case requestAccess
    case openSettings
    case none
}

/// Copy and row rules for the Notifications pane, kept apart from the view so
/// the platform and permission branches can be tested.
enum NotificationPanePresentation {
    /// Title of the unread-badge toggle; macOS names the Dock, iOS the app icon.
    static func badgeToggleTitle(platform: NotificationPanePlatform) -> String {
        switch platform {
        case .macOS: String(localized: "Show dock badge", bundle: .module)
        case .iOS: String(localized: "App icon badge", bundle: .module)
        }
    }

    /// The single action the permission row exposes for a status.
    static func authorizationAction(for status: BrevSettingsNotificationAuthStatus) -> NotificationAuthorizationAction {
        switch status {
        case .notDetermined: .requestAccess
        case .denied: .openSettings
        case .authorized, .provisional, .ephemeral: .none
        }
    }

    /// Secondary line under the permission row.
    static func authorizationSubtitle(
        for status: BrevSettingsNotificationAuthStatus,
        platform: NotificationPanePlatform
    ) -> String {
        guard status == .denied, platform == .iOS else { return status.displaySubtitle }
        return String(localized: "Turn on Allow Notifications for Brev in Settings.", bundle: .module)
    }

    /// Footer explaining when alerts arrive, in plain words on iPhone.
    static func deliveryFooter(platform: NotificationPanePlatform) -> String {
        switch platform {
        case .macOS:
            NotificationDeliveryExpectation.settingsCalloutMessage
        case .iOS:
            String(
                localized: "Brev alerts you while it is open or refreshing in the background. iOS decides when background refresh runs, so alerts can arrive late when Brev is closed.",
                bundle: .module
            )
        }
    }

    /// Whether the sound and preview rows accept input. They stay visible and
    /// keep full contrast when off, so the pane never fades rows below contrast.
    static func dependentRowsEnabled(notificationsEnabled: Bool) -> Bool {
        notificationsEnabled
    }
}
