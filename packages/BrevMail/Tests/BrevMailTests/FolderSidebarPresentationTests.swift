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
import Foundation
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

    @Test("arrow navigation changes the mailbox without moving focus into messages")
    func arrowSelectionKeepsSidebarFocus() {
        var selectedFolderID = "inbox"
        var activationCount = 0
        FolderSidebarDestinationActivation.activate(
            selection: { selectedFolderID = "drafts" },
            onActivated: { activationCount += 1 }, opensMessages: false
        )
        #expect(selectedFolderID == "drafts")
        #expect(activationCount == 0)
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
            title: String(localized: "couldntLoadFolders.plain", bundle: .module),
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
            title: String(localized: "couldntLoadFolders.plain", bundle: .module),
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
        #expect(macMetrics.disclosureHitSize >= 16)
        #expect(macMetrics.folderRowDepthIndent == macMetrics.iconWidth)
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
        #expect(compact.folderRowVerticalPadding == 0)
    }

    @Test("phone folders use compact 44 point rows without stacked padding")
    func phoneFoldersAvoidStackedPadding() {
        let metrics = FolderSidebarPresentation.layoutMetrics(for: .iPhone)
        #expect(metrics.folderRowMinimumHeight + 2 * metrics.folderRowVerticalPadding == 44)
        #expect(metrics.sectionSpacing == 0)
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

    @Test("unread counts speak as a phrase and stay silent at zero")
    func unreadValueSpeaksAPhrase() {
        #expect(FolderSidebarAccessibility.unreadValue(count: 16) == "16 unread")
        #expect(FolderSidebarAccessibility.unreadValue(count: 1) == "1 unread")
        #expect(FolderSidebarAccessibility.unreadValue(count: 0) == nil)
        #expect(FolderSidebarAccessibility.unreadValue(count: -3) == nil)
    }

    @Test("an expanded account header announces only its state")
    func expandedAccountHeaderValue() {
        let value = FolderSidebarAccessibility.accountHeaderValue(isExpanded: true, unreadCount: 11)
        #expect(value == "Expanded mailbox")
    }

    @Test("a collapsed account header keeps its unread badge in the spoken value")
    func collapsedAccountHeaderValueIncludesUnread() {
        let value = FolderSidebarAccessibility.accountHeaderValue(isExpanded: false, unreadCount: 11)
        #expect(value == "Collapsed mailbox, 11 unread")
        let none = FolderSidebarAccessibility.accountHeaderValue(isExpanded: false, unreadCount: 0)
        #expect(none == "Collapsed mailbox")
    }

    @Test("the Mailboxes title follows the active profile")
    func navigationTitleFollowsProfile() {
        let source = MailSourceID(accountID: "a", mailboxID: "m")
        let focused = MailProfile(id: "focused", name: "Focused", sourceIDs: [source])
        let profiles = [MailProfile.allMailboxes(sourceIDs: [source]), focused]
        #expect(FolderSidebarPresentation.navigationTitle(
            activeProfileID: MailProfile.allMailboxesID, profiles: profiles
        ) == "Mailboxes")
        #expect(FolderSidebarPresentation.navigationTitle(
            activeProfileID: "focused", profiles: profiles
        ) == "Focused")
        #expect(FolderSidebarPresentation.navigationTitle(
            activeProfileID: "deleted-profile", profiles: profiles
        ) == "Mailboxes")
        #expect(FolderSidebarPresentation.navigationTitle(
            activeProfileID: "focused", profiles: []
        ) == "Mailboxes")
    }

    @Test("fresh macOS disclosure state collapses nested subfolders by default")
    func freshDisclosureStateDefaultsNestedSubfoldersCollapsed() throws {
        let sourceID = MailSourceID(accountID: "acct-1", mailboxID: "personal")
        let folders = MockBackend.previewFolders
        var state = FolderDisclosureState.load(from: Data(), defaultCollapsed: true)

        let collapsed = state.collapsedFolderIDs(for: sourceID, folders: folders)
        #expect(collapsed == ["archive", "archive-receipts", "mailspring"])

        let initialRows = FolderSidebarPresentation.visibleRows(
            folders: folders,
            collapsedFolderIDs: collapsed
        )
        #expect(initialRows.map { $0.folder.id } == [
            "inbox",
            "drafts",
            "sent",
            "archive",
            "mailspring",
            "promotions",
            "social-networks",
            "spam",
            "trash",
        ])

        // Expanding Archive reveals direct children while keeping nested Receipts collapsed.
        state.toggle("archive", sourceID: sourceID)
        #expect(state.isExpanded("archive", sourceID: sourceID, folders: folders))
        #expect(!state.isExpanded("archive-receipts", sourceID: sourceID, folders: folders))
        let afterArchiveExpand = FolderSidebarPresentation.visibleRows(
            folders: folders,
            collapsedFolderIDs: state.collapsedFolderIDs(for: sourceID, folders: folders)
        )
        #expect(afterArchiveExpand.contains { $0.folder.id == "archive-receipts" })
        #expect(!afterArchiveExpand.contains { $0.folder.id == "archive-receipts-licenses" })

        // Round-trip persistence preserves the default-collapsed mode and expanded set.
        let encoded = try JSONEncoder().encode(state)
        let restored = FolderDisclosureState.load(from: encoded, defaultCollapsed: true)
        #expect(restored == state)

        // Expand All and Collapse All cover every collapsible folder in the source.
        state.setAllExpanded(true, sourceID: sourceID, folders: folders)
        #expect(state.collapsedFolderIDs(for: sourceID, folders: folders).isEmpty)
        state.setAllExpanded(false, sourceID: sourceID, folders: folders)
        #expect(state.collapsedFolderIDs(for: sourceID, folders: folders) == [
            "archive",
            "archive-receipts",
            "mailspring",
        ])
    }

    @Test("legacy persisted disclosure payloads preserve open-by-default semantics")
    func legacyDisclosurePayloadPreservesExplicitCollapsedSet() throws {
        struct LegacyDisclosurePayload: Encodable {
            let bySource: [MailSourceID: Set<Folder.ID>]
            let withoutSource: Set<Folder.ID>
        }
        let legacyJSON = try JSONEncoder().encode(
            LegacyDisclosurePayload(bySource: [:], withoutSource: ["archive"])
        )
        let state = FolderDisclosureState.load(from: legacyJSON, defaultCollapsed: true)

        #expect(!state.usesDefaultCollapsed)
        #expect(state.collapsedFolderIDs(for: nil, folders: MockBackend.previewFolders) == ["archive"])
        #expect(!state.isExpanded("archive", sourceID: nil, folders: MockBackend.previewFolders))
        #expect(state.isExpanded("mailspring", sourceID: nil, folders: MockBackend.previewFolders))
    }

    @Test("external folder navigation reveals only the selected folder's ancestors while keeping sibling branches collapsed")
    func externalNavigationRevealsSelectedFolderAncestorsOnly() {
        let sourceID = MailSourceID(accountID: "acct-1", mailboxID: "primary")
        let folders = [
            Folder(id: "inbox", name: "Inbox", role: .inbox),
            Folder(id: "archive", name: "Archive", role: .archive),
            Folder(id: "archive-home", name: "Home", role: .custom, parentID: "archive"),
            Folder(id: "projects", name: "Projects", role: .custom),
            Folder(id: "projects-2026", name: "2026", role: .custom, parentID: "projects"),
            Folder(id: "projects-2026-q4", name: "Q4", role: .custom, parentID: "projects-2026"),
        ]
        var state = FolderDisclosureState.load(from: Data(), defaultCollapsed: true)

        // Initially both Archive and Projects branches are collapsed.
        #expect(!state.isExpanded("archive", sourceID: sourceID, folders: folders))
        #expect(!state.isExpanded("projects", sourceID: sourceID, folders: folders))
        #expect(!state.isExpanded("projects-2026", sourceID: sourceID, folders: folders))

        // Selecting Projects/2026 expands Projects without expanding Archive or Projects/2026's own children.
        let changed = state.revealAncestors(of: "projects-2026", sourceID: sourceID, folders: folders)
        #expect(changed)
        #expect(state.isExpanded("projects", sourceID: sourceID, folders: folders))
        #expect(!state.isExpanded("projects-2026", sourceID: sourceID, folders: folders))
        #expect(!state.isExpanded("archive", sourceID: sourceID, folders: folders))

        let visibleIDs = FolderSidebarPresentation.visibleRows(
            folders: folders,
            collapsedFolderIDs: state.collapsedFolderIDs(for: sourceID, folders: folders)
        ).map(\.folder.id)
        #expect(visibleIDs == ["inbox", "archive", "projects", "projects-2026"])

        // Deeply nested navigation (Q4) reveals both Projects and 2026, still leaving Archive collapsed.
        let revealedDeep = state.revealAncestors(of: "projects-2026-q4", sourceID: sourceID, folders: folders)
        #expect(revealedDeep)
        #expect(state.isExpanded("projects", sourceID: sourceID, folders: folders))
        #expect(state.isExpanded("projects-2026", sourceID: sourceID, folders: folders))
        #expect(!state.isExpanded("archive", sourceID: sourceID, folders: folders))

        // Manual collapse after reveal still works cleanly.
        state.toggle("projects", sourceID: sourceID)
        #expect(!state.isExpanded("projects", sourceID: sourceID, folders: folders))
    }

    @Test("iOS/iPadOS external folder navigation preserves manually collapsed parent folders")
    func nonMacOSExternalNavigationPreservesManualCollapse() throws {
        let sourceID = MailSourceID(accountID: "acct-1", mailboxID: "primary")
        let folders = [
            Folder(id: "inbox", name: "Inbox", role: .inbox),
            Folder(id: "projects", name: "Projects", role: .custom),
            Folder(id: "projects-2026", name: "2026", role: .custom, parentID: "projects"),
        ]
        // On iOS/iPadOS branches default to expanded and the user manually collapses Projects.
        var state = FolderDisclosureState.load(from: Data(), defaultCollapsed: false)
        state.toggle("projects", sourceID: sourceID)
        let stateBefore = state
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let persistedBefore = try encoder.encode(state)
        #expect(!state.isExpanded("projects", sourceID: sourceID, folders: folders))

        let changed = state.revealAncestorsForExternalNavigation(
            of: "projects-2026",
            sourceID: sourceID,
            folders: folders,
            isMacOS: false
        )
        #expect(!changed)
        #expect(state == stateBefore)
        #expect(!state.isExpanded("projects", sourceID: sourceID, folders: folders))
        #expect(try encoder.encode(state) == persistedBefore)
    }
}
