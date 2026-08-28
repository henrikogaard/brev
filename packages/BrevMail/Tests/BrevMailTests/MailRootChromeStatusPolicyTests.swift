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
import Foundation
import Testing

@Suite("MailRootChromeStatusPolicy")
struct MailRootChromeStatusPolicyTests {
    private let sourceID = MailSourceID(accountID: "acct", mailboxID: "mbox")

    @Test("sign-in required outranks offline")
    func signInRequiredOutranksOffline() {
        let health = AccountSyncHealth(
            sourceID: sourceID,
            state: .authenticationRequired,
            lastSuccessfulSyncAt: nil,
            lastErrorDescription: "Token expired.",
            indexStatus: .notBuilt,
            cacheSizeBytes: 0,
            pendingMutationCount: 0
        )

        let chrome = MailRootChromeStatusPolicy.resolve(
            rootStatus: MailRootStatus(message: "Load failed.", tone: .danger, actionTitle: "Try Again"),
            isOnline: false,
            importHealth: health,
            folderSyncProgress: nil
        )

        guard case .importProgress(let presentation) = chrome else {
            Issue.record("Expected import progress chrome, got \(String(describing: chrome))")
            return
        }
        #expect(presentation.title == "Sign-in required")
    }

    @Test("offline outranks root warning when online auth is not required")
    func offlineOutranksRootWarning() {
        let chrome = MailRootChromeStatusPolicy.resolve(
            rootStatus: MailRootStatus(message: "Couldn't refresh.", tone: .warning, actionTitle: "Retry"),
            isOnline: false,
            importHealth: nil,
            folderSyncProgress: nil
        )

        #expect(chrome == .offline)
    }

    @Test("root warning outranks import progress")
    func rootWarningOutranksImportProgress() {
        let health = AccountSyncHealth(
            sourceID: sourceID,
            state: .healthy,
            lastSuccessfulSyncAt: Date(),
            lastErrorDescription: nil,
            indexStatus: .notBuilt,
            cacheSizeBytes: 512,
            pendingMutationCount: 0
        )
        let progress = MailSyncProgress(completed: 2, total: 10)

        let chrome = MailRootChromeStatusPolicy.resolve(
            rootStatus: MailRootStatus(message: "Couldn't refresh.", tone: .warning, actionTitle: "Retry"),
            isOnline: true,
            importHealth: health,
            folderSyncProgress: progress
        )

        guard case .rootStatus(let status) = chrome else {
            Issue.record("Expected root status chrome, got \(String(describing: chrome))")
            return
        }
        #expect(status.message == "Couldn't refresh.")
    }

    @Test("success root status is ignored so import progress can show")
    func successRootStatusIsIgnoredForRail() {
        let health = AccountSyncHealth(
            sourceID: sourceID,
            state: .healthy,
            lastSuccessfulSyncAt: Date(),
            lastErrorDescription: nil,
            indexStatus: .notBuilt,
            cacheSizeBytes: 512,
            pendingMutationCount: 0
        )
        let progress = MailSyncProgress(completed: 2, total: 10)

        let chrome = MailRootChromeStatusPolicy.resolve(
            rootStatus: MailRootStatus(message: "Draft saved.", tone: .success),
            isOnline: true,
            importHealth: health,
            folderSyncProgress: progress
        )

        guard case .importProgress(let presentation) = chrome else {
            Issue.record("Expected import progress chrome, got \(String(describing: chrome))")
            return
        }
        #expect(presentation.phase == .backfillContinuing)
    }

    @Test("idle online mailbox with no root status shows nothing")
    func idleOnlineMailboxShowsNothing() {
        let health = AccountSyncHealth(
            sourceID: sourceID,
            state: .healthy,
            lastSuccessfulSyncAt: Date(),
            lastErrorDescription: nil,
            indexStatus: .ready(messageCount: 3),
            cacheSizeBytes: 100,
            pendingMutationCount: 0
        )

        let chrome = MailRootChromeStatusPolicy.resolve(
            rootStatus: nil,
            isOnline: true,
            importHealth: health,
            folderSyncProgress: nil
        )

        #expect(chrome == nil)
    }
}
