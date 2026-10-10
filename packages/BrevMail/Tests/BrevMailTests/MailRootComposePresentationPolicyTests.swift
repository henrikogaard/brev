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

@Suite("MailRootQuickReplyPolicy")
struct MailRootQuickReplyPolicyTests {
    @Test("outbound-ended thread selects the newest replyable inbound message")
    func outboundEndedThreadSelectsPriorInbound() {
        let inbound = Self.header(
            id: "inbound",
            sender: "alex@example.org",
            date: 1
        )
        let outbound = Self.header(
            id: "outbound",
            sender: "henrik@example.org",
            date: 2,
            recipients: ["henrik@example.org"]
        )

        let target = MailRootQuickReplyPolicy.target(
            in: [inbound, outbound],
            accountEmail: "henrik@example.org"
        )

        #expect(target?.id == "inbound")
    }

    @Test("all-self thread has no quick-reply target")
    func allSelfThreadHasNoTarget() {
        let headers = [
            Self.header(id: "older", sender: "henrik@example.org", date: 1),
            Self.header(id: "newer", sender: "henrik@example.org", date: 2),
        ]

        #expect(MailRootQuickReplyPolicy.target(
            in: headers,
            accountEmail: "henrik@example.org"
        ) == nil)
    }

    private static func header(
        id: String,
        sender: String,
        date: TimeInterval,
        recipients: [String] = []
    ) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "thread",
            folderID: "inbox",
            from: Correspondent(name: sender, email: sender),
            to: recipients.map { Correspondent(email: $0) },
            subject: "Subject",
            snippet: "Snippet",
            date: Date(timeIntervalSince1970: date)
        )
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
    @Test("detail toolbars condense secondary actions on every platform")
    func detailToolbarsCondenseSecondaryActions() {
        #expect(MailRootDetailToolbarPolicy.usesCondensedLayout(platform: .iOS))
        #expect(MailRootDetailToolbarPolicy.usesCondensedLayout(platform: .macOS))
    }

    @Test("secondary response actions stay in More on every platform")
    func secondaryResponseActionsStayInMore() {
        #expect(!MailRootDetailToolbarPolicy.showsExtendedResponseActions(platform: .macOS))
        #expect(!MailRootDetailToolbarPolicy.showsExtendedResponseActions(platform: .iOS))
    }

    @Test("settings has one entry point in the iOS mailbox sidebar")
    func settingsShowsInSidebarAndIOSMessageListToolbars() {
        #expect(MailRootSettingsToolbarPolicy.showsSettingsButton(
            on: .sidebar,
            platform: .iOS
        ))
        #expect(!MailRootSettingsToolbarPolicy.showsSettingsButton(
            on: .messageList,
            platform: .iOS
        ))
        #expect(!MailRootSettingsToolbarPolicy.showsSettingsButton(
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

    @Test("Flag stays in the overflow menu")
    func flagStaysInOverflowMenu() {
        #expect(!MailRootDetailToolbarPolicy.showsFlagButton(platform: .macOS))
        #expect(!MailRootDetailToolbarPolicy.showsFlagButton(platform: .iOS))
    }

    @Test("organizer actions stay in More on every platform")
    func organizerActionsStayInMore() {
        #expect(!MailRootDetailToolbarPolicy.showsMessageOrganizerActions(platform: .macOS))
        #expect(!MailRootDetailToolbarPolicy.showsMessageOrganizerActions(platform: .iOS))
        #expect(!MailRootDetailToolbarPolicy.showsExtendedResponseActions(
            platform: .macOS, readerWidth: nil
        ))
    }

    @Test("the reader width settles past the longest gap in a column animation")
    func readerWidthSettleOutlastsColumnAnimationGaps() {
        // Revealing the folder sidebar animates in bursts with stalls
        // between them — measured at 107ms and 123ms on a 60fps capture.
        // A settle shorter than those would fire inside a stall and hand
        // the expanded search field a width the animation had not finished moving.
        #expect(MailRootDetailToolbarPolicy.readerWidthSettleDuration >= .milliseconds(150))

        // It still has to be short enough that releasing a divider drag
        // reads as immediate.
        #expect(MailRootDetailToolbarPolicy.readerWidthSettleDuration <= .milliseconds(300))
    }

    @Test("message-list account context prefers a quiet display name")
    func messageListAccountContextPrefersQuietDisplayName() {
        #expect(MailRootMessageListTitlePolicy.accountContext(
            mailboxDisplayName: "Personal",
            accountDisplayName: "Henrik",
            mailboxEmail: "henrik@example.org"
        ) == "Personal")
        #expect(MailRootMessageListTitlePolicy.accountContext(
            mailboxDisplayName: "henrik@example.org",
            accountDisplayName: "Henrik",
            mailboxEmail: "henrik@example.org"
        ) == "Henrik")
    }

    @Test("message-list account context requires a single-account folder")
    func messageListAccountContextRequiresSingleAccountFolder() {
        #expect(MailRootMessageListTitlePolicy.showsAccountContext(
            hasSelectedFolder: true,
            isUnifiedInboxSelected: false,
            isSmartViewSelected: false,
            isAllAttachmentsSelected: false,
            hasSelectedSavedSearch: false
        ))
        #expect(!MailRootMessageListTitlePolicy.showsAccountContext(
            hasSelectedFolder: true,
            isUnifiedInboxSelected: true,
            isSmartViewSelected: false,
            isAllAttachmentsSelected: false,
            hasSelectedSavedSearch: false
        ))
        #expect(!MailRootMessageListTitlePolicy.showsAccountContext(
            hasSelectedFolder: true,
            isUnifiedInboxSelected: false,
            isSmartViewSelected: true,
            isAllAttachmentsSelected: false,
            hasSelectedSavedSearch: false
        ))
        #expect(!MailRootMessageListTitlePolicy.showsAccountContext(
            hasSelectedFolder: false,
            isUnifiedInboxSelected: false,
            isSmartViewSelected: false,
            isAllAttachmentsSelected: false,
            hasSelectedSavedSearch: false
        ))
    }

    @Test("message-list unread count follows the selected destination")
    func messageListUnreadCountFollowsSelectedDestination() {
        #expect(MailRootMessageListTitlePolicy.unreadCount(
            isUnifiedInboxSelected: true,
            isSmartViewSelected: false,
            isAllAttachmentsSelected: false,
            hasSelectedSavedSearch: false,
            selectedFolderUnreadCount: nil,
            unifiedInboxUnreadCounts: [2, 3, 4]
        ) == 9)
        #expect(MailRootMessageListTitlePolicy.unreadCount(
            isUnifiedInboxSelected: false,
            isSmartViewSelected: false,
            isAllAttachmentsSelected: false,
            hasSelectedSavedSearch: false,
            selectedFolderUnreadCount: 7,
            unifiedInboxUnreadCounts: []
        ) == 7)
        #expect(MailRootMessageListTitlePolicy.unreadCount(
            isUnifiedInboxSelected: false,
            isSmartViewSelected: true,
            isAllAttachmentsSelected: false,
            hasSelectedSavedSearch: false,
            selectedFolderUnreadCount: 7,
            unifiedInboxUnreadCounts: []
        ) == nil)
        #expect(MailRootMessageListTitlePolicy.unreadCount(
            isUnifiedInboxSelected: true,
            isSmartViewSelected: false,
            isAllAttachmentsSelected: false,
            hasSelectedSavedSearch: false,
            selectedFolderUnreadCount: nil,
            unifiedInboxUnreadCounts: [0, 0]
        ) == nil)
        #expect(MailRootMessageListTitlePolicy.unreadCount(
            isUnifiedInboxSelected: false,
            isSmartViewSelected: false,
            isAllAttachmentsSelected: false,
            hasSelectedSavedSearch: false,
            selectedFolderUnreadCount: 0,
            unifiedInboxUnreadCounts: []
        ) == nil)
    }

    @Test("message-list account context falls back to a stable email identity")
    func messageListAccountContextFallsBackToStableEmailIdentity() {
        #expect(MailRootMessageListTitlePolicy.accountContext(
            mailboxDisplayName: "henrik@example.org",
            accountDisplayName: "henrik@example.org",
            mailboxEmail: "henrik@example.org"
        ) == "henrik@example.org")
    }

    @Test("message-list folder title matches the mailbox sidebar display name")
    func messageListFolderTitleMatchesMailboxSidebarDisplayName() {
        let sourceID = MailSourceID(accountID: "account", mailboxID: "primary")
        let drafts = Folder(id: "drafts", name: "Entwürfe", role: .drafts)

        // Role folders read as the standard name rather than the server name.
        #expect(MailRootMessageListTitlePolicy.folderTitle(
            folder: drafts,
            sourceID: sourceID,
            aliasPreferences: .defaults
        ) == "Drafts")

        // A Brev-local alias outranks the standard name.
        #expect(MailRootMessageListTitlePolicy.folderTitle(
            folder: drafts,
            sourceID: sourceID,
            aliasPreferences: FolderAliasPreferences(aliases: [
                FolderAliasPreference(
                    folderID: SourceFolderID(sourceID: sourceID, folderID: "drafts"),
                    name: "Kladder"
                )
            ])
        ) == "Kladder")

        // Custom folders keep the name the server gave them.
        #expect(MailRootMessageListTitlePolicy.folderTitle(
            folder: Folder(id: "projects", name: "Projects", role: .custom),
            sourceID: sourceID,
            aliasPreferences: .defaults
        ) == "Projects")
    }
}

@Suite("MailRootComposeSurface")
struct MailRootComposeSurfaceTests {
    @Test("iPad at regular width composes in a sheet, not a second window")
    func regularWidthIPadUsesSheet() {
        #expect(MailRootComposePresentationPolicy.surface(idiom: .pad, isRegularWidth: true) == .sheet)
    }

    @Test("iPhone and compact iPad compose in a sheet")
    func compactSurfacesUseSheet() {
        #expect(MailRootComposePresentationPolicy.surface(idiom: .phone, isRegularWidth: false) == .sheet)
        #expect(MailRootComposePresentationPolicy.surface(idiom: .pad, isRegularWidth: false) == .sheet)
    }

    @Test("a new window is opened only when it is requested on an iPad at regular width")
    func explicitRequestOpensWindow() {
        #expect(MailRootComposePresentationPolicy.surface(
            idiom: .pad, isRegularWidth: true, requestedNewWindow: true
        ) == .detachedWindow)
        #expect(MailRootComposePresentationPolicy.surface(
            idiom: .pad, isRegularWidth: false, requestedNewWindow: true
        ) == .sheet)
        #expect(MailRootComposePresentationPolicy.surface(
            idiom: .phone, isRegularWidth: true, requestedNewWindow: true
        ) == .sheet)
    }
}
