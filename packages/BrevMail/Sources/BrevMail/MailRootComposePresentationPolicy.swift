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
import CoreGraphics
import SwiftUI

enum MailRootComposePresentationPolicy {
    static func canPresentCompose(
        hasPresentedSheet: Bool,
        activeFolderLoadRequest: MailRootFolderLoadRequest?,
        activeMailboxLoadRequest: MailRootMailboxLoadRequest?,
        activeRefreshRequest: MailRootRefreshRequest?,
        activeMailboxSwitchRequest: MailRootMailboxSwitchRequest?,
        activeCommandMutationRequest: MailRootCommandMutationRequest?,
        activeComposeCompletionRequest: MailRootComposeCompletionRequest?
    ) -> Bool {
        !hasPresentedSheet
            && activeFolderLoadRequest == nil
            && activeMailboxLoadRequest == nil
            && activeRefreshRequest == nil
            && activeMailboxSwitchRequest == nil
            && activeCommandMutationRequest == nil
            && activeComposeCompletionRequest == nil
    }
}

enum MailRootInitialMailboxSelectionAction: Equatable, Sendable {
    case ignore
    case present
    case finishWithoutPresentation
}

enum MailRootInitialMailboxSelectionPolicy {
    static func action(
        pendingAccountID: BrevAccount.ID?,
        sourceIDs: [MailSourceID],
        preferences: MailboxSourcePreferences
    ) -> MailRootInitialMailboxSelectionAction {
        guard let pendingAccountID else { return .ignore }

        let setupSourceIDs = sourceIDs.filter { $0.accountID == pendingAccountID }
        guard !setupSourceIDs.isEmpty else {
            return .ignore
        }

        guard setupSourceIDs.count > 1 else {
            return .finishWithoutPresentation
        }

        if MailboxSourcePreferencesPolicy.hasExplicitSelection(
            availableSourceIDs: setupSourceIDs,
            preferences: preferences
        ) {
            return .finishWithoutPresentation
        }

        return .present
    }
}

enum MailRootSheetPresentationPolicy {
    static func canPresentSettings(hasPresentedSheet: Bool) -> Bool {
        !hasPresentedSheet
    }

    /// Settings always opens the external `BrevSettings` surface (no
    /// in-mail sheet). Without `onOpenSettings`, the gear is disabled.
    static func canOpenSettings(
        hasPresentedSheet: Bool,
        usesExternalSettingsWindow: Bool
    ) -> Bool {
        usesExternalSettingsWindow && !hasPresentedSheet
    }

    static func hidesBackgroundAccessibility(
        hasPresentedSheet: Bool,
        hasInitialMailboxSelection: Bool,
        hasFolderPrompt: Bool,
        hasFolderConfirmation: Bool,
        hasExternalModal: Bool = false
    ) -> Bool {
        hasPresentedSheet
            || hasInitialMailboxSelection
            || hasFolderPrompt
            || hasFolderConfirmation
            || hasExternalModal
    }
}

enum MailRootToolbarSurface: Sendable, Equatable {
    case sidebar
    case messageList
    case detail
}

enum MailRootToolbarPlatform: Sendable, Equatable {
    case iOS
    case macOS
}

enum MailRootMessageListTitlePolicy {
    static func accountContext(
        mailboxDisplayName: String,
        accountDisplayName: String,
        mailboxEmail: String
    ) -> String? {
        let email = mailboxEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [mailboxDisplayName, accountDisplayName]
        let displayName = candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { candidate in
                !candidate.isEmpty
                    && candidate.localizedCaseInsensitiveCompare(email) != .orderedSame
                    && !candidate.contains("@")
            })
        if let displayName {
            return displayName
        }
        return email.isEmpty ? nil : email
    }
}

enum MailRootSettingsToolbarPolicy {
    static func showsSettingsButton(
        on surface: MailRootToolbarSurface,
        platform: MailRootToolbarPlatform
    ) -> Bool {
        // macOS reaches Settings through the app menu (Cmd-,), so the window
        // chrome carries no Settings control on any surface. iOS has no menu
        // bar, so the sidebar keeps it as the primary entry point.
        switch surface {
        case .sidebar:
            platform == .iOS
        case .messageList, .detail:
            false
        }
    }
}

/// Controls the compact-only route from the mailbox sidebar to its message list.
enum MailRootSidebarToolbarPolicy {
    /// Shows the escape only for compact iOS layouts with a selected destination.
    static func showsMessageListButton(
        platform: MailRootToolbarPlatform,
        horizontalSizeClass: UserInterfaceSizeClass?,
        hasSelectedDestination: Bool
    ) -> Bool {
        platform == .iOS
            && horizontalSizeClass != .regular
            && hasSelectedDestination
    }
}

/// Toolbar section that carries Get Mail and New Message.
enum MailRootMailboxActionToolbarSection: CaseIterable {
    case messageList
    case detail
}

enum MailRootMailboxActionToolbarPolicy {
    /// Which section owns the mailbox-wide actions.
    ///
    /// Mail puts New Message and Get Mail at the head of the reader's action
    /// cluster, not above the message list, and the grouping reads correctly:
    /// everything from that point rightward acts on mail rather than on the
    /// list's presentation. Over the list they sat beside sort and filter, which
    /// only change what the list shows. iOS has one column at a time and no
    /// reader section to put them in, so they stay with the list there.
    static func section(platform: MailRootToolbarPlatform) -> MailRootMailboxActionToolbarSection {
        platform == .macOS ? .detail : .messageList
    }

    static func showsMailboxActions(
        on section: MailRootMailboxActionToolbarSection,
        platform: MailRootToolbarPlatform
    ) -> Bool {
        Self.section(platform: platform) == section
    }
}

enum MailRootDetailToolbarPolicy {
    static func usesCondensedLayout(platform _: MailRootToolbarPlatform) -> Bool {
        // The native macOS toolbar already favors a compact Reply / Archive /
        // Delete grouping; keep the SwiftUI fallback equally calm.
        true
    }

    /// How long the reader width has to hold still before the search field
    /// sizes itself against it.
    ///
    /// Column animations sweep this width rather than stepping it, and the
    /// sweep is not monotonic: revealing the folder sidebar takes width
    /// from the reader before the message list gives some back, so the
    /// reader can dip before the message list gives some width back. Acting
    /// on every intermediate value makes an expanded search field visibly
    /// pulse during an otherwise smooth column reveal.
    ///
    /// The animation runs in bursts with stalls between them (measured at
    /// 107ms and 123ms), so the settle has to outlast the longest stall
    /// without making a released divider drag feel laggy.
    static let readerWidthSettleDuration: Duration = .milliseconds(180)

    static func showsExtendedResponseActions(
        platform _: MailRootToolbarPlatform,
        readerWidth _: CGFloat? = nil
    ) -> Bool {
        false
    }

    /// Flag stays secondary on both platforms so the primary cluster keeps
    /// Reply, Archive, and Delete scannable at every reader width.
    static func showsFlagButton(
        platform _: MailRootToolbarPlatform,
        readerWidth _: CGFloat? = nil
    ) -> Bool {
        false
    }

    /// Workflow actions stay secondary on both platforms. They remain
    /// reachable through More and their existing commands/context menus.
    static func showsMessageOrganizerActions(
        platform _: MailRootToolbarPlatform,
        readerWidth _: CGFloat? = nil
    ) -> Bool {
        false
    }
}
