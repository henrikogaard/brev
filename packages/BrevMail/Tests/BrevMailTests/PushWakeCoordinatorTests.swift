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

@Suite("PushWakeCoordinator (#11)")
@MainActor
struct PushWakeCoordinatorTests {
    private static let workAccount = BrevAccount(
        id: BrevAccount.imapSMTPAccountID(forEmailAddress: "work@example.org"),
        displayName: "Work",
        emailAddress: "work@example.org"
    )
    private static let personalAccount = BrevAccount(
        id: BrevAccount.imapSMTPAccountID(forEmailAddress: "personal@example.org"),
        displayName: "Personal",
        emailAddress: "personal@example.org"
    )
    private static let workOpaqueToken = "acct-opaque-work-1"
    private static let personalOpaqueToken = "acct-opaque-personal-2"

    @Test("ignores wakes with zero sync or notification calls when closed-app push is disabled")
    func ignoresWakesWhenDisabled() async {
        let recorder = SyncedAccountRecorder()
        var notifiedCount = 0
        let coordinator = PushWakeCoordinator(
            settingsProvider: {
                PushRelaySettings(
                    isEnabled: false,
                    mode: .userHostedRelay,
                    endpointURLString: "https://relay.example.com/push",
                    enabledAccountIDs: [Self.workAccount.id],
                    opaqueAccountTokens: [Self.workAccount.id: Self.workOpaqueToken]
                )
            },
            backendsProvider: { [MockBackend(account: Self.workAccount)] },
            refreshBackends: { backends in
                await recorder.record(backends.map(\.account.id))
                return nil
            },
            notifyArrivedMail: { _, _ in notifiedCount += 1 }
        )

        let result = await coordinator.handleWake(
            PushWakePayload(accountID: Self.workOpaqueToken, stateToken: "s1", eventKind: .newMail)
        )
        #expect(result == .ignoredDisabled)
        #expect(await recorder.syncedAccountIDs().isEmpty)
        #expect(notifiedCount == 0)
    }

    @Test("ignores wakes for non-opted-in accounts and rejects unmapped raw IMAP account IDs")
    func ignoresNonOptedInAndRawEmailAccountIDs() async {
        let recorder = SyncedAccountRecorder()
        var notifiedCount = 0
        let coordinator = PushWakeCoordinator(
            settingsProvider: {
                PushRelaySettings(
                    isEnabled: true,
                    mode: .userHostedRelay,
                    endpointURLString: "https://relay.example.com/push",
                    enabledAccountIDs: [Self.workAccount.id],
                    opaqueAccountTokens: [
                        Self.workAccount.id: Self.workOpaqueToken,
                        Self.personalAccount.id: Self.personalOpaqueToken
                    ]
                )
            },
            backendsProvider: {
                [MockBackend(account: Self.workAccount), MockBackend(account: Self.personalAccount)]
            },
            refreshBackends: { backends in
                await recorder.record(backends.map(\.account.id))
                return nil
            },
            notifyArrivedMail: { _, _ in notifiedCount += 1 }
        )

        let nonOptedInResult = await coordinator.handleWake(
            PushWakePayload(accountID: Self.personalOpaqueToken, stateToken: nil, eventKind: .mailboxChanged)
        )
        #expect(nonOptedInResult == .ignoredAccountNotOptedIn(accountID: Self.personalOpaqueToken))

        // Raw `imap-smtp:work@example.org` ID MUST NOT match — only the opaque device-local token matches.
        let rawIDResult = await coordinator.handleWake(
            PushWakePayload(accountID: Self.workAccount.id, stateToken: nil, eventKind: .newMail)
        )
        #expect(rawIDResult == .ignoredAccountNotOptedIn(accountID: Self.workAccount.id))
        #expect(await recorder.syncedAccountIDs().isEmpty)
        #expect(notifiedCount == 0)
    }

    @Test("reverse-maps opaque token, syncs only the targeted opted-in account, and invokes scene-less notification seam")
    func syncsOnlyTargetedOptedInAccountAndNotifies() async {
        let recorder = SyncedAccountRecorder()
        var notifiedAccounts: [String] = []
        let coordinator = PushWakeCoordinator(
            settingsProvider: {
                PushRelaySettings(
                    isEnabled: true,
                    mode: .userHostedRelay,
                    endpointURLString: "https://relay.example.com/push",
                    enabledAccountIDs: [Self.workAccount.id, Self.personalAccount.id],
                    opaqueAccountTokens: [
                        Self.workAccount.id: Self.workOpaqueToken,
                        Self.personalAccount.id: Self.personalOpaqueToken
                    ]
                )
            },
            backendsProvider: {
                [MockBackend(account: Self.workAccount), MockBackend(account: Self.personalAccount)]
            },
            refreshBackends: { backends in
                await recorder.record(backends.map(\.account.id))
                return nil
            },
            notifyArrivedMail: { backend, _ in
                notifiedAccounts.append(backend.account.id)
            }
        )

        let userInfo: [AnyHashable: Any] = [
            "aps": ["content-available": 1],
            "brev": [
                "accountID": Self.workOpaqueToken,
                "stateToken": "modseq-99",
                "eventKind": "new_mail"
            ]
        ]
        let result = await coordinator.handleRemoteNotificationUserInfo(userInfo)
        #expect(result == .synced(accountID: Self.workAccount.id))
        #expect(await recorder.syncedAccountIDs() == [[Self.workAccount.id]])
        #expect(notifiedAccounts == [Self.workAccount.id])
    }

    @Test("routes RFC 8620 §7.2.2 JMAP PushVerification challenges without triggering mail sync")
    func handlesJMAPVerificationChallenge() async {
        let recorder = SyncedAccountRecorder()
        var capturedChallenge: (String, String)?
        let coordinator = PushWakeCoordinator(
            settingsProvider: {
                PushRelaySettings(
                    isEnabled: true,
                    mode: .jmapWebPush,
                    endpointURLString: "https://jmap.example.com/api",
                    webPushDeliveryURLString: "https://webpush.example.com/push/dev1",
                    enabledAccountIDs: [Self.workAccount.id],
                    opaqueAccountTokens: [Self.workAccount.id: Self.workOpaqueToken]
                )
            },
            backendsProvider: { [MockBackend(account: Self.workAccount)] },
            refreshBackends: { backends in
                await recorder.record(backends.map(\.account.id))
                return nil
            },
            notifyArrivedMail: { _, _ in }
        )
        coordinator.onJMAPVerificationChallenge = { subID, code in
            capturedChallenge = (subID, code)
        }

        let challengeJSON = Data("""
        {"@type":"PushVerification","pushSubscriptionId":"jmap-sub-42","verificationCode":"verify-token-9"}
        """.utf8)
        let result = await coordinator.handleWakeData(challengeJSON)
        #expect(result == .jmapVerificationChallenge(subscriptionID: "jmap-sub-42", verificationCode: "verify-token-9"))
        #expect(capturedChallenge?.0 == "jmap-sub-42")
        #expect(capturedChallenge?.1 == "verify-token-9")
        #expect(await recorder.syncedAccountIDs().isEmpty)
    }

    @Test("restores accounts on cold wake when backends are initially empty")
    func restoresOnColdWake() async {
        let recorder = SyncedAccountRecorder()
        var restored = false
        let coordinator = PushWakeCoordinator(
            settingsProvider: {
                PushRelaySettings(
                    isEnabled: true,
                    mode: .jmapWebPush,
                    endpointURLString: "https://jmap.example.com/api",
                    webPushDeliveryURLString: "https://webpush.example.com/push/dev1",
                    enabledAccountIDs: [Self.workAccount.id],
                    opaqueAccountTokens: [Self.workAccount.id: Self.workOpaqueToken]
                )
            },
            backendsProvider: {
                restored ? [MockBackend(account: Self.workAccount)] : []
            },
            ensureAccountsRestored: {
                restored = true
            },
            refreshBackends: { backends in
                await recorder.record(backends.map(\.account.id))
                return nil
            },
            notifyArrivedMail: { _, _ in }
        )

        let result = await coordinator.handleWake(
            PushWakePayload(accountID: Self.workOpaqueToken, stateToken: "jmap-state-7", eventKind: .mailboxChanged)
        )
        #expect(restored)
        #expect(result == .synced(accountID: Self.workAccount.id))
        #expect(await recorder.syncedAccountIDs() == [[Self.workAccount.id]])
    }

    @Test("rejects malformed remote notification payloads without triggering sync")
    func rejectsMalformedUserInfo() async {
        let recorder = SyncedAccountRecorder()
        let coordinator = PushWakeCoordinator(
            settingsProvider: {
                PushRelaySettings(
                    isEnabled: true,
                    mode: .userHostedRelay,
                    endpointURLString: "https://relay.example.com/push",
                    enabledAccountIDs: [Self.workAccount.id],
                    opaqueAccountTokens: [Self.workAccount.id: Self.workOpaqueToken]
                )
            },
            backendsProvider: { [MockBackend(account: Self.workAccount)] },
            refreshBackends: { backends in
                await recorder.record(backends.map(\.account.id))
                return nil
            },
            notifyArrivedMail: { _, _ in }
        )

        let result = await coordinator.handleRemoteNotificationUserInfo(["aps": ["content-available": 1]])
        #expect(result == .ignoredInvalidPayload)
        #expect(await recorder.syncedAccountIDs().isEmpty)
    }

    @Test("reports sync failures cleanly without firing arrival notifications")
    func reportsSyncFailure() async {
        var notifiedCount = 0
        let coordinator = PushWakeCoordinator(
            settingsProvider: {
                PushRelaySettings(
                    isEnabled: true,
                    mode: .userHostedRelay,
                    endpointURLString: "https://relay.example.com/push",
                    enabledAccountIDs: [Self.workAccount.id],
                    opaqueAccountTokens: [Self.workAccount.id: Self.workOpaqueToken]
                )
            },
            backendsProvider: { [MockBackend(account: Self.workAccount)] },
            refreshBackends: { _ in "IMAP connection timed out" },
            notifyArrivedMail: { _, _ in notifiedCount += 1 }
        )

        let result = await coordinator.handleWake(
            PushWakePayload(accountID: Self.workOpaqueToken, stateToken: nil, eventKind: .newMail)
        )
        #expect(result == .failed(accountID: Self.workAccount.id, message: "IMAP connection timed out"))
        #expect(notifiedCount == 0)
    }
}

private actor SyncedAccountRecorder {
    private var batches: [[String]] = []

    func record(_ ids: [String]) {
        batches.append(ids)
    }

    func syncedAccountIDs() -> [[String]] {
        batches
    }
}
