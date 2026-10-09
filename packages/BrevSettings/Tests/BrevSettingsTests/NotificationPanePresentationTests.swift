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

@testable import BrevSettings
import Testing

@Suite("NotificationPanePresentation")
struct NotificationPanePresentationTests {
    @Test("the badge toggle names the dock only on macOS")
    func badgeToggleTitleIsPlatformSpecific() {
        #expect(NotificationPanePresentation.badgeToggleTitle(platform: .macOS) == "Show dock badge")
        #expect(NotificationPanePresentation.badgeToggleTitle(platform: .iOS) == "App icon badge")
    }

    @Test("denied permission offers Open Settings; undecided offers a request; granted offers nothing")
    func authorizationActionFollowsPermission() {
        #expect(NotificationPanePresentation.authorizationAction(for: .denied) == .openSettings)
        #expect(NotificationPanePresentation.authorizationAction(for: .notDetermined) == .requestAccess)
        for status in [BrevSettingsNotificationAuthStatus.authorized, .provisional, .ephemeral] {
            #expect(NotificationPanePresentation.authorizationAction(for: status) == .none)
        }
    }

    @Test("iPhone denied copy points at Settings, not System Settings")
    func deniedSubtitleUsesPlatformName() {
        let phone = NotificationPanePresentation.authorizationSubtitle(for: .denied, platform: .iOS)
        #expect(phone.contains("Settings"))
        #expect(!phone.contains("System Settings"))
        let mac = NotificationPanePresentation.authorizationSubtitle(for: .denied, platform: .macOS)
        #expect(mac.contains("System Settings"))
        for status in BrevSettingsNotificationAuthStatus.allCases {
            #expect(!NotificationPanePresentation.authorizationSubtitle(for: status, platform: .iOS).isEmpty)
        }
    }

    @Test("iPhone delivery footer avoids sync-engine jargon")
    func deliveryFooterIsPlainOnIPhone() {
        let footer = NotificationPanePresentation.deliveryFooter(platform: .iOS)
        #expect(!footer.isEmpty)
        for jargon in ["IDLE", "polling", "push relay", "history"] {
            #expect(!footer.contains(jargon))
        }
        #expect(
            NotificationPanePresentation.deliveryFooter(platform: .macOS)
                == NotificationDeliveryExpectation.settingsCalloutMessage
        )
    }

    @Test("sound and preview rows are disabled, not hidden, while notifications are off")
    func dependentRowsStayVisible() {
        #expect(!NotificationPanePresentation.dependentRowsEnabled(notificationsEnabled: false))
        #expect(NotificationPanePresentation.dependentRowsEnabled(notificationsEnabled: true))
    }
}
