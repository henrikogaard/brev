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
import Foundation
import Testing

@Suite("Folder sidebar chrome presentation")
struct FolderSidebarChromePresentationTests {
    @Test("macOS row icons use soft muted tertiary at rest and secondary when selected across light and dark themes")
    func macOSRowIconColors() {
        for theme in [BrevTheme.brevMonoDark, .brevMonoGrey, .brevMonoLight] {
            #expect(
                FolderSidebarIconTint.macOSRowColor(isSelected: false, in: theme)
                    == theme.textTertiary.color.opacity(0.82)
            )
            #expect(
                FolderSidebarIconTint.macOSRowColor(isSelected: true, in: theme)
                    == theme.textSecondary.color
            )
        }
    }

    @Test("macOS section header titles stay calm and muted across light and dark themes")
    func macOSSectionHeaderTitleColors() {
        for theme in [BrevTheme.brevMonoDark, .brevMonoGrey, .brevMonoLight] {
            #expect(
                FolderSidebarSectionHeaderStyle.titleColor(in: theme)
                    == theme.textTertiary.color.opacity(0.76)
            )
        }
    }

    @Test("macOS 26 sidebar honors default glass, explicit Off, sidebar opacity endpoints, and Reduce Transparency")
    func surfacePolicy() {
        // Out-of-the-box macOS 26 (no explicit mode saved yet) renders pure native floating Liquid Glass.
        #expect(
            FolderSidebarSurfacePolicy.style(
                isMacOS26OrLater: true,
                reduceTransparency: false,
                hasSavedMode: false,
                preferences: .defaults,
                hasSavedSidebarOpacity: false
            ) == .nativeFloatingGlass(overlayOpacity: 0)
        )
        #expect(
            FolderSidebarSurfacePolicy.usesSoftScrollEdgeEffect(
                isMacOS26OrLater: true,
                reduceTransparency: false,
                hasSavedMode: false,
                preferences: .defaults,
                hasSavedSidebarOpacity: false
            )
        )

        // Explicit Off (.solid) restores the solid themed surface.
        let explicitSolid = WindowAppearancePreferences(mode: .solid, scope: .mainWindow)
        #expect(
            FolderSidebarSurfacePolicy.style(
                isMacOS26OrLater: true,
                reduceTransparency: false,
                hasSavedMode: true,
                preferences: explicitSolid
            ) == .themedSurface
        )
        #expect(
            !FolderSidebarSurfacePolicy.usesSoftScrollEdgeEffect(
                isMacOS26OrLater: true,
                reduceTransparency: false,
                hasSavedMode: true,
                preferences: explicitSolid
            )
        )

        // Explicit legacy vibrancy modes (.subtle, .frosted) delegate to BrevWindowSurfaceBackground + slider.
        for legacyMode in [WindowTranslucencyMode.subtle, .frosted] {
            let prefs = WindowAppearancePreferences(mode: legacyMode, scope: .sidebarOnly, sidebarOpacity: 1.0)
            #expect(
                FolderSidebarSurfacePolicy.style(
                    isMacOS26OrLater: true,
                    reduceTransparency: false,
                    hasSavedMode: true,
                    preferences: prefs,
                    hasSavedSidebarOpacity: true
                ) == .themedSurface
            )
        }

        // Explicit .glass without a custom sidebar opacity keeps pure native Liquid Glass.
        let glassDefault = WindowAppearancePreferences(mode: .glass, scope: .sidebarOnly)
        #expect(
            FolderSidebarSurfacePolicy.style(
                isMacOS26OrLater: true,
                reduceTransparency: false,
                hasSavedMode: true,
                preferences: glassDefault,
                hasSavedSidebarOpacity: false
            ) == .nativeFloatingGlass(overlayOpacity: 0)
        )

        // Explicit .glass with sidebarOpacity slider endpoints (min translucent vs 100% opaque).
        let glassMin = WindowAppearancePreferences(mode: .glass, scope: .sidebarOnly, sidebarOpacity: 0.0)
        #expect(
            FolderSidebarSurfacePolicy.style(
                isMacOS26OrLater: true,
                reduceTransparency: false,
                hasSavedMode: true,
                preferences: glassMin,
                hasSavedSidebarOpacity: true
            ) == .nativeFloatingGlass(overlayOpacity: WindowAppearancePreferences.sidebarOpacityRange.lowerBound)
        )
        let glassOpaque = WindowAppearancePreferences(mode: .glass, scope: .sidebarOnly, sidebarOpacity: 1.0)
        #expect(
            FolderSidebarSurfacePolicy.style(
                isMacOS26OrLater: true,
                reduceTransparency: false,
                hasSavedMode: true,
                preferences: glassOpaque,
                hasSavedSidebarOpacity: true
            ) == .nativeFloatingGlass(overlayOpacity: 1.0)
        )
        #expect(
            !FolderSidebarSurfacePolicy.usesSoftScrollEdgeEffect(
                isMacOS26OrLater: true,
                reduceTransparency: false,
                hasSavedMode: true,
                preferences: glassOpaque,
                hasSavedSidebarOpacity: true
            )
        )

        // Reduce Transparency and macOS < 26 always fall back to the themed surface.
        #expect(
            FolderSidebarSurfacePolicy.style(
                isMacOS26OrLater: true,
                reduceTransparency: true,
                hasSavedMode: false,
                preferences: glassDefault
            ) == .themedSurface
        )
        #expect(
            FolderSidebarSurfacePolicy.style(
                isMacOS26OrLater: false,
                reduceTransparency: false,
                hasSavedMode: false,
                preferences: glassDefault
            ) == .themedSurface
        )
    }

    @Test("persisted Appearance reset restores macOS 26 native glass while explicit Off stays solid")
    func persistedResetRestoresNativeGlassWhileExplicitOffStaysSolid() throws {
        let suiteName = "FolderSidebarChromePresentationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        func resolvedStyle() -> FolderSidebarSurfaceStyle {
            FolderSidebarSurfacePolicy.style(
                isMacOS26OrLater: true,
                reduceTransparency: false,
                hasSavedMode: defaults.string(forKey: WindowAppearancePreferenceKey.mode) != nil,
                preferences: WindowAppearancePreferences.load(from: defaults),
                hasSavedSidebarOpacity: defaults.object(forKey: WindowAppearancePreferenceKey.sidebarOpacity) != nil
            )
        }

        // Fresh defaults -> automatic native floating Liquid Glass.
        #expect(resolvedStyle() == .nativeFloatingGlass(overlayOpacity: 0))

        // Explicit Off saves `.solid` -> themed opaque sidebar.
        WindowAppearancePreferences(mode: .solid, scope: .mainWindow).save(to: defaults)
        #expect(resolvedStyle() == .themedSurface)

        // Appearance reset clears override keys -> returns to automatic native Liquid Glass.
        WindowAppearancePreferences.reset(in: defaults)
        #expect(WindowAppearancePreferences.load(from: defaults) == .defaults)
        #expect(resolvedStyle() == .nativeFloatingGlass(overlayOpacity: 0))
    }

    @Test("macOS top profile switcher hides for single-profile workspaces and shows for multi-profile")
    func profileSwitcherVisibility() {
        #expect(!FolderSidebarProfileSwitcherPolicy.showsTopBar(profileCount: 0))
        #expect(!FolderSidebarProfileSwitcherPolicy.showsTopBar(profileCount: 1))
        #expect(FolderSidebarProfileSwitcherPolicy.showsTopBar(profileCount: 2))
        #expect(FolderSidebarProfileSwitcherPolicy.showsTopBar(profileCount: 5))
    }

    @Test("section header actions and Smart Views / account chevrons stay quiet at rest and reveal on hover or focus")
    func sectionHeaderHoverAndFocusVisibility() {
        #expect(FolderSidebarSectionHeaderActionVisibility.trailingActionOpacity(isHovered: false, isFocused: false) == 0)
        #expect(FolderSidebarSectionHeaderActionVisibility.trailingActionOpacity(isHovered: true, isFocused: false) == 1)
        #expect(FolderSidebarSectionHeaderActionVisibility.trailingActionOpacity(isHovered: false, isFocused: true) == 1)
        #expect(FolderSidebarSectionHeaderActionVisibility
            .accountDisclosureChevronOpacity(isHovered: false, isFocused: false) == 0)
        #expect(FolderSidebarSectionHeaderActionVisibility
            .accountDisclosureChevronOpacity(isHovered: true, isFocused: false) == 1)
        #expect(FolderSidebarSectionHeaderActionVisibility
            .accountDisclosureChevronOpacity(isHovered: false, isFocused: true) == 1)
    }

    @Test("account header Account Settings action prefers dedicated Accounts-pane callback and falls back cleanly")
    func accountSettingsActionResolution() {
        var invoked: [String] = []
        let dedicated = FolderSidebarAccountSettingsAction.resolve(
            onOpenAccountSettings: { invoked.append("accounts") },
            footerOpenSettings: { invoked.append("footer") },
            fallbackOpenSettings: { invoked.append("fallback") }
        )
        dedicated?()
        #expect(invoked == ["accounts"])

        let footerFallback = FolderSidebarAccountSettingsAction.resolve(
            onOpenAccountSettings: nil,
            footerOpenSettings: { invoked.append("footer") },
            fallbackOpenSettings: { invoked.append("fallback") }
        )
        footerFallback?()
        #expect(invoked == ["accounts", "footer"])

        let genericFallback = FolderSidebarAccountSettingsAction.resolve(
            onOpenAccountSettings: nil,
            footerOpenSettings: nil,
            fallbackOpenSettings: { invoked.append("fallback") }
        )
        genericFallback?()
        #expect(invoked == ["accounts", "footer", "fallback"])
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
