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

import BrevAvatars
import BrevBackend
import BrevDesign
import BrevThemes
import SwiftUI

/// Which theme token tints a sidebar icon or status symbol (#306).
/// Mailbox roles stay monochrome (`.neutral`) on macOS so unread counts and
/// selection carry the visual hierarchy; status symbols retain semantic tints.
enum FolderSidebarIconTint: Equatable, Sendable {
    case accent
    case info
    case warning
    case success
    case danger
    case neutral

    /// Monochrome tint for mailbox roles in the sidebar.
    static func tint(for role: FolderRole) -> FolderSidebarIconTint {
        _ = role
        return .neutral
    }

    /// Monochrome SF Symbol colour for macOS sidebar rows: muted secondary at
    /// rest, elevated to primary when selected (Apple Mail style).
    static func macOSRowColor(isSelected: Bool, in theme: BrevTheme) -> Color {
        isSelected ? theme.textPrimary.color : theme.textSecondary.color
    }

    /// The resolved theme colour.
    func color(in theme: BrevTheme) -> Color {
        switch self {
        case .accent: theme.accent.color
        case .info: theme.info.color
        case .warning: theme.warning.color
        case .success: theme.success.color
        case .danger: theme.danger.color
        case .neutral: theme.textSecondary.color
        }
    }
}

/// How the macOS sidebar column renders its backing surface inside
/// `NavigationSplitView`.
enum FolderSidebarSurfaceStyle: Equatable, Sendable {
    /// Let macOS 26 `NavigationSplitView` provide its native floating
    /// Liquid Glass sidebar column without painting a flat slab over it.
    case nativeFloatingGlass
    /// Render the legacy themed pane surface (`BrevWindowSurfaceBackground`).
    /// Used on macOS < 26 and whenever Reduce Transparency is enabled.
    case themedSurface
}

/// Decides whether the macOS sidebar lets macOS 26's native floating Liquid
/// Glass chrome shine cleanly or falls back to the themed surface.
enum FolderSidebarSurfacePolicy {
    static func style(
        isMacOS26OrLater: Bool,
        reduceTransparency: Bool,
        translucencyMode: WindowTranslucencyMode
    ) -> FolderSidebarSurfaceStyle {
        guard isMacOS26OrLater, !reduceTransparency else {
            return .themedSurface
        }
        // On macOS 26+, NavigationSplitView renders a native floating
        // translucent Liquid Glass sidebar across appearance modes unless
        // Reduce Transparency requests an opaque surface.
        _ = translucencyMode
        return .nativeFloatingGlass
    }

    /// Uses native macOS 26 soft scroll-edge chrome instead of the legacy
    /// manual top blur overlay when native floating glass is active.
    static func usesSoftScrollEdgeEffect(
        isMacOS26OrLater: Bool,
        reduceTransparency: Bool
    ) -> Bool {
        isMacOS26OrLater && !reduceTransparency
    }
}

/// Controls when the macOS sidebar shows the top profile switcher bar.
/// Single-profile (or All Mailboxes only) sessions omit the top banner so
/// Favorites sit cleanly at the top edge like Apple Mail, while profile
/// management stays reachable via section context menus and Settings.
enum FolderSidebarProfileSwitcherPolicy {
    static func showsTopBar(profileCount: Int) -> Bool {
        profileCount > 1
    }
}

/// Controls hover-revealed accessories on macOS sidebar section headers so
/// resting headers stay quiet while keeping VoiceOver and keyboard access intact.
enum FolderSidebarSectionHeaderActionVisibility {
    /// Trailing opacity for hover-only header actions (`•••`, `+`).
    static func trailingActionOpacity(isHovered: Bool) -> Double {
        isHovered ? 1 : 0
    }

    /// Disclosure chevron opacity for collapsible account section headers.
    static func accountDisclosureChevronOpacity(isHovered: Bool) -> Double {
        isHovered ? 1 : 0
    }
}

/// The one-line sync state in the sidebar footer (#306).
enum FolderSidebarSyncStatus: Equatable, Sendable {
    case offline
    case needsAttention
    case syncing(completed: Int, total: Int)
    case checking
    case upToDate

    /// Picks the most important state: being offline beats a sync problem,
    /// and a sync problem beats any sync work, so a rejected sign-in is never
    /// reported as "Up to date".
    init(
        isOnline: Bool,
        isRefreshing: Bool,
        progress: (completed: Int, total: Int)?,
        health: SyncHealthState? = nil
    ) {
        // The account's own health counts too: a server that can't be
        // reached reports `.offline` while the network path is fine.
        if !isOnline || health == .offline {
            self = .offline
        } else if let health, [.authenticationRequired, .providerError, .degraded].contains(health) {
            self = .needsAttention
        } else if let progress, progress.total > 0, progress.completed < progress.total {
            self = .syncing(completed: progress.completed, total: progress.total)
        } else if isRefreshing {
            self = .checking
        } else {
            self = .upToDate
        }
    }

    /// Short text under the footer name.
    var title: String {
        switch self {
        case .offline:
            String(localized: "Offline", bundle: .module)
        case .needsAttention:
            String(localized: "Needs attention", bundle: .module)
        case .syncing(let completed, let total):
            String(localized: "Syncing \(completed) of \(total)", bundle: .module)
        case .checking:
            String(localized: "Checking for mail…", bundle: .module)
        case .upToDate:
            String(localized: "Up to date", bundle: .module)
        }
    }

    /// The small leading status symbol.
    var symbolName: String {
        switch self {
        case .offline: "wifi.slash"
        case .needsAttention: "exclamationmark.triangle.fill"
        case .syncing, .checking: "arrow.triangle.2.circlepath"
        case .upToDate: "circle.fill"
        }
    }

    /// The theme token for the status symbol.
    var tint: FolderSidebarIconTint {
        switch self {
        case .offline, .needsAttention: .warning
        case .syncing, .checking: .neutral
        case .upToDate: .success
        }
    }
}

/// Who the sidebar footer names: the first account's display name, or its
/// address when the name is blank.
struct FolderSidebarFooterIdentity: Equatable, Sendable {
    let name: String
    let initials: String

    init(name: String, initials: String) {
        self.name = name
        self.initials = initials
    }

    /// Nil when there is no account to show.
    init?(accounts: [BrevAccount]) {
        guard let account = accounts.first else { return nil }
        let displayName = account.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        name = displayName.isEmpty ? account.emailAddress : displayName
        initials = InitialsAvatar.initials(displayName: displayName, email: account.emailAddress)
    }
}

/// Everything the macOS sidebar footer needs; nil hides the footer.
struct FolderSidebarFooter {
    let identity: FolderSidebarFooterIdentity?
    let status: FolderSidebarSyncStatus
    let onOpenSettings: (() -> Void)?
}

#if os(macOS)
extension View {
    /// Applies the macOS sidebar backing surface: lets macOS 26's native
    /// floating Liquid Glass column shine cleanly unless Reduce Transparency
    /// or macOS < 26 requires the themed surface fallback.
    func brevMacSidebarPaneSurface() -> some View {
        modifier(MacSidebarPaneSurfaceModifier())
    }

    /// Applies the legacy top scroll-edge blur overlay only when native
    /// macOS 26 soft scroll-edge chrome is unavailable or disabled.
    func brevMacSidebarScrollEdgeChrome() -> some View {
        modifier(MacSidebarScrollEdgeChromeModifier())
    }
}

private struct MacSidebarPaneSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(WindowAppearancePreferenceKey.mode) private var translucencyModeRaw = WindowTranslucencyMode.solid.rawValue

    private var translucencyMode: WindowTranslucencyMode {
        WindowTranslucencyMode(rawValue: translucencyModeRaw) ?? .solid
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *),
           FolderSidebarSurfacePolicy.style(
               isMacOS26OrLater: true,
               reduceTransparency: reduceTransparency,
               translucencyMode: translucencyMode
           ) == .nativeFloatingGlass {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            content.brevMailPaneSurface(.sidebar)
        }
        #else
        content.brevMailPaneSurface(.sidebar)
        #endif
    }
}

private struct MacSidebarScrollEdgeChromeModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *),
           FolderSidebarSurfacePolicy.usesSoftScrollEdgeEffect(
               isMacOS26OrLater: true,
               reduceTransparency: reduceTransparency
           ) {
            content
        } else {
            content.brevMailPaneScrollEdgeBlur()
        }
        #else
        content.brevMailPaneScrollEdgeBlur()
        #endif
    }
}
#endif
