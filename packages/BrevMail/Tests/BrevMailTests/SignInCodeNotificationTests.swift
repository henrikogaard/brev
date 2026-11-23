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
import UserNotifications

@MainActor
private final class MockSignInNotificationScheduler: SignInCodeNotificationScheduling {
    struct PostedNotification: Equatable {
        let identifier: String
        let payload: SignInCodeNotificationPolicy.Payload
    }

    var posted: [PostedNotification] = []
    var removedIdentifiers: [[String]] = []
    var removedAccountIDs: [String] = []

    func postSignInNotification(
        identifier: String,
        payload: SignInCodeNotificationPolicy.Payload
    ) async {
        posted.append(PostedNotification(identifier: identifier, payload: payload))
    }

    func removeSignInNotifications(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(identifiers)
    }

    func removeAllSignInNotifications(forAccountID accountID: String) async {
        removedAccountIDs.append(accountID)
    }
}

@MainActor
private final class RecordingSignInPasteboard: SignInCodePasteboardWriting {
    var written: [String] = []
    private var changeCount = 0

    func writeConcealed(_ value: String) -> Int {
        written.append(value)
        changeCount += 1
        return changeCount
    }

    func clearIfUnchanged(expectedChangeCount: Int) {
        if changeCount == expectedChangeCount {
            written.removeAll()
        }
    }
}

@Suite("Sign-in code iOS notifications (ADR-0088)")
@MainActor
struct SignInCodeNotificationTests {
    @Test("notification payload excludes raw codes and magic-link URLs from every field")
    func payloadExcludesSecrets() {
        let codePresentation = SignInCodePresentation(
            accountID: "acct-1",
            messageID: "msg-code",
            folderID: "INBOX",
            sender: "Acme Security",
            content: .code("839204"),
            timeout: 60
        )
        let codePayload = SignInCodeNotificationPolicy.contentPayload(for: codePresentation)
        #expect(codePayload.title == "Acme Security")
        #expect(codePayload.categoryIdentifier == SignInCodeNotificationPolicy.codeCategoryIdentifier)
        #expect(!codePayload.title.contains("839204"))
        #expect(!codePayload.body.contains("839204"))
        #expect(!codePayload.threadIdentifier.contains("839204"))
        #expect(!codePayload.userInfo.values.contains { $0.contains("839204") })
        #expect(NotificationRoutingPolicy.route(from: codePayload.userInfo) == NotificationMailRoute(
            accountID: "acct-1",
            folderID: "INBOX",
            messageID: "msg-code"
        ))

        let secretURL = "https://auth.example.com/magic?token=super-secret-xyz"
        let linkPresentation = SignInCodePresentation(
            accountID: "acct-1",
            messageID: "msg-link",
            folderID: "INBOX",
            sender: "Acme",
            content: .link(destination: secretURL, host: "auth.example.com"),
            timeout: 60
        )
        let linkPayload = SignInCodeNotificationPolicy.contentPayload(for: linkPresentation)
        #expect(linkPayload.categoryIdentifier == SignInCodeNotificationPolicy.linkCategoryIdentifier)
        #expect(!linkPayload.title.contains("super-secret-xyz"))
        #expect(!linkPayload.body.contains("super-secret-xyz"))
        #expect(!linkPayload.body.contains("auth.example.com"))
        #expect(!linkPayload.userInfo.values.contains { $0.contains("super-secret-xyz") || $0.contains("auth.example.com") })
    }

    @Test("Copy code and Open link actions enforce biometric auth and correct foregrounding")
    func notificationActionsRequireAuthentication() {
        let copyAction = SignInCodeNotificationPolicy.makeCopyCodeAction()
        #expect(copyAction.identifier == SignInCodeNotificationPolicy.copyCodeActionIdentifier)
        #expect(copyAction.options.contains(.authenticationRequired))
        #expect(!copyAction.options.contains(.foreground))

        let openAction = SignInCodeNotificationPolicy.makeOpenLinkAction()
        #expect(openAction.identifier == SignInCodeNotificationPolicy.openLinkActionIdentifier)
        #expect(openAction.options.contains(.authenticationRequired))
        #expect(openAction.options.contains(.foreground))

        let codeCategory = SignInCodeNotificationPolicy.makeCodeCategory()
        #expect(codeCategory.identifier == SignInCodeNotificationPolicy.codeCategoryIdentifier)
        #expect(codeCategory.hiddenPreviewsBodyPlaceholder == "Sign-in code")
        #expect(codeCategory.actions.map(\.identifier) == [SignInCodeNotificationPolicy.copyCodeActionIdentifier])

        let linkCategory = SignInCodeNotificationPolicy.makeLinkCategory()
        #expect(linkCategory.identifier == SignInCodeNotificationPolicy.linkCategoryIdentifier)
        #expect(linkCategory.hiddenPreviewsBodyPlaceholder == "Sign-in link")
        #expect(linkCategory.actions.map(\.identifier) == [SignInCodeNotificationPolicy.openLinkActionIdentifier])
    }

    @Test("Copy code copies concealed value, removes delivered notification, and drops in-memory entry")
    func copyCodeActionSuccess() async {
        let scheduler = MockSignInNotificationScheduler()
        let pasteboard = RecordingSignInPasteboard()
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        var currentNow = baseDate
        var consent = SignInCodeSettings()
        consent.setAccountOverride(accountID: "acct-1", codesEnabled: true, linksEnabled: false)
        let presenter = SignInCodeNotificationPresenter(
            scheduler: scheduler,
            pasteboard: pasteboard,
            settings: { consent },
            now: { currentNow }
        )
        presenter.present(SignInCodePresentation(
            accountID: "acct-1",
            messageID: "msg-1",
            folderID: "INBOX",
            sender: "Linear",
            content: .code("482913"),
            timeout: 60
        ))
        await Task.yield()
        #expect(scheduler.posted.count == 1)
        #expect(presenter.storedEntryCount == 1)

        currentNow = baseDate.addingTimeInterval(30)
        let copied = await presenter.handleCopyCodeAction(
            route: NotificationMailRoute(accountID: "acct-1", folderID: "INBOX", messageID: "msg-1")
        )
        #expect(copied)
        #expect(pasteboard.written == ["482913"])
        #expect(presenter.storedEntryCount == 0)
        let expectedID = SignInCodeNotificationPolicy.notificationIdentifier(accountID: "acct-1", messageID: "msg-1")
        #expect(scheduler.removedIdentifiers.contains([expectedID]))
    }

    @Test("Copy code fails closed when consent is withdrawn or 10-minute window expires")
    func copyCodeFailsClosedOnConsentOrExpiry() async {
        let scheduler = MockSignInNotificationScheduler()
        let pasteboard = RecordingSignInPasteboard()
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        var currentNow = baseDate
        var codesEnabled = true
        let presenter = SignInCodeNotificationPresenter(
            scheduler: scheduler,
            pasteboard: pasteboard,
            settings: {
                var consent = SignInCodeSettings()
                consent.setAccountOverride(accountID: "acct-1", codesEnabled: codesEnabled, linksEnabled: false)
                return consent
            },
            now: { currentNow }
        )

        // Withdrawn consent fails closed.
        presenter.present(SignInCodePresentation(
            accountID: "acct-1",
            messageID: "msg-consent",
            folderID: "INBOX",
            sender: "GitHub",
            content: .code("111222"),
            timeout: 60
        ))
        codesEnabled = false
        let deniedByConsent = await presenter.handleCopyCodeAction(
            route: NotificationMailRoute(accountID: "acct-1", folderID: "INBOX", messageID: "msg-consent")
        )
        #expect(!deniedByConsent)
        #expect(pasteboard.written.isEmpty)

        // Expired after 10 minutes fails closed.
        codesEnabled = true
        presenter.present(SignInCodePresentation(
            accountID: "acct-1",
            messageID: "msg-expired",
            folderID: "INBOX",
            sender: "GitHub",
            content: .code("333444"),
            timeout: 60
        ))
        currentNow = baseDate.addingTimeInterval(601)
        let deniedByExpiry = await presenter.handleCopyCodeAction(
            route: NotificationMailRoute(accountID: "acct-1", folderID: "INBOX", messageID: "msg-expired")
        )
        #expect(!deniedByExpiry)
        #expect(pasteboard.written.isEmpty)
    }

    @Test("Open link stages foreground host confirmation without leaking link in descriptions")
    func openLinkStagesHostConfirmation() async throws {
        let scheduler = MockSignInNotificationScheduler()
        let pasteboard = RecordingSignInPasteboard()
        var consent = SignInCodeSettings()
        consent.setAccountOverride(accountID: "acct-1", codesEnabled: false, linksEnabled: true)
        let presenter = SignInCodeNotificationPresenter(
            scheduler: scheduler,
            pasteboard: pasteboard,
            settings: { consent }
        )
        let urlString = "https://login.northwind.example/verify?t=secret999"
        presenter.present(SignInCodePresentation(
            accountID: "acct-1",
            messageID: "msg-link",
            folderID: "INBOX",
            sender: "Northwind",
            content: .link(destination: urlString, host: "login.northwind.example"),
            timeout: 60
        ))

        let confirmation = await presenter.handleOpenLinkAction(
            route: NotificationMailRoute(accountID: "acct-1", folderID: "INBOX", messageID: "msg-link")
        )
        let resolved = try #require(confirmation)
        #expect(presenter.pendingLinkConfirmation == resolved)
        #expect(resolved.host == "login.northwind.example")
        #expect(resolved.destinationURL?.absoluteString == urlString)
        #expect(resolved.alertMessage.contains("login.northwind.example"))
        #expect(!String(describing: resolved).contains("secret999"))
        #expect(!String(describing: presenter).contains("secret999"))
    }

    @Test("dismiss(accountID:) and pruneExpired() remove only targeted notifications")
    func dismissAndPruneCleanup() async {
        let scheduler = MockSignInNotificationScheduler()
        let pasteboard = RecordingSignInPasteboard()
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        var currentNow = baseDate
        let presenter = SignInCodeNotificationPresenter(
            scheduler: scheduler,
            pasteboard: pasteboard,
            settings: { SignInCodeSettings() },
            now: { currentNow }
        )
        presenter.present(SignInCodePresentation(
            accountID: "acct-1",
            messageID: "m1",
            folderID: "INBOX",
            sender: "One",
            content: .code("111111"),
            timeout: 60
        ))
        presenter.present(SignInCodePresentation(
            accountID: "acct-2",
            messageID: "m2",
            folderID: "INBOX",
            sender: "Two",
            content: .code("222222"),
            timeout: 60
        ))
        #expect(presenter.storedEntryCount == 2)

        presenter.dismiss(accountID: "acct-1")
        await Task.yield()
        #expect(presenter.storedEntryCount == 1)
        #expect(scheduler.removedAccountIDs == ["acct-1"])

        currentNow = baseDate.addingTimeInterval(605)
        presenter.pruneExpired()
        #expect(presenter.storedEntryCount == 0)
        let m2ID = SignInCodeNotificationPolicy.notificationIdentifier(accountID: "acct-2", messageID: "m2")
        #expect(scheduler.removedIdentifiers.contains([m2ID]))
    }

    @Test("delegate buffers cold-launch Copy code and Open link actions until handlers install")
    func delegateBuffersSignInActions() async {
        let delegate = BrevNotificationDelegate()
        let copyRoute = NotificationMailRoute(accountID: "acct-1", folderID: "INBOX", messageID: "msg-cold-copy")
        let linkRoute = NotificationMailRoute(accountID: "acct-1", folderID: "INBOX", messageID: "msg-cold-link")

        final class RouteBox: @unchecked Sendable {
            private let lock = NSLock()
            private var value: NotificationMailRoute?
            func set(_ route: NotificationMailRoute) {
                lock.lock()
                value = route
                lock.unlock()
            }

            func get() -> NotificationMailRoute? {
                lock.lock()
                defer { lock.unlock() }
                return value
            }
        }

        let copyBox = RouteBox()
        let copyHandled: NotificationMailRoute? = await withCheckedContinuation { continuation in
            delegate.handleCopySignInCode(route: copyRoute) {
                continuation.resume(returning: copyBox.get())
            }
            delegate.onCopySignInCode = { received in
                copyBox.set(received)
            }
        }
        #expect(copyHandled == copyRoute)

        let linkBox = RouteBox()
        let linkHandled: NotificationMailRoute? = await withCheckedContinuation { continuation in
            delegate.handleOpenSignInLink(route: linkRoute) {
                continuation.resume(returning: linkBox.get())
            }
            delegate.onOpenSignInLink = { received in
                linkBox.set(received)
            }
        }
        #expect(linkHandled == linkRoute)
    }

    @Test("iOS sign-in notification copy has Norwegian catalog entries")
    func norwegianCatalogEntriesExist() throws {
        let strings = try LocalizationCatalogTestSupport.loadCatalogStrings()
        for key in [
            "Copy code",
            "Open link",
            "Sign-in code",
            "Sign-in link",
            "Sign-in code arrived",
            "Sign-in link arrived",
            "Open sign-in link?",
            "This sign-in link opens %@ in your browser.",
            "Sign-in link from %@ opens %@ in your browser."
        ] {
            let entry = try #require(strings[key] as? [String: Any], "Missing catalog key: \(key)")
            let nb = (entry["localizations"] as? [String: Any])?["nb"] as? [String: Any]
            let unit = nb?["stringUnit"] as? [String: Any]
            #expect((unit?["value"] as? String)?.isEmpty == false, "Missing nb translation for: \(key)")
        }
    }
}
