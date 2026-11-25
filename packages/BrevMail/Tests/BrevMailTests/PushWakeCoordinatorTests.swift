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
            refreshBackends: { _ in
                await cacheBox.setHeaders([freshArrival, cachedRecent, olderUncachedUnread])
                return nil
            },
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

    @Test("cold IMAP wake alerts on delayed newly delivered message with higher UID and older Date header")
    func coldIMAPDelayedDeliveryWithHigherUIDAndOlderDateAlerts() async {
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox, unreadCount: 2, totalCount: 2)
        let cachedNewest = MessageHeader(
            id: "INBOX:100",
            threadID: "thread-100",
            folderID: inbox.id,
            from: Correspondent(name: "Alice", email: "alice@example.org"),
            to: [Correspondent(email: "work@example.org")],
            subject: "Cached newest message",
            snippet: "UID 100 at 10:00",
            date: Date(timeIntervalSince1970: 1_750_003_600),
            isRead: false
        )
        // Delayed delivery: UID 101 > cached max UID 100, yet Date header is 30 minutes OLDER than UID 100.
        let delayedArrival = MessageHeader(
            id: "INBOX:101",
            threadID: "thread-101",
            folderID: inbox.id,
            from: Correspondent(name: "Greylisted Sender", email: "delayed@example.org"),
            to: [Correspondent(email: "work@example.org")],
            subject: "Delayed delivery",
            snippet: "Arrived late with older Date header",
            date: Date(timeIntervalSince1970: 1_750_001_800),
            isRead: false
        )
        // Older uncached message (UID 50 < 100, older Date): must NOT alert.
        let olderUncachedIMAP = MessageHeader(
            id: "INBOX:50",
            threadID: "thread-50",
            folderID: inbox.id,
            from: Correspondent(name: "Archive", email: "old@example.org"),
            to: [Correspondent(email: "work@example.org")],
            subject: "Old IMAP message",
            snippet: "UID 50 below max cached UID",
            date: Date(timeIntervalSince1970: 1_749_000_000),
            isRead: false
        )

        let backend = MockBackend(
            account: Self.workAccount,
            extendedCapabilities: [.cachedMessageHeaders],
            folders: [inbox],
            messagesByFolder: [inbox.id: [cachedNewest, delayedArrival, olderUncachedIMAP]]
        )
        let cacheBox = CachedHeaderBox(headers: [cachedNewest])
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
                await cacheBox.setHeaders([cachedNewest, delayedArrival, olderUncachedIMAP])
                return nil
            },
            deliverNotification: { arrived in
                deliveredMessages.append(arrived)
            }
        )

        let result = await coordinator.handleWake(
            PushWakePayload(accountID: Self.workOpaqueToken, stateToken: "uid-101", eventKind: .newMail)
        )
        #expect(result == .synced(accountID: Self.workAccount.id))
        #expect(result.fetchOutcome == .newData)
        // Higher IMAP UID `INBOX:101` alerts despite older Date; lower UID `INBOX:50` does NOT alert.
        #expect(deliveredMessages.map(\.messageID) == [delayedArrival.id])
    }

    @Test("mailbox_changed wake reports newData on flag-only mutation with zero alerts and noData when unchanged")
    func mailboxChangedFlagMutationReportsNewDataWithoutAlerts() async throws {
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox, unreadCount: 1, totalCount: 1)
        let unreadMessage = MessageHeader(
            id: "INBOX:200",
            threadID: "thread-200",
            folderID: inbox.id,
            from: Correspondent(name: "Alice", email: "alice@example.org"),
            to: [Correspondent(email: "work@example.org")],
            subject: "Flag mutation test",
            snippet: "Marked read remotely",
            date: Date(timeIntervalSince1970: 1_750_005_000),
            isRead: false
        )

        let backend = MockBackend(
            account: Self.workAccount,
            extendedCapabilities: [.cachedMessageHeaders],
            folders: [inbox],
            messagesByFolder: [inbox.id: [unreadMessage]]
        )

        var deliveredMessages: [PushWakeArrivedMessage] = []
        var enabledNotifications = NotificationSettings.defaults
        enabledNotifications.notificationsEnabled = true
        let notificationSnapshot = enabledNotifications
        var markReadDuringRefresh = true

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
                if await MainActor.run(body: { markReadDuringRefresh }) {
                    try? await backend.setRead(true, for: [unreadMessage.id])
                }
                return nil
            },
            deliverNotification: { arrived in
                deliveredMessages.append(arrived)
            }
        )

        let flagWake = PushWakePayload(
            accountID: Self.workOpaqueToken,
            stateToken: "modseq-500",
            eventKind: .mailboxChanged
        )

        // 1. Flag-only change (marked read) MUST report `.newData` with 0 arrival alerts.
        let mutatedResult = await coordinator.handleWake(flagWake)
        #expect(mutatedResult == .synced(accountID: Self.workAccount.id))
        #expect(mutatedResult.fetchOutcome == .newData)
        #expect(deliveredMessages.isEmpty)

        // 2. Subsequent unchanged refresh MUST report `.noData` with 0 alerts.
        markReadDuringRefresh = false
        let unchangedResult = await coordinator.handleWake(flagWake)
        #expect(unchangedResult == .syncedNoNewData(accountID: Self.workAccount.id))
        #expect(unchangedResult.fetchOutcome == .noData)
        #expect(deliveredMessages.isEmpty)
    }

    @Test(
        "paginated 60-message cached Inbox catches off-page flag change with zero enumerateMessages calls and reports noData when unchanged"
    )
    func paginatedCachedInboxCatchesOffPageFlagChangeWithoutLiveFetch() async {
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox, unreadCount: 60, totalCount: 60)
        // Build 60 cached messages (UIDs 1..60); UID 5 (off-page past top 50) has a newer Date than UID 11 (50th),
        // and UID 10 (off-page) will be marked read during wake 1.
        let baseDate = Date(timeIntervalSince1970: 1_750_000_000)
        var initialCached: [MessageHeader] = (1 ... 60).map { uid in
            let offsetSeconds: TimeInterval = uid == 5 ? 45 * 60 : TimeInterval(uid * 60)
            return MessageHeader(
                id: "INBOX:\(uid)",
                threadID: "thread-\(uid)",
                folderID: inbox.id,
                from: Correspondent(name: "Sender \(uid)", email: "sender\(uid)@example.org"),
                to: [Correspondent(email: "work@example.org")],
                subject: "Message \(uid)",
                snippet: "Body \(uid)",
                date: baseDate.addingTimeInterval(offsetSeconds),
                isRead: false
            )
        }
        initialCached.sort { $0.date > $1.date }

        let cacheBox = CachedHeaderBox(headers: initialCached)
        let enumerateCounter = CallCounter()
        let backend = MockBackend(
            account: Self.workAccount,
            extendedCapabilities: [.cachedMessageHeaders],
            folders: [inbox],
            messagesByFolder: [inbox.id: Array(initialCached.prefix(50))]
        )
        backend.cachedMessageHeadersHandler = { _, _ in
            await cacheBox.currentHeaders()
        }
        backend.messagesHandler = { _, _ in
            await enumerateCounter.increment()
            return (Array(initialCached.prefix(50)), "page-2")
        }

        var deliveredMessages: [PushWakeArrivedMessage] = []
        var enabledNotifications = NotificationSettings.defaults
        enabledNotifications.notificationsEnabled = true
        let notificationSnapshot = enabledNotifications
        var mutateOffPageUID10 = true

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
                if await MainActor.run(body: { mutateOffPageUID10 }) {
                    var updated = await cacheBox.currentHeaders()
                    if let idx = updated.firstIndex(where: { $0.id == "INBOX:10" }) {
                        updated[idx].isRead = true
                    }
                    await cacheBox.setHeaders(updated)
                }
                return nil
            },
            deliverNotification: { arrived in
                deliveredMessages.append(arrived)
            }
        )

        let wakePayload = PushWakePayload(
            accountID: Self.workOpaqueToken,
            stateToken: "condstore-99",
            eventKind: .mailboxChanged
        )

        // 1. Off-page UID 10 marked read -> `.newData`, 0 alerts, and 0 live `enumerateMessages` calls.
        let mutated = await coordinator.handleWake(wakePayload)
        #expect(mutated == .synced(accountID: Self.workAccount.id))
        #expect(mutated.fetchOutcome == .newData)
        #expect(deliveredMessages.isEmpty)
        #expect(await enumerateCounter.count() == 0)

        // 2. Unchanged 60-message cached Inbox -> `.noData` (even with off-page newer Date), 0 alerts, 0 live calls.
        mutateOffPageUID10 = false
        let unchanged = await coordinator.handleWake(wakePayload)
        #expect(unchanged == .syncedNoNewData(accountID: Self.workAccount.id))
        #expect(unchanged.fetchOutcome == .noData)
        #expect(deliveredMessages.isEmpty)
        #expect(await enumerateCounter.count() == 0)
    }

    @Test("delayed Gmail delivery with older Date header alerts via freshDeliveryMessageIDs while uncached backfill does not")
    func delayedGmailDeliveryAlertsViaFreshDeliveryProvider() async {
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox, unreadCount: 3, totalCount: 3)
        let cachedNewest = MessageHeader(
            id: "18f0000000000001",
            threadID: "t-1",
            folderID: inbox.id,
            from: Correspondent(name: "Alice", email: "alice@example.org"),
            to: [Correspondent(email: "work@example.org")],
            subject: "Cached newest Gmail message",
            snippet: "Cached at 10:00",
            date: Date(timeIntervalSince1970: 1_750_003_600),
            isRead: false
        )
        // Delayed Gmail delivery: non-IMAP opaque hex ID with Date header 1 hour OLDER than `cachedNewest`,
        // positively identified by Gmail History delta (`freshDeliveryMessageIDs(since:)`).
        let delayedGmailFresh = MessageHeader(
            id: "18f0000000000002",
            threadID: "t-2",
            folderID: inbox.id,
            from: Correspondent(name: "Delayed Sender", email: "delayed@example.org"),
            to: [Correspondent(email: "work@example.org")],
            subject: "Delayed Gmail delivery",
            snippet: "Older Date header, fresh History delta",
            date: Date(timeIntervalSince1970: 1_750_000_000),
            isRead: false
        )
        // Older uncached unread Gmail message NOT in `freshDeliveryMessageIDs(since:)`: must NOT alert.
        let uncachedBackfill = MessageHeader(
            id: "18f0000000000003",
            threadID: "t-3",
            folderID: inbox.id,
            from: Correspondent(name: "Newsletter", email: "news@example.org"),
            to: [Correspondent(email: "work@example.org")],
            subject: "Older uncached unread Gmail message",
            snippet: "Not a fresh delivery",
            date: Date(timeIntervalSince1970: 1_749_000_000),
            isRead: false
        )

        let cacheBox = CachedHeaderBox(headers: [cachedNewest])
        let enumerateCounter = CallCounter()
        let backend = MockBackend(
            account: Self.workAccount,
            extendedCapabilities: [.cachedMessageHeaders],
            folders: [inbox],
            messagesByFolder: [inbox.id: [cachedNewest, delayedGmailFresh, uncachedBackfill]]
        )
        backend.cachedMessageHeadersHandler = { _, _ in
            await cacheBox.currentHeaders()
        }
        backend.messagesHandler = { _, _ in
            await enumerateCounter.increment()
            return ([cachedNewest, delayedGmailFresh, uncachedBackfill], nil)
        }
        let wakeTime = Date(timeIntervalSince1970: 1_750_004_000)
        backend.freshDeliveryMessageIDsHandler = { since in
            since <= wakeTime ? [delayedGmailFresh.id] : []
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
                await cacheBox.setHeaders([cachedNewest, delayedGmailFresh, uncachedBackfill])
                return nil
            },
            deliverNotification: { arrived in
                deliveredMessages.append(arrived)
            },
            now: { wakeTime }
        )

        let result = await coordinator.handleWake(
            PushWakePayload(accountID: Self.workOpaqueToken, stateToken: "hist-77", eventKind: .newMail)
        )
        #expect(result == .synced(accountID: Self.workAccount.id))
        #expect(result.fetchOutcome == .newData)
        #expect(deliveredMessages.map(\.messageID) == [delayedGmailFresh.id])
        #expect(await enumerateCounter.count() == 0)
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
        session.configurePushRelayVerificationForTesting(
            defaults: defaults,
            secretStore: secretStore,
            client: client,
            now: { verifiedAt }
        )

        // 1. Early challenge for `jmap-sub-early` arrives BEFORE `jmap-sub-early` is persisted:
        // buffered in memory with zero network calls yet; `jmap-sub-pending` stays untouched.
        await session.handleJMAPVerificationChallenge(
            subscriptionID: "jmap-sub-early",
            verificationCode: "early-code-77"
        )
        #expect(await transport.recordedRequests().isEmpty)
        #expect(store.pushRelaySettings().activeRegistration?.state == .pendingVerification)

        // 2. Matching challenge for `jmap-sub-pending` verifies immediately and transitions to `.active`.
        await session.handleJMAPVerificationChallenge(
            subscriptionID: "jmap-sub-pending",
            verificationCode: "challenge-42"
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

        // 3. Persist `jmap-sub-early` as `.pendingVerification` WITHOUT calling any helper directly:
        // `store.save(...)` posts `.brevPushRelaySettingsDidChange`, triggering `AppSession`'s real
        // observer to consume the buffered challenge and transition `jmap-sub-early` to `.active`.
        var earlyPending = updated
        earlyPending.activeRegistration = ActivePushRelayRegistration(
            mode: .jmapWebPush,
            endpointURLString: "https://jmap.example.com/api/",
            webPushDeliveryURLString: "https://webpush.example.com/push/dev1",
            subscriptionID: "jmap-sub-early",
            state: .pendingVerification
        )
        store.save(earlyPending)

        for _ in 0 ..< 100 {
            if store.pushRelaySettings().activeRegistration?.state == .active {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

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

private actor CallCounter {
    private var total = 0

    func increment() {
        total += 1
    }

    func count() -> Int {
        total
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
