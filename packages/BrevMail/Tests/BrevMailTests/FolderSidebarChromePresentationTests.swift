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
import Testing

@Suite("Folder sidebar chrome presentation")
struct FolderSidebarChromePresentationTests {
    @Test("mailbox roles get theme-token tints; custom folders stay neutral")
    func roleTints() {
        #expect(FolderSidebarIconTint.tint(for: .inbox) == .accent)
        #expect(FolderSidebarIconTint.tint(for: .sent) == .accent)
        #expect(FolderSidebarIconTint.tint(for: .drafts) == .info)
        #expect(FolderSidebarIconTint.tint(for: .starred) == .warning)
        #expect(FolderSidebarIconTint.tint(for: .snoozed) == .warning)
        #expect(FolderSidebarIconTint.tint(for: .archive) == .success)
        #expect(FolderSidebarIconTint.tint(for: .spam) == .danger)
        #expect(FolderSidebarIconTint.tint(for: .trash) == .neutral)
        #expect(FolderSidebarIconTint.tint(for: .custom) == .neutral)
    }

    @Test("footer status says offline before anything else")
    func offlineWins() {
        let status = FolderSidebarSyncStatus(isOnline: false, isRefreshing: true, progress: (1, 4))
        #expect(status == .offline)
        #expect(status.symbolName == "wifi.slash")
    }

    @Test("footer status shows sync progress, then a refresh, then up to date")
    func syncingStates() {
        #expect(FolderSidebarSyncStatus(isOnline: true, isRefreshing: true, progress: (2, 5))
            == .syncing(completed: 2, total: 5))
        #expect(FolderSidebarSyncStatus(isOnline: true, isRefreshing: true, progress: nil) == .checking)
        #expect(FolderSidebarSyncStatus(isOnline: true, isRefreshing: false, progress: nil) == .upToDate)
        // A finished or empty progress report is not "syncing".
        #expect(FolderSidebarSyncStatus(isOnline: true, isRefreshing: false, progress: (5, 5)) == .upToDate)
        #expect(FolderSidebarSyncStatus(isOnline: true, isRefreshing: false, progress: (0, 0)) == .upToDate)
    }

    @Test("a sign-in or provider problem is never shown as up to date")
    func healthProblemsNeedAttention() {
        for state in [SyncHealthState.authenticationRequired, .providerError, .degraded] {
            #expect(FolderSidebarSyncStatus(isOnline: true, isRefreshing: false, progress: nil, health: state)
                == .needsAttention)
            #expect(FolderSidebarSyncStatus(isOnline: true, isRefreshing: true, progress: (1, 3), health: state)
                == .needsAttention)
        }
        // Offline still comes first, and healthy or busy states change nothing.
        #expect(FolderSidebarSyncStatus(isOnline: false, isRefreshing: false, progress: nil,
                                        health: .authenticationRequired) == .offline)
        for state in [SyncHealthState.healthy, .syncing, .indexing, .offline] {
            #expect(FolderSidebarSyncStatus(isOnline: true, isRefreshing: false, progress: nil, health: state)
                == .upToDate)
        }
        #expect(FolderSidebarSyncStatus.needsAttention.tint == .warning)
    }

    @Test("footer identity uses the first account's name, else its address")
    func footerIdentity() {
        let named = BrevAccount(id: "a", displayName: "Alex Chen", emailAddress: "alex@example.org")
        let unnamed = BrevAccount(id: "b", displayName: " ", emailAddress: "me@example.org")
        #expect(FolderSidebarFooterIdentity(accounts: [named, unnamed])
            == FolderSidebarFooterIdentity(name: "Alex Chen", initials: "AC"))
        #expect(FolderSidebarFooterIdentity(accounts: [unnamed])
            == FolderSidebarFooterIdentity(name: "me@example.org", initials: "M"))
        #expect(FolderSidebarFooterIdentity(accounts: []) == nil)
    }
}
