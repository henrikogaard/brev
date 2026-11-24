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
        id: "acct-work",
        displayName: "Work",
        emailAddress: "work@example.org"
    )
    private static let personalAccount = BrevAccount(
        id: "acct-personal",
        displayName: "Personal",
        emailAddress: "personal@example.org"
    )

    @Test("ignores wakes with zero sync calls when closed-app push is disabled")
    func ignoresWakesWhenDisabled() async {
        let recorder = SyncedAccountRecorder()
        let coordinator = PushWakeCoordinator(
            settingsProvider: {
                PushRelaySettings(
                    isEnabled: false,
                    mode: .userHostedRelay,
                    endpointURLString: "https://relay.example.com/push",
                    enabledAccountIDs: [Self.workAccount.id]
                )
            },
            backendsProvider: { [MockBackend(account: Self.workAccount)] },
            refreshBackends: { backends in
                await recorder.record(backends.map(\.account.id))
                return nil
            }
        )

        let result = await coordinator.handleWake(
            PushWakePayload(accountID: Self.workAccount.id, stateToken: "s1", eventKind: .newMail)
        )
        #expect(result == .ignoredDisabled)
        #expect(await recorder.syncedAccountIDs().isEmpty)
    }

    @Test("ignores wakes for accounts that are not opted in")
    func ignoresNonOptedInAccount() async {
        let recorder = SyncedAccountRecorder()
        let coordinator = PushWakeCoordinator(
            settingsProvider: {
                PushRelaySettings(
                    isEnabled: true,
                    mode: .userHostedRelay,
                    endpointURLString: "https://relay.example.com/push",
                    enabledAccountIDs: [Self.workAccount.id]
                )
            },
            backendsProvider: {
                [MockBackend(account: Self.workAccount), MockBackend(account: Self.personalAccount)]
            },
            refreshBackends: { backends in
                await recorder.record(backends.map(\.account.id))
                return nil
            }
        )

        let result = await coordinator.handleWake(
            PushWakePayload(accountID: Self.personalAccount.id, stateToken: nil, eventKind: .mailboxChanged)
        )
        #expect(result == .ignoredAccountNotOptedIn(accountID: Self.personalAccount.id))
        #expect(await recorder.syncedAccountIDs().isEmpty)
    }

    @Test("syncs only the targeted opted-in account on valid wake")
    func syncsOnlyTargetedOptedInAccount() async {
        let recorder = SyncedAccountRecorder()
        let coordinator = PushWakeCoordinator(
            settingsProvider: {
                PushRelaySettings(
                    isEnabled: true,
                    mode: .userHostedRelay,
                    endpointURLString: "https://relay.example.com/push",
                    enabledAccountIDs: [Self.workAccount.id, Self.personalAccount.id]
                )
            },
            backendsProvider: {
                [MockBackend(account: Self.workAccount), MockBackend(account: Self.personalAccount)]
            },
            refreshBackends: { backends in
                await recorder.record(backends.map(\.account.id))
                return nil
            }
        )

        let userInfo: [AnyHashable: Any] = [
            "aps": ["content-available": 1],
            "brev": [
                "accountID": Self.workAccount.id,
                "stateToken": "modseq-99",
                "eventKind": "new_mail"
            ]
        ]
        let result = await coordinator.handleRemoteNotificationUserInfo(userInfo)
        #expect(result == .synced(accountID: Self.workAccount.id))
        #expect(await recorder.syncedAccountIDs() == [[Self.workAccount.id]])
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
                    enabledAccountIDs: [Self.workAccount.id]
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
            }
        )

        let result = await coordinator.handleWake(
            PushWakePayload(accountID: Self.workAccount.id, stateToken: "jmap-state-7", eventKind: .mailboxChanged)
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
                    enabledAccountIDs: [Self.workAccount.id]
                )
            },
            backendsProvider: { [MockBackend(account: Self.workAccount)] },
            refreshBackends: { backends in
                await recorder.record(backends.map(\.account.id))
                return nil
            }
        )

        let result = await coordinator.handleRemoteNotificationUserInfo(["aps": ["content-available": 1]])
        #expect(result == .ignoredInvalidPayload)
        #expect(await recorder.syncedAccountIDs().isEmpty)
    }

    @Test("reports sync failures cleanly")
    func reportsSyncFailure() async {
        let coordinator = PushWakeCoordinator(
            settingsProvider: {
                PushRelaySettings(
                    isEnabled: true,
                    mode: .userHostedRelay,
                    endpointURLString: "https://relay.example.com/push",
                    enabledAccountIDs: [Self.workAccount.id]
                )
            },
            backendsProvider: { [MockBackend(account: Self.workAccount)] },
            refreshBackends: { _ in "IMAP connection timed out" }
        )

        let result = await coordinator.handleWake(
            PushWakePayload(accountID: Self.workAccount.id, stateToken: nil, eventKind: .newMail)
        )
        #expect(result == .failed(accountID: Self.workAccount.id, message: "IMAP connection timed out"))
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
