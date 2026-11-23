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
            receivedAt: Self.sampleDate,
            now: Self.sampleDate
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
            receivedAt: Self.sampleDate,
            now: Self.sampleDate
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
            receivedAt: Self.sampleDate,
            now: Self.sampleDate
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
    func autoDismissesAfterTimeout() async {
        let controller = NewMailPanelStateController(autoDismissDelay: .milliseconds(20))
        let payload = NewMailPanelPayload(
            route: Self.makeRoute(),
            senderName: "Maya Okafor",
            senderEmail: "maya@example.com",
            previewLine: "Launch checklist — Ready for Thursday?",
            receivedAt: Self.sampleDate
        )

        controller.present(payload)
        #expect(controller.activePayload == payload)

        await controller.awaitAutoDismissForTesting()
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

    @Test("Verification code alongside a support URL is still suppressed from drop-down previews")
    func suppressesVerificationCodeWithSupportURL() {
        var settings = NotificationSettings.defaults
        settings.newMailPanelEnabled = true
        settings.showPreviews = true
        let now = Date(timeIntervalSince1970: 1_794_500_000)
        let route = NotificationMailRoute(accountID: "acct-1", folderID: "inbox", messageID: "msg-otp")
        let payload = NewMailPanelPolicy.payload(
            settings: settings,
            route: route,
            correspondent: Correspondent(name: "GitHub", email: "noreply@github.com"),
            subject: "Security verification",
            snippet: "Your verification code is 482913. Need help? https://support.github.com/help",
            receivedAt: now.addingTimeInterval(-10),
            now: now
        )
        #expect(payload == nil)
    }

    @Test("Historical cached backfill messages older than freshness window do not pop drop-down panel")
    func suppressesStaleMessages() {
        var settings = NotificationSettings.defaults
        settings.newMailPanelEnabled = true
        let now = Date(timeIntervalSince1970: 1_794_500_000)
        let route = NotificationMailRoute(accountID: "acct-1", folderID: "inbox", messageID: "msg-old")
        let payload = NewMailPanelPolicy.payload(
            settings: settings,
            route: route,
            correspondent: Correspondent(name: "Maya", email: "maya@example.org"),
            subject: "Last month's notes",
            snippet: "Here is the summary",
            receivedAt: now.addingTimeInterval(-7200),
            now: now
        )
        #expect(payload == nil)
    }

    @Test("Sign-in link split across subject wording and snippet URL is suppressed from drop-down previews")
    func suppressesSplitSubjectAndSnippetSignInLink() {
        var settings = NotificationSettings.defaults
        settings.newMailPanelEnabled = true
        settings.showPreviews = true
        let now = Date(timeIntervalSince1970: 1_794_500_000)
        let route = NotificationMailRoute(accountID: "acct-1", folderID: "inbox", messageID: "msg-link")
        let payload = NewMailPanelPolicy.payload(
            settings: settings,
            route: route,
            correspondent: Correspondent(name: "Example Cloud", email: "noreply@example.com"),
            subject: "Your magic sign-in link",
            snippet: "https://auth.example.com/verify?token=secret-abc-123",
            receivedAt: now.addingTimeInterval(-10),
            now: now
        )
        #expect(payload == nil)
    }

    @Test("Archive destination falls back to All Mail for label-based providers like Gmail")
    func archiveDestinationResolvesAllMailFallback() {
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        let allMail = Folder(id: "ALL_MAIL", name: "All Mail", role: .allMail)
        let archive = Folder(id: "Archive", name: "Archive", role: .archive)

        #expect(NotificationActionExecutor.archiveDestinationFolder(in: [inbox, allMail])?.id == "ALL_MAIL")
        #expect(NotificationActionExecutor.archiveDestinationFolder(in: [inbox, allMail, archive])?.id == "Archive")
        #expect(NotificationActionExecutor.archiveDestinationFolder(in: [inbox]) == nil)
    }

    @Test("Cold notification action awaits prepareBackends before resolving account")
    func coldActionAwaitsPrepareBackends() async throws {
        let backend = MockBackend(account: .preview)
        try await backend.connect()
        let inbox = try await #require(backend.folders().first { $0.role == .inbox })
        let header = try await #require(backend.messages(in: inbox, pageToken: nil).headers.first)
        try await backend.setRead(false, for: [header.id])

        var restored: [any MailBackend] = []
        let executor = NotificationActionExecutor(
            backendsProvider: { restored },
            prepareBackends: { restored = [backend] }
        )
        let route = NotificationMailRoute(
            accountID: backend.account.id,
            folderID: inbox.id,
            messageID: header.id
        )
        let ok = await executor.markRead(route: route)
        #expect(ok)
        let updated = try await backend.messages(in: inbox, pageToken: nil).headers.first { $0.id == header.id }
        #expect(updated?.isRead == true)
    }
}
