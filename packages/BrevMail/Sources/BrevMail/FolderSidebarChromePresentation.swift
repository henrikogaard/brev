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
import BrevThemes
import SwiftUI

/// Which theme token tints a mailbox icon in the sidebar (#306). Roles get a
/// colour so the common mailboxes can be found at a glance; custom folders
/// stay neutral so a long folder tree does not turn into confetti.
enum FolderSidebarIconTint: Equatable, Sendable {
    case accent
    case info
    case warning
    case success
    case danger
    case neutral

    /// The tint for a folder role.
    static func tint(for role: FolderRole) -> FolderSidebarIconTint {
        switch role {
        case .inbox, .sent: .accent
        case .drafts, .scheduled: .info
        case .starred, .snoozed: .warning
        case .archive: .success
        case .spam: .danger
        case .trash, .allMail, .custom: .neutral
        }
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
