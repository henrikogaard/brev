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

enum MailRootSettingsToolbarPolicy {
    static func showsSettingsButton(
        on surface: MailRootToolbarSurface,
        platform: MailRootToolbarPlatform
    ) -> Bool {
        // macOS reaches Settings through the app menu (Cmd-,), so the window
        // chrome carries no Settings control on any surface. iOS has no menu
        // bar, so the sidebar keeps it as the primary entry point.
        switch surface {
        case .sidebar, .messageList, .detail:
            platform == .iOS
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

    /// Reader width below which the cluster condenses: Reply All, Forward,
    /// Flag, Create Task, and Move leave their own buttons for the overflow
    /// menu. The pre-organizer macOS cluster measured just under 500pt with
    /// search collapsed; Create Task and Move — hosted in the root cluster
    /// since they left `MessageDetailView`'s toolbar — add two bordered
    /// buttons and a group gap, estimated at ~100pt (pending an on-screen
    /// re-measure). In a narrower reader the excess buttons spill left
    /// across the split-view divider into the message list instead of
    /// collapsing.
    static let condensedActionsReaderWidth: CGFloat = 600

    /// How long the reader width has to hold still before the toolbar acts
    /// on it.
    ///
    /// Column animations sweep this width rather than stepping it, and the
    /// sweep is not monotonic: revealing the folder sidebar takes width
    /// from the reader before the message list gives some back, so the
    /// reader dips below `condensedActionsReaderWidth` on its way to a
    /// final width above it. Acting on every intermediate width folded the
    /// cluster into the overflow menu and unfolded it again — two extra
    /// animated toolbar passes on the end of a reveal that was otherwise
    /// finished in ~300ms.
    ///
    /// The animation runs in bursts with stalls between them (measured at
    /// 107ms and 123ms), so the settle has to outlast the longest stall
    /// without making a released divider drag feel laggy.
    static let readerWidthSettleDuration: Duration = .milliseconds(180)

    static func showsExtendedResponseActions(
        platform: MailRootToolbarPlatform,
        readerWidth: CGFloat? = nil
    ) -> Bool {
        guard platform == .macOS else { return false }
        guard let readerWidth else { return true }
        return readerWidth >= condensedActionsReaderWidth
    }

    /// macOS gives Flag its own toolbar button instead of folding it into an
    /// overflow menu — unless the reader is too narrow for the full cluster.
    /// At full width that menu held Flag and nothing else there — Forward and
    /// Settings are both excluded on macOS — so the extra press bought
    /// nothing. iOS keeps the menu, where it still carries all three.
    static func showsFlagButton(
        platform: MailRootToolbarPlatform,
        readerWidth: CGFloat? = nil
    ) -> Bool {
        guard platform == .macOS else { return false }
        guard let readerWidth else { return true }
        return readerWidth >= condensedActionsReaderWidth
    }

    /// macOS shows Create Task and Move as their own buttons in the root
    /// cluster — unless the reader is too narrow, where they fold into the
    /// overflow menu with the rest. They used to ride in from
    /// `MessageDetailView`'s own `.toolbar`, which appends after the root's
    /// items: that put them to the right of the AI Sidebar toggle and kept
    /// them out of this condensation entirely, so narrow readers leaked
    /// them across the divider. iOS keeps them in the reader's own tools
    /// menu.
    static func showsMessageOrganizerActions(
        platform: MailRootToolbarPlatform,
        readerWidth: CGFloat? = nil
    ) -> Bool {
        guard platform == .macOS else { return false }
        guard let readerWidth else { return true }
        return readerWidth >= condensedActionsReaderWidth
    }
}
