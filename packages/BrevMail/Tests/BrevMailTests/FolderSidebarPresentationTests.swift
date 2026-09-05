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
import Testing

@Suite("FolderSidebarPresentation")
struct FolderSidebarPresentationTests {
    @Test("reselecting the active destination still requests the message list")
    func reselectingActiveDestinationRequestsMessageList() {
        var selectedFolderID = "inbox"
        var activationCount = 0

        FolderSidebarDestinationActivation.activate(
            selection: { selectedFolderID = "inbox" },
            onActivated: { activationCount += 1 }
        )

        #expect(selectedFolderID == "inbox")
        #expect(activationCount == 1)
    }

    @Test("load errors render an error status")
    func loadErrorsRenderErrorStatus() {
        #expect(FolderSidebarPresentation.status(
            folders: [],
            loadError: FolderLoadError(
                message: "Network error: offline",
                isNetworkError: true
            )
        ) == FolderSidebarStatus(
            title: "Couldn't load folders",
            icon: "exclamationmark.triangle",
            subtitle: "Network error: offline",
            actionTitle: "Try Again"
        ))
    }

    @Test("load errors with cached folders render a stale state")
    func loadErrorsWithCachedFoldersRenderAStaleState() {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)

        #expect(FolderSidebarPresentation.status(
            folders: [inbox],
            loadError: FolderLoadError(
                message: "Offline",
                isNetworkError: true
            )
        ) == FolderSidebarStatus(
            title: "Folders may be stale",
            icon: "wifi.slash",
            subtitle: "Showing cached folders while Brev retries: Offline",
            actionTitle: "Retry"
        ))
    }

    @Test("blank load errors render a fallback subtitle")
    func blankLoadErrorsRenderFallbackSubtitle() {
        #expect(FolderSidebarPresentation.status(
            folders: [],
            loadError: FolderLoadError(
                message: " ",
                isNetworkError: false
            )
        ) == FolderSidebarStatus(
            title: "Couldn't load folders",
            icon: "exclamationmark.triangle",
            subtitle: "Couldn't load folders.",
            actionTitle: "Try Again"
        ))
    }

    @Test("empty successful loads render an empty status")
    func emptySuccessfulLoadsRenderEmptyStatus() {
        #expect(FolderSidebarPresentation.status(
            folders: [],
            loadError: nil
        ) == FolderSidebarStatus(
            title: "Setting up your Inbox",
            icon: "arrow.triangle.2.circlepath",
            subtitle: "Brev is checking this account for folders. Your mail will appear here when the first sync finishes.",
            actionTitle: "Check Again"
        ))
    }

    @Test("loaded folders render the folder list")
    func loadedFoldersRenderFolderList() {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)

        #expect(FolderSidebarPresentation.status(folders: [inbox], loadError: nil) == nil)
    }

    @Test("context menu enables mark all as read when unread messages exist")
    func contextMenuEnablesMarkAllAsReadWhenUnreadMessagesExist() {
        let folder = Folder(
            id: "receipts",
            name: "Receipts",
            role: .custom,
            unreadCount: 3
        )

        let presentation = FolderSidebarPresentation.contextMenu(
            folder: folder,
            capabilities: [.folderCreate, .folderRename, .folderDelete, .folderFlush],
            isActionBlocked: false
        )

        #expect(presentation.canMarkAllAsRead)
    }

    @Test("selected sidebar rows use the compact control radius")
    func selectedSidebarRowsUseCompactControlRadius() {
        #expect(FolderSidebarSelectionPresentation.cornerRadius == BrevRadius.md)
    }

    @Test("global sidebar selections stay quieter than mailbox selections")
    func globalSidebarSelectionsStayQuieterThanMailboxSelections() {
        #expect(FolderSidebarSelectionPresentation.globalActionOpacity < 1)
    }

    @Test("accent-driven selection keeps global controls quieter than folders")
    func accentDrivenSelectionKeepsGlobalControlsQuieterThanFolders() {
        #expect(
            FolderSidebarSelectionPresentation.globalActionOpacity
                < FolderSidebarSelectionPresentation.folderOpacity
        )
        #expect(FolderSidebarSelectionPresentation.folderOpacity < 1)
    }

    @Test("sidebar controls keep reliable touch targets")
    func sidebarControlsKeepReliableTouchTargets() {
        let metrics = FolderSidebarPresentation.layoutMetrics(for: .iPhone)

        #expect(metrics.profilePickerMinimumHeight >= 44)
        #expect(metrics.disclosureHitSize >= 44)
        #expect(metrics.folderRowMinimumHeight >= 44)
        #expect(metrics.unreadBadgeMinimumWidth >= 20)
        #expect(metrics.unreadBadgeMinimumHeight >= 18)
    }

    @Test("macOS sidebar metrics use denser source-list rows")
    func macOSSidebarMetricsUseDenserSourceListRows() {
        let touchMetrics = FolderSidebarPresentation.layoutMetrics(for: .iPhone)
        let macMetrics = FolderSidebarPresentation.layoutMetrics(for: .macOS)

        #expect(macMetrics.folderRowMinimumHeight < touchMetrics.folderRowMinimumHeight)
        #expect(macMetrics.sourceHeaderMinimumHeight < touchMetrics.sourceHeaderMinimumHeight)
        #expect(macMetrics.disclosureHitSize < touchMetrics.disclosureHitSize)
        #expect(macMetrics.folderRowDepthIndent < touchMetrics.folderRowDepthIndent)
    }

    @Test("macOS sidebar rows follow the shared density preference")
    func macOSSidebarRowsFollowSharedDensity() {
        let compact = FolderSidebarPresentation.layoutMetrics(
            for: .macOS,
            density: .compact
        )
        let spacious = FolderSidebarPresentation.layoutMetrics(
            for: .macOS,
            density: .spacious
        )

        #expect(compact.folderRowVerticalPadding == MailboxListDensity.compact.sidebarRowVerticalPadding)
        #expect(spacious.folderRowVerticalPadding == MailboxListDensity.spacious.sidebarRowVerticalPadding)
        #expect(compact.folderRowMinimumHeight < spacious.folderRowMinimumHeight)
    }

    @Test("touch sidebar density preserves minimum control targets")
    func touchSidebarDensityPreservesControlTargets() {
        let compact = FolderSidebarPresentation.layoutMetrics(
            for: .iPhone,
            density: .compact
        )

        #expect(compact.profilePickerMinimumHeight >= 44)
        #expect(compact.disclosureHitSize >= 44)
        // Density may reduce the visible padding, but never the iOS hit region.
        #expect(compact.folderRowMinimumHeight >= 44)
        #expect(compact.folderRowMinimumHeight == FolderSidebarPresentation.layoutMetrics(for: .iPhone).folderRowMinimumHeight)
        #expect(compact.folderRowVerticalPadding == MailboxListDensity.compact.sidebarRowVerticalPadding)
    }

    @Test("source disclosure initially expands the selected account")
    func sourceDisclosureInitiallyExpandsSelectedAccount() {
        let first = MailSourceID(accountID: "first", mailboxID: "primary")
        let selected = MailSourceID(accountID: "selected", mailboxID: "primary")

        #expect(FolderSidebarSourceExpansionPolicy.initialExpandedSourceIDs(
            sourceIDs: [first, selected],
            selectedSourceID: selected
        ) == [selected])
        #expect(FolderSidebarSourceExpansionPolicy.initialExpandedSourceIDs(
            sourceIDs: [first, selected],
            selectedSourceID: nil
        ) == [first])
    }

    @Test("selecting mail from another account expands that source")
    func selectingAnotherAccountExpandsItsSource() {
        let first = MailSourceID(accountID: "first", mailboxID: "primary")
        let selected = MailSourceID(accountID: "selected", mailboxID: "primary")

        #expect(FolderSidebarSourceExpansionPolicy.expandingSelection(
            selected,
            in: [first]
        ) == [first, selected])
    }

    @Test("source disclosure toggles without affecting other accounts")
    func sourceDisclosureTogglesIndependently() {
        let first = MailSourceID(accountID: "first", mailboxID: "primary")
        let second = MailSourceID(accountID: "second", mailboxID: "primary")

        #expect(FolderSidebarSourceExpansionPolicy.toggling(first, in: [first, second]) == [second])
        #expect(FolderSidebarSourceExpansionPolicy.toggling(first, in: [second]) == [first, second])
    }

    @Test("smart views reveal themselves when one of them is selected")
    func smartViewsRevealThemselvesWhenOneIsSelected() {
        #expect(FolderSidebarSmartViewPresentation.isExpanded(
            userExpanded: nil,
            hasSelectedSmartView: false
        ) == false)
        #expect(FolderSidebarSmartViewPresentation.isExpanded(
            userExpanded: nil,
            hasSelectedSmartView: true
        ))
    }

    @Test("the section still collapses while one of its smart views is selected")
    func theSectionStillCollapsesWhileASmartViewIsSelected() {
        // Auto-reveal was an `||`, so a selected smart view held the section open
        // and the disclosure control did nothing — the state it most needed to
        // collapse from was the one state it could not.
        #expect(FolderSidebarSmartViewPresentation.isExpanded(
            userExpanded: false,
            hasSelectedSmartView: true
        ) == false)
    }

    @Test("toggling always flips what is on screen")
    func togglingAlwaysFlipsWhatIsOnScreen() {
        for userExpanded in [nil, true, false] as [Bool?] {
            for hasSelected in [true, false] {
                let before = FolderSidebarSmartViewPresentation.isExpanded(
                    userExpanded: userExpanded,
                    hasSelectedSmartView: hasSelected
                )
                let toggled = FolderSidebarSmartViewPresentation.toggled(
                    userExpanded: userExpanded,
                    hasSelectedSmartView: hasSelected
                )
                let after = FolderSidebarSmartViewPresentation.isExpanded(
                    userExpanded: toggled,
                    hasSelectedSmartView: hasSelected
                )

                #expect(after == !before)
            }
        }
    }

    @Test("context menu exposes hide action for source-scoped folders")
    func contextMenuExposesHideActionForSourceScopedFolders() {
        let folder = Folder(id: "projects", name: "Projects", role: .custom)
        let presentation = FolderSidebarPresentation.contextMenu(
            folder: folder,
            capabilities: [],
            isActionBlocked: false,
            hasSourceIdentity: true
        )

        #expect(presentation.canHideFolder)
    }

    @Test("context menu exposes local name actions for source-scoped folders")
    func contextMenuExposesLocalNameActionsForSourceScopedFolders() {
        let folder = Folder(id: "inbox", name: "INBOX", role: .inbox)
        let presentation = FolderSidebarPresentation.contextMenu(
            folder: folder,
            capabilities: [],
            isActionBlocked: false,
            hasSourceIdentity: true,
            hasLocalAlias: true
        )

        #expect(presentation.canSetLocalName)
        #expect(presentation.canClearLocalName)
    }

    @Test("folder context menu exposes grouped desktop actions")
    func folderContextMenuExposesGroupedDesktopActions() {
        let folder = Folder(
            id: "projects",
            name: "Projects",
            role: .custom,
            unreadCount: 2
        )
        let menu = FolderSidebarPresentation.desktopContextMenu(
            folder: folder,
            capabilities: [.folderCreate, .folderRename, .folderDelete],
            isActionBlocked: false,
            hasSourceIdentity: true,
            hasLocalAlias: true,
            hasChildren: true,
            isExpanded: true,
            canExpandAll: false,
            canCollapseAll: true,
            canOpenAccountSettings: true
        )

        #expect(menu.sections.map { $0.actions.map(\.action) } == [
            [.newSubfolder],
            [.collapseAll],
            [.markAllAsRead],
            [.setLocalName, .clearLocalName, .hideFromMailboxList],
            [.renameFolder, .deleteFolder],
            [.refresh],
            [.accountSettings]
        ])
        #expect(menu.action(.collapseAll)?.title == "Collapse All")
        #expect(menu.action(.markAllAsRead)?.isEnabled == true)
        #expect(menu.action(.deleteFolder)?.role == .destructive)
        #expect(menu.action(.openInNewWindow) == nil)
        #expect(menu.action(.showInProfile) == nil)
        #expect(menu.action(.properties) == nil)
        #expect(menu.action(.downloadOffline) == nil)
    }

    @Test("folder display name resolves local alias before standard role names")
    func folderDisplayNameResolvesLocalAliasBeforeStandardRoleNames() {
        let sourceID = MailSourceID(accountID: "acct-1", mailboxID: "personal")
        let inbox = Folder(id: "inbox", name: "INBOX", role: .inbox)
        let preferences = FolderAliasPreferencesPolicy.settingAlias(
            "Home",
            folderID: inbox.id,
            sourceID: sourceID,
            in: .defaults
        )

        #expect(FolderSidebarPresentation.displayName(
            for: inbox,
            sourceID: sourceID,
            aliasPreferences: preferences
        ) == "Home")
        #expect(FolderSidebarPresentation.displayName(
            for: inbox,
            sourceID: nil,
            aliasPreferences: preferences
        ) == "Inbox")
    }

    @Test("folder tree rows preserve nested mailbox groups")
    func folderTreeRowsPreserveNestedMailboxGroups() {
        let archive = Folder(id: "archive", name: "Archive", role: .archive)
        let receipts = Folder(id: "receipts", name: "Receipts", role: .custom, parentID: archive.id)
        let licenses = Folder(id: "licenses", name: "Licenses", role: .custom, parentID: receipts.id)
        let newsletters = Folder(id: "newsletters", name: "Newsletters", role: .custom, parentID: archive.id)
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)

        let rows = FolderSidebarPresentation.visibleRows(
            folders: [archive, receipts, licenses, newsletters, inbox],
            collapsedFolderIDs: []
        )

        #expect(rows.map { $0.folder.id } == ["archive", "receipts", "licenses", "newsletters", "inbox"])
        #expect(rows.map(\.depth) == [0, 1, 2, 1, 0])
        #expect(rows.map(\.hasChildren) == [true, true, false, false, false])
    }

    @Test("mock nested folder snapshot fixture keeps stable rows")
    func mockNestedFolderSnapshotFixtureKeepsStableRows() {
        let rows = FolderSidebarPresentation.visibleRows(
            folders: MockBackend.previewFolders,
            collapsedFolderIDs: []
        )

        #expect(rows.map { $0.folder.id } == [
            "inbox",
            "drafts",
            "sent",
            "archive",
            "archive-home",
            "archive-travel",
            "archive-receipts",
            "archive-receipts-licenses",
            "archive-newsletters",
            "mailspring",
            "mailspring-snoozed",
            "promotions",
            "social-networks",
            "spam",
            "trash"
        ])
        #expect(rows.map(\.depth) == [
            0,
            0,
            0,
            0,
            1,
            1,
            1,
            2,
            1,
            0,
            1,
            0,
            0,
            0,
            0
        ])
        #expect(rows.map { $0.folder.unreadCount } == [
            6,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            1479,
            0,
            0,
            591,
            14,
            87,
            1
        ])
    }

    @Test("collapsed folder tree rows hide descendants")
    func collapsedFolderTreeRowsHideDescendants() {
        let archive = Folder(id: "archive", name: "Archive", role: .archive)
        let receipts = Folder(id: "receipts", name: "Receipts", role: .custom, parentID: archive.id)
        let licenses = Folder(id: "licenses", name: "Licenses", role: .custom, parentID: receipts.id)
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)

        let rows = FolderSidebarPresentation.visibleRows(
            folders: [archive, receipts, licenses, inbox],
            collapsedFolderIDs: [archive.id]
        )

        #expect(rows.map { $0.folder.id } == ["archive", "inbox"])
        #expect(rows.map(\.depth) == [0, 0])
        #expect(rows.map(\.hasChildren) == [true, false])
    }

    @Test("hidden standard folders are omitted from sidebar rows")
    func hiddenStandardFoldersAreOmittedFromRows() {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let starred = Folder(id: "flagged", name: "Flagged", role: .starred)
        let starChild = Folder(id: "flag-child", name: "Flag child", role: .custom, parentID: starred.id)
        let archive = Folder(id: "archive", name: "Archive", role: .archive)
        let archiveChild = Folder(id: "archive-child", name: "Archive child", role: .custom, parentID: archive.id)

        let visibility = FolderSidebarVisibilityPreferences(
            showStarred: false,
            showSnoozed: true,
            showScheduled: true,
            showAllMail: false,
            showSpam: true,
            showTrash: true,
            showArchive: true
        )

        let rows = FolderSidebarPresentation.visibleRows(
            folders: [starred, starChild, inbox, archive, archiveChild],
            visibility: visibility,
            collapsedFolderIDs: []
        )

        #expect(rows.map { $0.folder.id } == ["inbox", "archive", "archive-child"])
        #expect(rows.map(\.depth) == [0, 0, 1])
    }

    @Test("hidden folder descendants are hidden with role filtering")
    func hiddenFolderDescendantsAreHiddenWithRoleFiltering() {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let allMail = Folder(id: "allMail", name: "All Mail", role: .allMail)
        let allMailChild = Folder(id: "allMailChild", name: "Nested all-mail folder", role: .custom, parentID: allMail.id)

        let rows = FolderSidebarPresentation.visibleRows(
            folders: [allMail, allMailChild, inbox],
            visibility: .defaults,
            collapsedFolderIDs: []
        )

        #expect(rows.map { $0.folder.id } == ["inbox"])
    }

    @Test("mailbox header is enabled without pending switch work")
    func mailboxHeaderIsEnabledWithoutPendingSwitchWork() {
        #expect(FolderSidebarPresentation.mailboxHeader(
            isSwitchingMailbox: false,
            isBlocked: false
        ) == FolderSidebarMailboxHeaderPresentation(
            isDisabled: false,
            statusMessage: nil
        ))
    }

    @Test("mailbox header is disabled and labeled while switching")
    func mailboxHeaderIsDisabledAndLabeledWhileSwitching() {
        #expect(FolderSidebarPresentation.mailboxHeader(
            isSwitchingMailbox: true,
            isBlocked: false
        ) == FolderSidebarMailboxHeaderPresentation(
            isDisabled: true,
            statusMessage: "Switching mailbox…"
        ))
    }

    @Test("mailbox header is disabled while root work is active")
    func mailboxHeaderIsDisabledWhileRootWorkIsActive() {
        #expect(FolderSidebarPresentation.mailboxHeader(
            isSwitchingMailbox: false,
            isBlocked: true
        ) == FolderSidebarMailboxHeaderPresentation(
            isDisabled: true,
            statusMessage: "Finishing current action…"
        ))
    }

    @Test("custom folders expose create, rename, and delete actions")
    func customFolderContextActions() {
        let folder = Folder(id: "custom", name: "Projects", role: .custom)
        let presentation = FolderSidebarPresentation.contextMenu(
            folder: folder,
            capabilities: [.folderCreate, .folderRename, .folderDelete, .folderFlush],
            isActionBlocked: false
        )

        #expect(presentation.canCreateSubfolder)
        #expect(presentation.canRenameFolder)
        #expect(presentation.canDeleteFolder)
        #expect(!presentation.canFlushFolder)
        #expect(presentation.flushActionTitle == "Empty Folder")
    }

    @Test("trash folders expose destructive flush actions")
    func trashFolderContextActions() {
        let folder = Folder(id: "trash", name: "Trash", role: .trash)
        let presentation = FolderSidebarPresentation.contextMenu(
            folder: folder,
            capabilities: [.folderFlush],
            isActionBlocked: false
        )

        #expect(!presentation.canCreateSubfolder)
        #expect(!presentation.canRenameFolder)
        #expect(!presentation.canDeleteFolder)
        #expect(presentation.canFlushFolder)
        #expect(presentation.flushActionTitle == "Empty Trash")
    }

    @Test("context actions are disabled while root work is active")
    func contextActionsAreDisabledWhileBlocked() {
        let folder = Folder(id: "custom", name: "Blocked", role: .custom)
        let presentation = FolderSidebarPresentation.contextMenu(
            folder: folder,
            capabilities: [.folderCreate, .folderRename, .folderDelete, .folderFlush],
            isActionBlocked: true
        )

        #expect(!presentation.canCreateSubfolder)
        #expect(!presentation.canRenameFolder)
        #expect(!presentation.canDeleteFolder)
        #expect(!presentation.canFlushFolder)
    }
}
