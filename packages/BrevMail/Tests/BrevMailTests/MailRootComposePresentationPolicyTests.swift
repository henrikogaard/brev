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
import SwiftUI
import Testing

@Suite("MailRootComposePresentationPolicy")
struct MailRootComposePresentationPolicyTests {
    @Test("compose can present when no root work or sheet is active")
    func composeCanPresentWhenNoRootWorkOrSheetIsActive() {
        #expect(MailRootComposePresentationPolicy.canPresentCompose(
            hasPresentedSheet: false,
            activeFolderLoadRequest: nil,
            activeMailboxLoadRequest: nil,
            activeRefreshRequest: nil,
            activeMailboxSwitchRequest: nil,
            activeCommandMutationRequest: nil,
            activeComposeCompletionRequest: nil
        ))
    }

    @Test("compose cannot present while another sheet is active")
    func composeCannotPresentWhileAnotherSheetIsActive() {
        #expect(!MailRootComposePresentationPolicy.canPresentCompose(
            hasPresentedSheet: true,
            activeFolderLoadRequest: nil,
            activeMailboxLoadRequest: nil,
            activeRefreshRequest: nil,
            activeMailboxSwitchRequest: nil,
            activeCommandMutationRequest: nil,
            activeComposeCompletionRequest: nil
        ))
    }

    @Test("compose cannot present while root mailbox context work is active")
    func composeCannotPresentWhileRootMailboxContextWorkIsActive() {
        #expect(!MailRootComposePresentationPolicy.canPresentCompose(
            hasPresentedSheet: false,
            activeFolderLoadRequest: MailRootFolderLoadRequest(id: 1),
            activeMailboxLoadRequest: nil,
            activeRefreshRequest: nil,
            activeMailboxSwitchRequest: nil,
            activeCommandMutationRequest: nil,
            activeComposeCompletionRequest: nil
        ))
        #expect(!MailRootComposePresentationPolicy.canPresentCompose(
            hasPresentedSheet: false,
            activeFolderLoadRequest: nil,
            activeMailboxLoadRequest: MailRootMailboxLoadRequest(id: 1),
            activeRefreshRequest: nil,
            activeMailboxSwitchRequest: nil,
            activeCommandMutationRequest: nil,
            activeComposeCompletionRequest: nil
        ))
        #expect(!MailRootComposePresentationPolicy.canPresentCompose(
            hasPresentedSheet: false,
            activeFolderLoadRequest: nil,
            activeMailboxLoadRequest: nil,
            activeRefreshRequest: MailRootRefreshRequest(
                id: 1,
                folderID: "inbox",
                mailboxID: "mailbox-a"
            ),
            activeMailboxSwitchRequest: nil,
            activeCommandMutationRequest: nil,
            activeComposeCompletionRequest: nil
        ))
        #expect(!MailRootComposePresentationPolicy.canPresentCompose(
            hasPresentedSheet: false,
            activeFolderLoadRequest: nil,
            activeMailboxLoadRequest: nil,
            activeRefreshRequest: nil,
            activeMailboxSwitchRequest: MailRootMailboxSwitchRequest(
                id: 1,
                mailboxID: "mailbox-b"
            ),
            activeCommandMutationRequest: nil,
            activeComposeCompletionRequest: nil
        ))
        #expect(!MailRootComposePresentationPolicy.canPresentCompose(
            hasPresentedSheet: false,
            activeFolderLoadRequest: nil,
            activeMailboxLoadRequest: nil,
            activeRefreshRequest: nil,
            activeMailboxSwitchRequest: nil,
            activeCommandMutationRequest: MailRootCommandMutationRequest(
                id: 1,
                sourceFolderID: "inbox"
            ),
            activeComposeCompletionRequest: nil
        ))
        #expect(!MailRootComposePresentationPolicy.canPresentCompose(
            hasPresentedSheet: false,
            activeFolderLoadRequest: nil,
            activeMailboxLoadRequest: nil,
            activeRefreshRequest: nil,
            activeMailboxSwitchRequest: nil,
            activeCommandMutationRequest: nil,
            activeComposeCompletionRequest: MailRootComposeCompletionRequest(
                id: 1,
                composePresentationID: 1,
                mailboxID: "mailbox-a"
            )
        ))
    }
}

@Suite("MailRootSheetPresentationPolicy")
struct MailRootSheetPresentationPolicyTests {
    @Test("settings can present when no sheet is active")
    func settingsCanPresentWhenNoSheetIsActive() {
        #expect(MailRootSheetPresentationPolicy.canPresentSettings(
            hasPresentedSheet: false
        ))
    }

    @Test("settings cannot present over another active sheet")
    func settingsCannotPresentOverAnotherActiveSheet() {
        #expect(!MailRootSheetPresentationPolicy.canPresentSettings(
            hasPresentedSheet: true
        ))
    }

    @Test("external settings window can open when no mail sheet is active")
    func externalSettingsWindowCanOpenWhenNoMailSheetIsActive() {
        #expect(MailRootSheetPresentationPolicy.canOpenSettings(
            hasPresentedSheet: false,
            usesExternalSettingsWindow: true
        ))
    }

    @Test("settings cannot open without an external settings surface")
    func settingsCannotOpenWithoutExternalSettingsSurface() {
        #expect(!MailRootSheetPresentationPolicy.canOpenSettings(
            hasPresentedSheet: false,
            usesExternalSettingsWindow: false
        ))
    }

    @Test("external settings window cannot open over an active mail sheet")
    func externalSettingsWindowCannotOpenOverActiveMailSheet() {
        #expect(!MailRootSheetPresentationPolicy.canOpenSettings(
            hasPresentedSheet: true,
            usesExternalSettingsWindow: true
        ))
    }

    @Test("mail background is hidden from accessibility while modal presentations are active")
    func mailBackgroundIsHiddenFromAccessibilityWhileModalPresentationsAreActive() {
        #expect(MailRootSheetPresentationPolicy.hidesBackgroundAccessibility(
            hasPresentedSheet: true,
            hasInitialMailboxSelection: false,
            hasFolderPrompt: false,
            hasFolderConfirmation: false
        ))
        #expect(MailRootSheetPresentationPolicy.hidesBackgroundAccessibility(
            hasPresentedSheet: false,
            hasInitialMailboxSelection: true,
            hasFolderPrompt: false,
            hasFolderConfirmation: false
        ))
        #expect(!MailRootSheetPresentationPolicy.hidesBackgroundAccessibility(
            hasPresentedSheet: false,
            hasInitialMailboxSelection: false,
            hasFolderPrompt: false,
            hasFolderConfirmation: false
        ))
        #expect(MailRootSheetPresentationPolicy.hidesBackgroundAccessibility(
            hasPresentedSheet: false,
            hasInitialMailboxSelection: false,
            hasFolderPrompt: false,
            hasFolderConfirmation: false,
            hasExternalModal: true
        ))
    }
}

@Suite("MailRootInitialMailboxSelectionPolicy")
struct MailRootInitialMailboxSelectionPolicyTests {
    private let first = MailSourceID(accountID: "acct-1", mailboxID: "first")
    private let second = MailSourceID(accountID: "acct-1", mailboxID: "second")
    private let other = MailSourceID(accountID: "acct-2", mailboxID: "other")

    @Test("does not present for already added accounts without pending setup")
    func doesNotPresentForAlreadyAddedAccountsWithoutPendingSetup() {
        #expect(MailRootInitialMailboxSelectionPolicy.action(
            pendingAccountID: nil,
            sourceIDs: [first, second],
            preferences: .defaults
        ) == .ignore)
    }

    @Test("presents only for pending setup account with multiple unconfigured mailboxes")
    func presentsOnlyForPendingSetupAccountWithMultipleUnconfiguredMailboxes() {
        #expect(MailRootInitialMailboxSelectionPolicy.action(
            pendingAccountID: "acct-1",
            sourceIDs: [first, second, other],
            preferences: .defaults
        ) == .present)
    }

    @Test("finishes pending setup without sheet for single mailbox accounts")
    func finishesPendingSetupWithoutSheetForSingleMailboxAccounts() {
        #expect(MailRootInitialMailboxSelectionPolicy.action(
            pendingAccountID: "acct-1",
            sourceIDs: [first, other],
            preferences: .defaults
        ) == .finishWithoutPresentation)
    }

    @Test("keeps pending setup while account sources have not loaded yet")
    func keepsPendingSetupWhileAccountSourcesHaveNotLoadedYet() {
        #expect(MailRootInitialMailboxSelectionPolicy.action(
            pendingAccountID: "acct-1",
            sourceIDs: [other],
            preferences: .defaults
        ) == .ignore)
    }

    @Test("finishes pending setup without sheet when settings already have explicit mailbox selection")
    func finishesPendingSetupWithoutSheetWhenSettingsAlreadyHaveExplicitSelection() {
        #expect(MailRootInitialMailboxSelectionPolicy.action(
            pendingAccountID: "acct-1",
            sourceIDs: [first, second],
            preferences: MailboxSourcePreferences(
                enabledSourceIDs: [first],
                defaultSourceID: first
            )
        ) == .finishWithoutPresentation)
    }
}

@Suite("MailRootSettingsToolbarPolicy")
struct MailRootSettingsToolbarPolicyTests {
    @Test("iPhone sidebar exposes an escape to the selected message list")
    func iPhoneSidebarExposesMessageListEscape() {
        #expect(MailRootSidebarToolbarPolicy.showsMessageListButton(
            platform: .iOS,
            horizontalSizeClass: .compact,
            hasSelectedDestination: true
        ))
        #expect(!MailRootSidebarToolbarPolicy.showsMessageListButton(
            platform: .iOS,
            horizontalSizeClass: .compact,
            hasSelectedDestination: false
        ))
        #expect(!MailRootSidebarToolbarPolicy.showsMessageListButton(
            platform: .iOS,
            horizontalSizeClass: .regular,
            hasSelectedDestination: true
        ))
        #expect(!MailRootSidebarToolbarPolicy.showsMessageListButton(
            platform: .macOS,
            horizontalSizeClass: .compact,
            hasSelectedDestination: true
        ))
    }

    @Test("detail toolbars condense secondary actions on every platform")
    func detailToolbarsCondenseSecondaryActions() {
        #expect(MailRootDetailToolbarPolicy.usesCondensedLayout(platform: .iOS))
        #expect(MailRootDetailToolbarPolicy.usesCondensedLayout(platform: .macOS))
    }

    @Test("macOS exposes the complete primary response group")
    func macOSExposesCompletePrimaryResponseGroup() {
        #expect(MailRootDetailToolbarPolicy.showsExtendedResponseActions(platform: .macOS))
        #expect(!MailRootDetailToolbarPolicy.showsExtendedResponseActions(platform: .iOS))
    }

    @Test("settings shows in sidebar and iOS message list toolbars")
    func settingsShowsInSidebarAndIOSMessageListToolbars() {
        #expect(MailRootSettingsToolbarPolicy.showsSettingsButton(
            on: .sidebar,
            platform: .iOS
        ))
        #expect(MailRootSettingsToolbarPolicy.showsSettingsButton(
            on: .messageList,
            platform: .iOS
        ))
        #expect(MailRootSettingsToolbarPolicy.showsSettingsButton(
            on: .detail,
            platform: .iOS
        ))
    }

    @Test("macOS keeps Settings out of window chrome and in the app menu")
    func macOSKeepsSettingsOutOfWindowChrome() {
        #expect(!MailRootSettingsToolbarPolicy.showsSettingsButton(
            on: .sidebar,
            platform: .macOS
        ))
        #expect(!MailRootSettingsToolbarPolicy.showsSettingsButton(
            on: .messageList,
            platform: .macOS
        ))
        #expect(!MailRootSettingsToolbarPolicy.showsSettingsButton(
            on: .detail,
            platform: .macOS
        ))
    }
}

@Suite("MailboxFilterControlPolicy")
struct MailboxFilterControlPolicyTests {
    @Test("filter glyph has no enclosing circle")
    func filterGlyphHasNoEnclosingCircle() {
        // macOS 26 draws each toolbar item inside its own circular bordered
        // container, so a `.circle` variant renders a circle inside a circle.
        #expect(MailboxFilterSymbol.name == "line.3.horizontal.decrease")
        #expect(!MailboxFilterSymbol.name.contains("circle"))
    }

    @Test("both platforms host sort and filter in the toolbar, never in-pane")
    func filterControlPlacementDiffersByPlatform() {
        #expect(MailboxFilterControlPolicy.usesToolbarControl(platform: .macOS))
        #expect(!MailboxFilterControlPolicy.usesInPaneBar(platform: .macOS))

        #expect(MailboxFilterControlPolicy.usesToolbarControl(platform: .iOS))
        #expect(!MailboxFilterControlPolicy.usesInPaneBar(platform: .iOS))
    }

    @Test("macOS promotes Flag out of the overflow menu")
    func macOSPromotesFlagOutOfOverflowMenu() {
        #expect(MailRootDetailToolbarPolicy.showsFlagButton(platform: .macOS))
        #expect(!MailRootDetailToolbarPolicy.showsFlagButton(platform: .iOS))
    }

    /// Create Task and Move used to ride in from `MessageDetailView`'s own
    /// `.toolbar`, which appends after the root's items — landing to the
    /// right of the AI Sidebar toggle and never condensing with the
    /// cluster, so at narrow reader widths they pushed the row across the
    /// divider into the message list.
    @Test("macOS hosts Create Task and Move in the root cluster, condensing with it")
    func macOSHostsOrganizerActionsInRootCluster() {
        #expect(MailRootDetailToolbarPolicy.showsMessageOrganizerActions(platform: .macOS))
        #expect(!MailRootDetailToolbarPolicy.showsMessageOrganizerActions(platform: .iOS))

        let narrow = MailRootDetailToolbarPolicy.condensedActionsReaderWidth - 1
        #expect(!MailRootDetailToolbarPolicy.showsMessageOrganizerActions(
            platform: .macOS, readerWidth: narrow
        ))
        #expect(MailRootDetailToolbarPolicy.showsMessageOrganizerActions(
            platform: .macOS,
            readerWidth: MailRootDetailToolbarPolicy.condensedActionsReaderWidth
        ))
    }

    /// The condensation width has to cover the whole cluster it now gates —
    /// including Create Task and Move, which the old 500pt measurement
    /// predates.
    @Test("the condensation width accounts for Create Task and Move")
    func condensationWidthAccountsForOrganizerActions() {
        #expect(MailRootDetailToolbarPolicy.condensedActionsReaderWidth >= 600)
    }

    /// Below the condensation width the full cluster no longer fits beside the
    /// reader, and the excess buttons used to spill left across the divider
    /// into the message list.
    @Test("narrow readers condense the response cluster into the overflow menu")
    func narrowReadersCondenseResponseCluster() {
        let narrow = MailRootDetailToolbarPolicy.condensedActionsReaderWidth - 1
        let wide = MailRootDetailToolbarPolicy.condensedActionsReaderWidth

        #expect(!MailRootDetailToolbarPolicy.showsExtendedResponseActions(
            platform: .macOS, readerWidth: narrow
        ))
        #expect(!MailRootDetailToolbarPolicy.showsFlagButton(
            platform: .macOS, readerWidth: narrow
        ))

        #expect(MailRootDetailToolbarPolicy.showsExtendedResponseActions(
            platform: .macOS, readerWidth: wide
        ))
        #expect(MailRootDetailToolbarPolicy.showsFlagButton(
            platform: .macOS, readerWidth: wide
        ))

        // An unknown reader width keeps the uncondensed default.
        #expect(MailRootDetailToolbarPolicy.showsExtendedResponseActions(
            platform: .macOS, readerWidth: nil
        ))

        // iOS never shows the extended cluster, wide or not.
        #expect(!MailRootDetailToolbarPolicy.showsExtendedResponseActions(
            platform: .iOS, readerWidth: 1200
        ))
        #expect(!MailRootDetailToolbarPolicy.showsFlagButton(
            platform: .iOS, readerWidth: 1200
        ))
    }

    @Test("the reader width settles past the longest gap in a column animation")
    func readerWidthSettleOutlastsColumnAnimationGaps() {
        // Revealing the folder sidebar animates in bursts with stalls
        // between them — measured at 107ms and 123ms on a 60fps capture.
        // A settle shorter than those would fire inside a stall and hand
        // the toolbar a width the animation had not finished moving.
        #expect(MailRootDetailToolbarPolicy.readerWidthSettleDuration >= .milliseconds(150))

        // It still has to be short enough that releasing a divider drag
        // reads as immediate.
        #expect(MailRootDetailToolbarPolicy.readerWidthSettleDuration <= .milliseconds(300))
    }

    @Test("a width excursion that returns is not a condensation change")
    func widthExcursionThatReturnsIsNotACondensationChange() {
        // The measured failure: showing the sidebar swept the reader from
        // 620 down through 480 and back to 620. Both ends read the same,
        // so settling on the last width leaves the toolbar untouched —
        // only the excursion in the middle ever asked it to condense.
        let settled = MailRootDetailToolbarPolicy.showsExtendedResponseActions(
            platform: .macOS, readerWidth: 620
        )
        let excursion = MailRootDetailToolbarPolicy.showsExtendedResponseActions(
            platform: .macOS, readerWidth: 480
        )

        #expect(settled)
        #expect(!excursion)
    }
}
