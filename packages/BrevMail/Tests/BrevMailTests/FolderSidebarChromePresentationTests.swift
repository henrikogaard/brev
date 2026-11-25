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
import BrevDesign
@testable import BrevMail
import BrevThemes
import Testing

@Suite("Folder sidebar chrome presentation")
struct FolderSidebarChromePresentationTests {
    @Test("mailbox roles stay monochrome neutral so selection and unread counts carry hierarchy")
    func roleTints() {
        for role in FolderRole.allCases {
            #expect(FolderSidebarIconTint.tint(for: role) == .neutral)
        }
        let dark = BrevTheme.brevMonoDark
        #expect(FolderSidebarIconTint.macOSRowColor(isSelected: false, in: dark) == dark.textSecondary.color)
        #expect(FolderSidebarIconTint.macOSRowColor(isSelected: true, in: dark) == dark.textPrimary.color)
    }

    @Test("macOS 26 sidebar uses native floating Liquid Glass unless Reduce Transparency or older macOS")
    func surfacePolicy() {
        for mode in WindowTranslucencyMode.allCases {
            #expect(
                FolderSidebarSurfacePolicy.style(
                    isMacOS26OrLater: true,
                    reduceTransparency: false,
                    translucencyMode: mode
                ) == .nativeFloatingGlass
            )
            #expect(
                FolderSidebarSurfacePolicy.style(
                    isMacOS26OrLater: true,
                    reduceTransparency: true,
                    translucencyMode: mode
                ) == .themedSurface
            )
            #expect(
                FolderSidebarSurfacePolicy.style(
                    isMacOS26OrLater: false,
                    reduceTransparency: false,
                    translucencyMode: mode
                ) == .themedSurface
            )
        }
        #expect(FolderSidebarSurfacePolicy.usesSoftScrollEdgeEffect(isMacOS26OrLater: true, reduceTransparency: false))
        #expect(!FolderSidebarSurfacePolicy.usesSoftScrollEdgeEffect(isMacOS26OrLater: true, reduceTransparency: true))
        #expect(!FolderSidebarSurfacePolicy.usesSoftScrollEdgeEffect(isMacOS26OrLater: false, reduceTransparency: false))
    }

    @Test("macOS top profile switcher hides for single-profile workspaces and shows for multi-profile")
    func profileSwitcherVisibility() {
        #expect(!FolderSidebarProfileSwitcherPolicy.showsTopBar(profileCount: 0))
        #expect(!FolderSidebarProfileSwitcherPolicy.showsTopBar(profileCount: 1))
        #expect(FolderSidebarProfileSwitcherPolicy.showsTopBar(profileCount: 2))
        #expect(FolderSidebarProfileSwitcherPolicy.showsTopBar(profileCount: 5))
    }

    @Test("section header actions and account chevrons stay quiet at rest and reveal on hover")
    func sectionHeaderHoverVisibility() {
        #expect(FolderSidebarSectionHeaderActionVisibility.trailingActionOpacity(isHovered: false) == 0)
        #expect(FolderSidebarSectionHeaderActionVisibility.trailingActionOpacity(isHovered: true) == 1)
        #expect(FolderSidebarSectionHeaderActionVisibility.accountDisclosureChevronOpacity(isHovered: false) == 0)
        #expect(FolderSidebarSectionHeaderActionVisibility.accountDisclosureChevronOpacity(isHovered: true) == 1)
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
        // A server that can't be reached is offline even when the network is up.
        #expect(FolderSidebarSyncStatus(isOnline: true, isRefreshing: false, progress: nil, health: .offline)
            == .offline)
        for state in [SyncHealthState.healthy, .syncing, .indexing] {
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
