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

@Suite("Sign-in code panel and surfaces (#239, ADR-0088)")
@MainActor
struct SignInCodePanelTests {
    private static let now = Date(timeIntervalSince1970: 1_794_500_000)

    private final class MockConcealedPasteboard: SignInCodePasteboardWriting {
        private(set) var changeCount = 10
        private(set) var storedString: String?
        private(set) var wasConcealed = false
        private(set) var clearCallCount = 0

        func writeConcealed(_ value: String) -> Int {
            changeCount += 1
            storedString = value
            wasConcealed = true
            return changeCount
        }

        func clearIfUnchanged(expectedChangeCount: Int) {
            guard changeCount == expectedChangeCount else { return }
            clearCallCount += 1
            storedString = nil
            changeCount += 1
        }

        func simulateExternalCopy(_ other: String) {
            changeCount += 1
            storedString = other
            wasConcealed = false
        }
    }

    @Test("groupedCode formats 6- and 8-character codes cleanly while preserving short codes")
    func groupedCodeFormatting() {
        #expect(SignInCodePresentationFormat.groupedCode("525488") == "525-488")
        #expect(SignInCodePresentationFormat.groupedCode("482913") == "482-913")
        #expect(SignInCodePresentationFormat.groupedCode("12345678") == "1234-5678")
        #expect(SignInCodePresentationFormat.groupedCode("1234") == "1234")
    }

    @Test("copy writes concealed pasteboard and only clears when changeCount is unchanged")
    func concealedCopyAndSafeClear() async throws {
        let pasteboard = MockConcealedPasteboard()
        let controller = SignInCodePanelStateController(
            pasteboard: pasteboard,
            clipboardClearDelay: .milliseconds(40),
            copiedDismissDelay: .milliseconds(20),
            isAppActive: { true }
        )

        let presentation = SignInCodePresentation(
            accountID: "acct-1",
            messageID: "msg-1",
            sender: "GitHub",
            content: .code("525488"),
            timeout: 60
        )
        controller.present(presentation)
        controller.copyActiveCode()

        #expect(pasteboard.storedString == "525488")
        #expect(pasteboard.wasConcealed == true)
        #expect(controller.didCopyActiveCode == true)

        try await Task.sleep(for: .milliseconds(100))
        #expect(controller.activePresentation == nil)
        #expect(pasteboard.storedString == nil)
        #expect(pasteboard.clearCallCount == 1)

        // Second copy: user copies something else before the clear timer fires.
        controller.present(presentation)
        controller.copyActiveCode()
        pasteboard.simulateExternalCopy("keep-this")
        try await Task.sleep(for: .milliseconds(100))
        #expect(pasteboard.storedString == "keep-this")
        #expect(pasteboard.clearCallCount == 1)
    }

    @Test("Escape dismisses the panel ONLY when Brev is the active app (ADR-0088 §9)")
    func escapeOnlyDismissesWhenAppActive() {
        var active = false
        let controller = SignInCodePanelStateController(
            pasteboard: MockConcealedPasteboard(),
            isAppActive: { active }
        )
        let presentation = SignInCodePresentation(
            accountID: "acct-1",
            messageID: "msg-1",
            sender: "GitHub",
            content: .code("482913"),
            timeout: 60
        )
        controller.present(presentation)

        #expect(controller.handleEscapeKey() == false)
        #expect(controller.activePresentation != nil)

        active = true
        #expect(controller.handleEscapeKey() == true)
        #expect(controller.activePresentation == nil)
    }

    @Test("newer code from the same account and sender replaces older instead of stacking")
    func sameSenderReplacesOlder() {
        let controller = SignInCodePanelStateController(
            pasteboard: MockConcealedPasteboard(),
            isAppActive: { true }
        )
        let first = SignInCodePresentation(
            accountID: "acct-1",
            messageID: "msg-1",
            sender: "GitHub",
            content: .code("111222"),
            timeout: 60
        )
        let second = SignInCodePresentation(
            accountID: "acct-1",
            messageID: "msg-2",
            sender: "GitHub",
            content: .code("333444"),
            timeout: 60
        )
        controller.present(first)
        controller.present(second)

        #expect(controller.activePresentation?.messageID == "msg-2")
        #expect(controller.queuedCount == 0)
    }

    @Test("derived code and link state never leaks into descriptions or mirrors (ADR-0088 §7)")
    func redactionEnforcedAcrossDerivedTypes() {
        let secretCode = "739204"
        let secretLink = "https://auth.example.com/magic?token=supersecret999"

        let codePresentation = SignInCodePresentation(
            accountID: "acct-1",
            messageID: "msg-1",
            sender: "GitHub",
            content: .code(secretCode),
            timeout: 60
        )
        let linkPresentation = SignInCodePresentation(
            accountID: "acct-1",
            messageID: "msg-2",
            sender: "Linear",
            content: .link(destination: secretLink, host: "auth.example.com"),
            timeout: 60
        )
        let surfaceMatch = SignInCodeSurfaceMatch(
            code: secretCode,
            sender: "GitHub",
            sentAt: Self.now,
            messageID: "msg-1",
            folderID: "inbox",
            sourceID: nil
        )

        for value in [
            String(describing: codePresentation),
            String(reflecting: codePresentation),
            String(describing: linkPresentation),
            String(reflecting: linkPresentation),
            String(describing: surfaceMatch),
            String(reflecting: surfaceMatch),
        ] {
            #expect(!value.contains(secretCode))
            #expect(!value.contains(secretLink))
            #expect(!value.contains("supersecret999"))
        }

        #expect(Mirror(reflecting: codePresentation).children.isEmpty)
        #expect(Mirror(reflecting: surfaceMatch).children.isEmpty)
    }

    @Test("surface extraction requires per-account opt-in and applies local expiry rule")
    func surfaceOptInAndExpiry() throws {
        let header = MessageHeader(
            id: "msg-1",
            threadID: "t-1",
            folderID: "inbox",
            from: Correspondent(name: "GitHub", email: "noreply@github.com"),
            subject: "Your verification code is 525488",
            snippet: "Use 525488 to sign in.",
            date: Self.now.addingTimeInterval(-120),
            isRead: false
        )

        // Default off: never runs detection.
        let offResult = SignInCodeSurfacePolicy.headerCode(
            for: header,
            sourceID: nil,
            accountID: "acct-1",
            settings: .defaults
        )
        #expect(offResult == nil)

        var optedIn = SignInCodeSettings.defaults
        optedIn.setAccountOverride(accountID: "acct-1", codesEnabled: true, linksEnabled: false)

        let match = try #require(SignInCodeSurfacePolicy.headerCode(
            for: header,
            sourceID: nil,
            accountID: "acct-1",
            settings: optedIn
        ))
        #expect(match.code == "525488")
        #expect(!SignInCodePresentationFormat.isProbablyExpired(sentAt: match.sentAt, now: Self.now))

        let expiredDate = Self.now.addingTimeInterval(-15 * 60)
        #expect(SignInCodePresentationFormat.isProbablyExpired(sentAt: expiredDate, now: Self.now))

        let expiredHeader = MessageHeader(
            id: "msg-old",
            threadID: "t-old",
            folderID: "inbox",
            from: Correspondent(name: "GitHub", email: "noreply@github.com"),
            subject: "Your verification code is 998877",
            snippet: "",
            date: expiredDate,
            isRead: false
        )
        #expect(SignInCodeSurfacePolicy.newestActiveCode(
            headers: [expiredHeader],
            sourceID: nil,
            accountID: "acct-1",
            settings: optedIn,
            now: Self.now
        ) == nil)
        #expect(SignInCodeSurfacePolicy.newestActiveCode(
            headers: [expiredHeader, header],
            sourceID: nil,
            accountID: "acct-1",
            settings: optedIn,
            now: Self.now
        )?.code == "525488")
    }

    @Test("sign-in code UI copy has Norwegian translations")
    func norwegianCopy() throws {
        let catalog = try LocalizationCatalogTestSupport.loadCatalogStrings()
        let requiredKeys = [
            "Copy code",
            "Sign-in code",
            "Sign-in code · probably expired",
            "%@ sent a sign-in link",
            "Click to open it in your browser",
            "Codes usually stop working after a few minutes.",
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
