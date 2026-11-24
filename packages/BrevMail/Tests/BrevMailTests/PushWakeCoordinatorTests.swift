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

    @Test("handles RFC 8620 StateChange wake payloads by syncing only opted-in mapped accounts")
    func handlesRFC8620StateChangeWake() async {
        let recorder = SyncedAccountRecorder()
        let coordinator = PushWakeCoordinator(
            settingsProvider: {
                PushRelaySettings(
                    isEnabled: true,
                    mode: .jmapWebPush,
                    endpointURLString: "https://jmap.example.com/api/",
                    webPushDeliveryURLString: "https://webpush.example.com/push/dev1",
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
            notifyArrivedMail: { _, _ in }
        )

        let stateChangeJSON = Data("""
        {
          "@type": "StateChange",
          "changed": {
            "\(Self.workOpaqueToken)": { "Email": "e-100" },
            "\(Self.personalOpaqueToken)": { "Email": "e-200" }
          }
        }
        """.utf8)
        let result = await coordinator.handleWakeData(stateChangeJSON)
        #expect(result == .synced(accountID: Self.workAccount.id))
        #expect(await recorder.syncedAccountIDs() == [[Self.workAccount.id]])
    }

    @Test("scene-less arrival diff notifies only newly arrived unread Inbox messages and never re-notifies existing unread mail")
    func sceneLessArrivalDiffOnlyNotifiesNewlyArrivedUnread() async throws {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox, unreadCount: 1, totalCount: 1)
        let staging = Folder(id: "archive", name: "Archive", role: .archive, unreadCount: 1, totalCount: 2)
        let oldUnread = MessageHeader(
            id: "msg-existing-unread",
            threadID: "thread-existing",
            folderID: inbox.id,
            from: Correspondent(name: "Alice", email: "alice@example.org"),
            to: [Correspondent(email: "work@example.org")],
            subject: "Already in Inbox before wake",
            snippet: "Old unread message",
            date: Date(timeIntervalSince1970: 1_750_000_000),
            isRead: false
        )
        let arrivingUnread = MessageHeader(
            id: "msg-newly-arrived-unread",
            threadID: "thread-new-unread",
            folderID: staging.id,
            from: Correspondent(name: "Bob", email: "bob@example.org"),
            to: [Correspondent(email: "work@example.org")],
            subject: "Fresh arrival",
            snippet: "Arrived during wake refresh",
            date: Date(timeIntervalSince1970: 1_750_000_100),
            isRead: false
        )
        let arrivingRead = MessageHeader(
            id: "msg-newly-arrived-read",
            threadID: "thread-new-read",
            folderID: staging.id,
            from: Correspondent(name: "Carol", email: "carol@example.org"),
            to: [Correspondent(email: "work@example.org")],
            subject: "Already read arrival",
            snippet: "Should not notify",
            date: Date(timeIntervalSince1970: 1_750_000_200),
            isRead: true
        )

        let backend = MockBackend(
            account: Self.workAccount,
            extendedCapabilities: [.cachedMessageHeaders],
            folders: [inbox, staging],
            messagesByFolder: [
                inbox.id: [oldUnread],
                staging.id: [arrivingUnread, arrivingRead]
            ]
        )

        var shouldDeliverNewMailOnRefresh = false
        var deliveredMessages: [PushWakeArrivedMessage] = []
        var enabledNotifications = NotificationSettings.defaults
        enabledNotifications.notificationsEnabled = true
        enabledNotifications.showPreviews = true
        let notificationSettingsSnapshot = enabledNotifications

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
            notificationSettingsProvider: { notificationSettingsSnapshot },
            backendsProvider: { [backend] },
            refreshBackends: { _ in
                if await MainActor.run(body: { shouldDeliverNewMailOnRefresh }) {
                    try? await backend.move(messageIDs: [arrivingUnread.id, arrivingRead.id], to: inbox)
                }
                return nil
            },
            deliverNotification: { arrived in
                deliveredMessages.append(arrived)
            }
        )

        let wakePayload = PushWakePayload(accountID: Self.workOpaqueToken, stateToken: "s1", eventKind: .newMail)

        // 1. Wake with no newly arrived messages MUST NOT re-notify `oldUnread` and reports `.noData`.
        let wake1 = await coordinator.handleWake(wakePayload)
        #expect(wake1 == .syncedNoNewData(accountID: Self.workAccount.id))
        #expect(wake1.fetchOutcome == .noData)
        #expect(deliveredMessages.isEmpty)

        // 2. Wake where `arrivingUnread` and `arrivingRead` arrive notifies ONLY `arrivingUnread` and reports `.newData`.
        shouldDeliverNewMailOnRefresh = true
        let wake2 = await coordinator.handleWake(wakePayload)
        #expect(wake2 == .synced(accountID: Self.workAccount.id))
        #expect(wake2.fetchOutcome == .newData)
        #expect(deliveredMessages.map(\.messageID) == [arrivingUnread.id])

        // 3. Subsequent wake with no additional arrivals MUST NOT re-notify and reports `.noData`.
        shouldDeliverNewMailOnRefresh = false
        let wake3 = await coordinator.handleWake(wakePayload)
        #expect(wake3 == .syncedNoNewData(accountID: Self.workAccount.id))
        #expect(wake3.fetchOutcome == .noData)
        #expect(deliveredMessages.map(\.messageID) == [arrivingUnread.id])
    }

    @Test("pre-refresh baseline reads local cache only so already-delivered remote mail triggers alert")
    func preRefreshBaselineUsesLocalCacheNotLiveServer() async {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox, unreadCount: 2, totalCount: 2)
        let cachedOldUnread = MessageHeader(
            id: "msg-cached-old",
            threadID: "thread-cached-old",
            folderID: inbox.id,
            from: Correspondent(name: "Alice", email: "alice@example.org"),
            to: [Correspondent(email: "work@example.org")],
            subject: "Already cached before wake",
            snippet: "Previously synced",
            date: Date(timeIntervalSince1970: 1_750_000_000),
            isRead: false
        )
        let remoteNewUnread = MessageHeader(
            id: "msg-remote-already-delivered",
            threadID: "thread-remote-new",
            folderID: inbox.id,
            from: Correspondent(name: "Dana", email: "dana@example.org"),
            to: [Correspondent(email: "work@example.org")],
            subject: "Already on remote server when wake starts",
            snippet: "Not in local cache yet",
            date: Date(timeIntervalSince1970: 1_750_000_500),
            isRead: false
        )

        // Remote server (enumerateMessages) ALREADY holds `remoteNewUnread` when handleWake starts,
        // while the local header cache (`cachedMessageHeaders`) only holds `cachedOldUnread`.
        let backend = MockBackend(
            account: Self.workAccount,
            extendedCapabilities: [.cachedMessageHeaders],
            folders: [inbox],
            messagesByFolder: [inbox.id: [remoteNewUnread, cachedOldUnread]]
        )
        let cacheBox = CachedHeaderBox(headers: [cachedOldUnread])
        backend.cachedMessageHeadersHandler = { _, _ in
            await cacheBox.currentHeaders()
        }

        var deliveredMessages: [PushWakeArrivedMessage] = []
        var enabledNotifications = NotificationSettings.defaults
        enabledNotifications.notificationsEnabled = true
        let notificationSnapshot = enabledNotifications

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
            notificationSettingsProvider: { notificationSnapshot },
            backendsProvider: { [backend] },
            refreshBackends: { _ in
                // Refresh pulls `remoteNewUnread` into the local cache.
                await cacheBox.setHeaders([remoteNewUnread, cachedOldUnread])
                return nil
            },
            deliverNotification: { arrived in
                deliveredMessages.append(arrived)
            }
        )

        let wakePayload = PushWakePayload(accountID: Self.workOpaqueToken, stateToken: "s2", eventKind: .newMail)

        // Wake 1 MUST fire the alert for `remoteNewUnread` even though the live server already had it at wake start.
        let firstWake = await coordinator.handleWake(wakePayload)
        #expect(firstWake == .synced(accountID: Self.workAccount.id))
        #expect(firstWake.fetchOutcome == .newData)
        #expect(deliveredMessages.map(\.messageID) == [remoteNewUnread.id])

        // Wake 2 sees `remoteNewUnread` in the local cache and MUST NOT re-notify it.
        let secondWake = await coordinator.handleWake(wakePayload)
        #expect(secondWake == .syncedNoNewData(accountID: Self.workAccount.id))
        #expect(secondWake.fetchOutcome == .noData)
        #expect(deliveredMessages.map(\.messageID) == [remoteNewUnread.id])
    }

    @Test("older uncached unread Inbox message below pre-refresh watermark never alerts while fresh arrival does")
    func olderUncachedUnreadMessageDoesNotAlert() async {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox, unreadCount: 3, totalCount: 3)
        let cachedRecent = MessageHeader(
            id: "msg-cached-watermark",
            threadID: "thread-cached",
            folderID: inbox.id,
            from: Correspondent(name: "Alice", email: "alice@example.org"),
            to: [Correspondent(email: "work@example.org")],
            subject: "Newest cached before wake",
            snippet: "Watermark message",
            date: Date(timeIntervalSince1970: 1_750_000_000),
            isRead: false
        )
        let freshArrival = MessageHeader(
            id: "msg-fresh-arrival",
            threadID: "thread-fresh",
            folderID: inbox.id,
            from: Correspondent(name: "Bob", email: "bob@example.org"),
            to: [Correspondent(email: "work@example.org")],
            subject: "Genuine new mail",
            snippet: "Arrived after watermark",
            date: Date(timeIntervalSince1970: 1_750_000_600),
            isRead: false
        )
        let olderUncachedUnread = MessageHeader(
            id: "msg-old-uncached-unread",
            threadID: "thread-old-uncached",
            folderID: inbox.id,
            from: Correspondent(name: "Legacy", email: "legacy@example.org"),
            to: [Correspondent(email: "work@example.org")],
            subject: "Old unread outside initial 250-message cache",
            snippet: "Must NOT alert",
            date: Date(timeIntervalSince1970: 1_740_000_000),
            isRead: false
        )

        let backend = MockBackend(
            account: Self.workAccount,
            extendedCapabilities: [.cachedMessageHeaders],
            folders: [inbox],
            messagesByFolder: [inbox.id: [freshArrival, cachedRecent, olderUncachedUnread]]
        )
        let cacheBox = CachedHeaderBox(headers: [cachedRecent])
        backend.cachedMessageHeadersHandler = { _, _ in
            await cacheBox.currentHeaders()
        }

        var deliveredMessages: [PushWakeArrivedMessage] = []
        var enabledNotifications = NotificationSettings.defaults
        enabledNotifications.notificationsEnabled = true
        let notificationSnapshot = enabledNotifications

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
            notificationSettingsProvider: { notificationSnapshot },
            backendsProvider: { [backend] },
            refreshBackends: { _ in nil },
            deliverNotification: { arrived in
                deliveredMessages.append(arrived)
            }
        )

        let result = await coordinator.handleWake(
            PushWakePayload(accountID: Self.workOpaqueToken, stateToken: "s3", eventKind: .newMail)
        )
        #expect(result == .synced(accountID: Self.workAccount.id))
        #expect(result.fetchOutcome == .newData)
        // ONLY `freshArrival` alerts; `olderUncachedUnread` is suppressed by the pre-refresh date watermark.
        #expect(deliveredMessages.map(\.messageID) == [freshArrival.id])
    }

    @Test("multi-account wake continues refreshing and alerting remaining accounts when an earlier account fails")
    func multiAccountWakeContinuesPastFirstAccountFailure() async {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox, unreadCount: 1, totalCount: 1)
        let personalNewUnread = MessageHeader(
            id: "msg-personal-new",
            threadID: "thread-personal-new",
            folderID: inbox.id,
            from: Correspondent(name: "Eva", email: "eva@example.org"),
            to: [Correspondent(email: "personal@example.org")],
            subject: "Personal arrival",
            snippet: "Arrived while work account timed out",
            date: Date(timeIntervalSince1970: 1_750_000_900),
            isRead: false
        )

        let workBackend = MockBackend(
            account: Self.workAccount,
            extendedCapabilities: [.cachedMessageHeaders],
            folders: [inbox],
            messagesByFolder: [inbox.id: []]
        )
        let personalBackend = MockBackend(
            account: Self.personalAccount,
            extendedCapabilities: [.cachedMessageHeaders],
            folders: [inbox],
            messagesByFolder: [inbox.id: [personalNewUnread]]
        )
        let personalCache = CachedHeaderBox(headers: [])
        personalBackend.cachedMessageHeadersHandler = { _, _ in
            await personalCache.currentHeaders()
        }

        let recorder = SyncedAccountRecorder()
        var deliveredMessages: [PushWakeArrivedMessage] = []
        var enabledNotifications = NotificationSettings.defaults
        enabledNotifications.notificationsEnabled = true
        let notificationSnapshot = enabledNotifications

        // Use opaque tokens ordered so the failing account runs first ("acct-aaa-failing" < "acct-zzz-healthy").
        let failingAccountID = Self.workAccount.id
        let failingToken = "acct-aaa-failing"
        let healthyToken = "acct-zzz-healthy"
        let orderedCoordinator = PushWakeCoordinator(
            settingsProvider: {
                PushRelaySettings(
                    isEnabled: true,
                    mode: .jmapWebPush,
                    endpointURLString: "https://jmap.example.com/api/",
                    webPushDeliveryURLString: "https://webpush.example.com/push/dev1",
                    enabledAccountIDs: [Self.workAccount.id, Self.personalAccount.id],
                    opaqueAccountTokens: [
                        Self.workAccount.id: failingToken,
                        Self.personalAccount.id: healthyToken
                    ]
                )
            },
            notificationSettingsProvider: { notificationSnapshot },
            backendsProvider: { [workBackend, personalBackend] },
            refreshBackends: { backends in
                let ids = backends.map(\.account.id)
                await recorder.record(ids)
                if ids.contains(failingAccountID) {
                    return "Work account timed out"
                }
                await personalCache.setHeaders([personalNewUnread])
                return nil
            },
            deliverNotification: { arrived in
                deliveredMessages.append(arrived)
            },
            now: { Date(timeIntervalSince1970: 1_750_001_000) }
        )

        let stateChangeJSON = Data("""
        {
          "@type": "StateChange",
          "changed": {
            "\(failingToken)": { "Email": "e-1" },
            "\(healthyToken)": { "Email": "e-2" }
          }
        }
        """.utf8)
        let result = await orderedCoordinator.handleWakeData(stateChangeJSON)

        // First account failed, yet second account STILL refreshed and posted its arrival alert,
        // so the mixed wake reports `.synced` (`.newData`) rather than `.failed`.
        #expect(result == .synced(accountID: Self.personalAccount.id))
        #expect(result.fetchOutcome == .newData)
        #expect(await recorder.syncedAccountIDs() == [[Self.workAccount.id], [Self.personalAccount.id]])
        #expect(deliveredMessages.map(\.messageID) == [personalNewUnread.id])
        #expect(deliveredMessages.map(\.accountID) == [Self.personalAccount.id])

        // Second mixed wake where `work` fails and `personal` succeeds with NO new mail reports `.noData`.
        let secondMixed = await orderedCoordinator.handleWakeData(stateChangeJSON)
        #expect(secondMixed == .syncedNoNewData(accountID: Self.personalAccount.id))
        #expect(secondMixed.fetchOutcome == .noData)
    }

    @Test("AppSession JMAP PushVerification callback verifies matching pending subscription and buffers early challenges")
    func appSessionHandlesJMAPVerificationChallenge() async throws {
        let suite = "AppSessionJMAPVerify-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsPersistenceStore(defaults: defaults)
        let secretStore = InMemoryPushRelaySecretStore()
        try secretStore.saveBearerToken("jmap-origin-token", forOrigin: "https://jmap.example.com")

        let pendingSettings = PushRelaySettings(
            isEnabled: true,
            mode: .jmapWebPush,
            endpointURLString: "https://jmap.example.com/api/",
            webPushDeliveryURLString: "https://webpush.example.com/push/dev1",
            enabledAccountIDs: [Self.workAccount.id],
            opaqueAccountTokens: [Self.workAccount.id: Self.workOpaqueToken],
            deviceClientID: "brev-dev-1",
            activeRegistration: ActivePushRelayRegistration(
                mode: .jmapWebPush,
                endpointURLString: "https://jmap.example.com/api/",
                webPushDeliveryURLString: "https://webpush.example.com/push/dev1",
                subscriptionID: "jmap-sub-pending",
                state: .pendingVerification
            )
        )
        store.save(pendingSettings)

        let verifyOK = Data("""
        {"methodResponses":[["PushSubscription/set",{"updated":{"jmap-sub-pending":null}},"c0"]]}
        """.utf8)
        let verifyEarlyOK = Data("""
        {"methodResponses":[["PushSubscription/set",{"updated":{"jmap-sub-early":null}},"c0"]]}
        """.utf8)
        let transport = QueuedPushTransport(responses: [(verifyOK, 200), (verifyEarlyOK, 200)])
        let client = PushRelayClient(transport: transport)
        let session = AppSession(accountStore: InMemoryAccountStore(), tokenStore: StubPushTestTokenStore())
        #expect(session.pushWakeCoordinator.onJMAPVerificationChallenge != nil)
        let verifiedAt = Date(timeIntervalSince1970: 1_800_123_456)

        // 1. Early challenge for `jmap-sub-early` arrives BEFORE `jmap-sub-early` is persisted:
        // buffered in memory with zero network calls yet; `jmap-sub-pending` stays untouched.
        await session.handleJMAPVerificationChallenge(
            subscriptionID: "jmap-sub-early",
            verificationCode: "early-code-77",
            settingsStore: store,
            secretStore: secretStore,
            client: client,
            now: { verifiedAt }
        )
        #expect(await transport.recordedRequests().isEmpty)
        #expect(store.pushRelaySettings().activeRegistration?.state == .pendingVerification)

        // 2. Matching challenge for `jmap-sub-pending` verifies immediately and transitions to `.active`.
        await session.handleJMAPVerificationChallenge(
            subscriptionID: "jmap-sub-pending",
            verificationCode: "challenge-42",
            settingsStore: store,
            secretStore: secretStore,
            client: client,
            now: { verifiedAt }
        )
        let afterFirst = await transport.recordedRequests()
        #expect(afterFirst.count == 1)
        #expect(afterFirst[0].value(forHTTPHeaderField: "Authorization") == "Bearer jmap-origin-token")
        let body = try String(decoding: #require(afterFirst[0].httpBody), as: UTF8.self)
        #expect(body.contains("\"verificationCode\":\"challenge-42\""))
        #expect(body.contains("jmap-sub-pending"))

        let updated = store.pushRelaySettings()
        #expect(updated.activeRegistration?.state == .active)
        #expect(updated.activeRegistration?.registeredAt == verifiedAt)
        #expect(updated.lastRegistrationError == nil)

        // 3. Once `jmap-sub-early` is persisted as `.pendingVerification`, consuming buffered
        // challenges immediately verifies it with `early-code-77` and transitions it to `.active`.
        var earlyPending = updated
        earlyPending.activeRegistration = ActivePushRelayRegistration(
            mode: .jmapWebPush,
            endpointURLString: "https://jmap.example.com/api/",
            webPushDeliveryURLString: "https://webpush.example.com/push/dev1",
            subscriptionID: "jmap-sub-early",
            state: .pendingVerification
        )
        store.save(earlyPending)
        await session.consumeBufferedJMAPVerificationChallengeIfNeeded(
            settingsStore: store,
            secretStore: secretStore,
            client: client,
            now: { verifiedAt.addingTimeInterval(5) }
        )

        let afterSecond = await transport.recordedRequests()
        #expect(afterSecond.count == 2)
        let earlyBody = try String(decoding: #require(afterSecond[1].httpBody), as: UTF8.self)
        #expect(earlyBody.contains("\"verificationCode\":\"early-code-77\""))
        #expect(earlyBody.contains("jmap-sub-early"))
        #expect(store.pushRelaySettings().activeRegistration?.subscriptionID == "jmap-sub-early")
        #expect(store.pushRelaySettings().activeRegistration?.state == .active)
    }
}

private actor CachedHeaderBox {
    private var headers: [MessageHeader]

    init(headers: [MessageHeader]) {
        self.headers = headers
    }

    func currentHeaders() -> [MessageHeader] {
        headers
    }

    func setHeaders(_ updated: [MessageHeader]) {
        headers = updated
    }
}

private actor QueuedPushTransport: PushRelayHTTPTransport {
    private var responses: [(Data, Int)]
    private var requests: [URLRequest] = []

    init(responses: [(Data, Int)]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let next = responses.isEmpty ? (Data(), 200) : responses.removeFirst()
        let url = request.url ?? URL(string: "https://jmap.example.com/api/")!
        let http = HTTPURLResponse(
            url: url,
            statusCode: next.1,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (next.0, http)
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }
}

private actor StubPushTestTokenStore: TokenStore {
    private var tokens: [String: Token] = [:]

    func token(for accountID: String) -> Token? {
        tokens[accountID]
    }

    func setToken(_ token: Token, for accountID: String) {
        tokens[accountID] = token
    }

    func clearToken(for accountID: String) {
        tokens[accountID] = nil
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
