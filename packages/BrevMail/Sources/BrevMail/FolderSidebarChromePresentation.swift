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

/// Which theme token tints a sidebar status symbol or row icon (#306).
/// Status symbols retain semantic tints; macOS sidebar row icons stay
/// monochrome via `macOSRowColor(isSelected:in:)`.
enum FolderSidebarIconTint: Equatable, Sendable {
    case accent
    case info
    case warning
    case success
    case danger
    case neutral

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
    /// Let macOS 26 `NavigationSplitView` provide its native floating Liquid
    /// Glass sidebar column, optionally tinted by a themed overlay opacity
    /// (`0` = pure native glass, `1` = opaque `theme.bgSecondary.color`).
    case nativeFloatingGlass(overlayOpacity: Double)
    /// Render the legacy themed pane surface (`BrevWindowSurfaceBackground`).
    /// Used on macOS < 26, when Reduce Transparency is enabled, or when the
    /// user explicitly chooses Off (`.solid`) or a legacy vibrancy mode.
    case themedSurface
}

/// Decides whether the macOS sidebar lets macOS 26's native floating Liquid
/// Glass chrome shine cleanly or falls back to the themed surface.
enum FolderSidebarSurfacePolicy {
    static func style(
        isMacOS26OrLater: Bool,
        reduceTransparency: Bool,
        hasSavedMode: Bool,
        preferences: WindowAppearancePreferences,
        hasSavedSidebarOpacity: Bool = false
    ) -> FolderSidebarSurfaceStyle {
        guard isMacOS26OrLater, !reduceTransparency else {
            return .themedSurface
        }
        // Out of the box on macOS 26 (before the user saves an explicit
        // Window Transparency override), let NavigationSplitView's native
        // floating Liquid Glass column shine cleanly.
        if !hasSavedMode {
            let overlayOpacity = hasSavedSidebarOpacity
                ? clampedOverlayOpacity(preferences.sidebarOpacity)
                : 0
            return .nativeFloatingGlass(overlayOpacity: overlayOpacity)
        }
        switch preferences.mode {
        case .solid, .subtle, .frosted:
            // Explicit Off (`.solid`) restores the solid themed fill, and
            // `.subtle`/`.frosted` honor BrevWindowSurfaceBackground + slider.
            return .themedSurface
        case .glass:
            guard preferences.scope.applies(to: .sidebar) else {
                return .themedSurface
            }
            let overlayOpacity = hasSavedSidebarOpacity
                ? clampedOverlayOpacity(preferences.sidebarOpacity)
                : 0
            return .nativeFloatingGlass(overlayOpacity: overlayOpacity)
        }
    }

    /// Uses native macOS 26 soft scroll-edge chrome instead of the legacy
    /// manual top blur overlay when translucent native floating glass is active.
    static func usesSoftScrollEdgeEffect(
        isMacOS26OrLater: Bool,
        reduceTransparency: Bool,
        hasSavedMode: Bool = false,
        preferences: WindowAppearancePreferences = .defaults,
        hasSavedSidebarOpacity: Bool = false
    ) -> Bool {
        switch style(
            isMacOS26OrLater: isMacOS26OrLater,
            reduceTransparency: reduceTransparency,
            hasSavedMode: hasSavedMode,
            preferences: preferences,
            hasSavedSidebarOpacity: hasSavedSidebarOpacity
        ) {
        case .nativeFloatingGlass(let overlayOpacity):
            return overlayOpacity < 1
        case .themedSurface:
            return false
        }
    }

    private static func clampedOverlayOpacity(_ value: Double) -> Double {
        min(max(value, 0), 1)
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

/// Controls hover- and focus-revealed accessories on macOS sidebar section
/// headers so resting headers stay quiet while keeping pointer, keyboard Tab,
/// and VoiceOver access visible and usable.
enum FolderSidebarSectionHeaderActionVisibility {
    /// Trailing opacity for header actions (`•••`, `+`).
    static func trailingActionOpacity(isHovered: Bool, isFocused: Bool = false) -> Double {
        (isHovered || isFocused) ? 1 : 0
    }

    /// Disclosure chevron opacity for collapsible account section headers.
    static func accountDisclosureChevronOpacity(isHovered: Bool, isFocused: Bool = false) -> Double {
        (isHovered || isFocused) ? 1 : 0
    }
}

/// Resolves the callback for "Account Settings…" context menu actions,
/// preferring the Accounts-pane-targeted handler when wired.
enum FolderSidebarAccountSettingsAction {
    static func resolve(
        onOpenAccountSettings: (() -> Void)?,
        footerOpenSettings: (() -> Void)?,
        fallbackOpenSettings: (() -> Void)?
    ) -> (() -> Void)? {
        onOpenAccountSettings ?? footerOpenSettings ?? fallbackOpenSettings
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
    @Environment(\.brevTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(WindowAppearancePreferenceKey.mode) private var savedModeRaw: String?
    @AppStorage(WindowAppearancePreferenceKey.scope) private var scopeRaw = WindowTranslucencyScope.mainWindow.rawValue
    @AppStorage(WindowAppearancePreferenceKey.surfaceOpacity)
    private var surfaceOpacity = WindowAppearancePreferences.defaultSurfaceOpacity
    @AppStorage(WindowAppearancePreferenceKey.sidebarOpacity) private var savedSidebarOpacity: Double?

    private var preferences: WindowAppearancePreferences {
        WindowAppearancePreferences(
            mode: savedModeRaw.flatMap(WindowTranslucencyMode.init(rawValue:)) ?? .solid,
            scope: WindowTranslucencyScope(rawValue: scopeRaw) ?? .mainWindow,
            surfaceOpacity: surfaceOpacity,
            sidebarOpacity: savedSidebarOpacity
        )
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            switch FolderSidebarSurfacePolicy.style(
                isMacOS26OrLater: true,
                reduceTransparency: reduceTransparency,
                hasSavedMode: savedModeRaw != nil,
                preferences: preferences,
                hasSavedSidebarOpacity: savedSidebarOpacity != nil
            ) {
            case .nativeFloatingGlass(let overlayOpacity):
                ZStack {
                    if overlayOpacity > 0 {
                        theme.bgSecondary.color
                            .opacity(overlayOpacity)
                            .ignoresSafeArea()
                    }
                    content
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .themedSurface:
                content.brevMailPaneSurface(.sidebar)
            }
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
    @AppStorage(WindowAppearancePreferenceKey.mode) private var savedModeRaw: String?
    @AppStorage(WindowAppearancePreferenceKey.scope) private var scopeRaw = WindowTranslucencyScope.mainWindow.rawValue
    @AppStorage(WindowAppearancePreferenceKey.surfaceOpacity)
    private var surfaceOpacity = WindowAppearancePreferences.defaultSurfaceOpacity
    @AppStorage(WindowAppearancePreferenceKey.sidebarOpacity) private var savedSidebarOpacity: Double?

    private var preferences: WindowAppearancePreferences {
        WindowAppearancePreferences(
            mode: savedModeRaw.flatMap(WindowTranslucencyMode.init(rawValue:)) ?? .solid,
            scope: WindowTranslucencyScope(rawValue: scopeRaw) ?? .mainWindow,
            surfaceOpacity: surfaceOpacity,
            sidebarOpacity: savedSidebarOpacity
        )
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *),
           FolderSidebarSurfacePolicy.usesSoftScrollEdgeEffect(
               isMacOS26OrLater: true,
               reduceTransparency: reduceTransparency,
               hasSavedMode: savedModeRaw != nil,
               preferences: preferences,
               hasSavedSidebarOpacity: savedSidebarOpacity != nil
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
