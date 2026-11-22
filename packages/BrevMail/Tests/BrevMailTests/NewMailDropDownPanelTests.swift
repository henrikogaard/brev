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
@testable import BrevMail
import BrevSettings
import Foundation
import Testing

@Suite("New-mail drop-down panel (#307)")
@MainActor
struct NewMailDropDownPanelTests {
    private static let sampleDate = Date(timeIntervalSince1970: 1_794_500_000)

    private static func makeRoute() -> NotificationMailRoute {
        NotificationMailRoute(
            accountID: "acct-1",
            folderID: "inbox",
            messageID: "msg-1"
        )
    }

    @Test("drop-down panel is suppressed by default when opt-in setting is off")
    func suppressedByDefault() {
        let settings = NotificationSettings.defaults
        let payload = NewMailPanelPolicy.payload(
            settings: settings,
            route: Self.makeRoute(),
            correspondent: Correspondent(name: "Maya Okafor", email: "maya@example.com"),
            subject: "Launch checklist",
            snippet: "Ready for Thursday?",
            receivedAt: Self.sampleDate
        )
        #expect(payload == nil)
    }

    @Test("drop-down panel shows sender and one-line preview when opted in")
    func showsSenderAndPreviewWhenEnabled() throws {
        var settings = NotificationSettings.defaults
        settings.notificationsEnabled = true
        settings.newMailPanelEnabled = true

        let payload = try #require(NewMailPanelPolicy.payload(
            settings: settings,
            route: Self.makeRoute(),
            correspondent: Correspondent(name: "Maya Okafor", email: "maya@example.com"),
            subject: "Launch checklist",
            snippet: "Ready for Thursday?",
            receivedAt: Self.sampleDate
        ))

        #expect(payload.senderName == "Maya Okafor")
        #expect(payload.senderEmail == "maya@example.com")
        #expect(payload.previewLine.contains("Launch checklist"))
        #expect(payload.previewLine.contains("Ready for Thursday?"))
    }

    @Test("drop-down panel hides message text when showPreviews is off")
    func hidesPreviewWhenShowPreviewsIsOff() throws {
        var settings = NotificationSettings.defaults
        settings.notificationsEnabled = true
        settings.newMailPanelEnabled = true
        settings.showPreviews = false

        let payload = try #require(NewMailPanelPolicy.payload(
            settings: settings,
            route: Self.makeRoute(),
            correspondent: Correspondent(name: "Maya Okafor", email: "maya@example.com"),
            subject: "Confidential offer",
            snippet: "Salary details attached",
            receivedAt: Self.sampleDate
        ))

        #expect(!payload.previewLine.contains("Confidential"))
        #expect(!payload.previewLine.contains("Salary"))
    }

    @Test("drop-down panel excludes sign-in code messages per ADR-0088")
    func excludesSignInCodeMessages() {
        var settings = NotificationSettings.defaults
        settings.notificationsEnabled = true
        settings.newMailPanelEnabled = true

        let codePayload = NewMailPanelPolicy.payload(
            settings: settings,
            route: Self.makeRoute(),
            correspondent: Correspondent(name: "GitHub", email: "noreply@github.com"),
            subject: "Your verification code is 482913",
            snippet: "Use this code to sign in.",
            receivedAt: Self.sampleDate
        )
        #expect(codePayload == nil)

        let snippetCodePayload = NewMailPanelPolicy.payload(
            settings: settings,
            route: Self.makeRoute(),
            correspondent: Correspondent(name: "Example", email: "security@example.com"),
            subject: "Sign in to Example",
            snippet: "Your one-time code is 918273",
            receivedAt: Self.sampleDate
        )
        #expect(snippetCodePayload == nil)
    }

    @Test("panel state auto-dismisses after timeout and cancels on manual dismiss")
    func autoDismissesAfterTimeout() async throws {
        let controller = NewMailPanelStateController(autoDismissDelay: .milliseconds(40))
        let payload = NewMailPanelPayload(
            route: Self.makeRoute(),
            senderName: "Maya Okafor",
            senderEmail: "maya@example.com",
            previewLine: "Launch checklist — Ready for Thursday?",
            receivedAt: Self.sampleDate
        )

        controller.present(payload)
        #expect(controller.activePayload == payload)

        let deadline = Date().addingTimeInterval(2.0)
        while controller.activePayload != nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(controller.activePayload == nil)
    }

    @Test("panel action keys have Norwegian translations")
    func norwegianCopy() throws {
        let catalog = try LocalizationCatalogTestSupport.loadCatalogStrings()
        let requiredKeys = [
            "Mark as Read",
            "Archive",
            "Reply",
            "New mail",
        ]
        for key in requiredKeys {
            let entry = try #require(catalog[key] as? [String: Any], "Missing catalog key \(key)")
            let localizations = try #require(entry["localizations"] as? [String: Any])
            let nb = try #require(localizations["nb"] as? [String: Any])
            let value = (nb["stringUnit"] as? [String: Any])?["value"] as? String
            #expect(value?.isEmpty == false, "Missing nb localization for \(key)")
        }
    }
}
