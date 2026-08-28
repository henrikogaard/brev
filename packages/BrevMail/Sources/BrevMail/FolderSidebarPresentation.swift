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
import Foundation

struct FolderSidebarStatus: Equatable, Sendable {
    let title: String
    let icon: String
    let subtitle: String
    let actionTitle: String?
}

struct FolderSidebarMailboxHeaderPresentation: Equatable, Sendable {
    let isDisabled: Bool
    let statusMessage: String?
}

enum FolderSidebarPlatform: Equatable, Sendable {
    case iPhone
    case iPad
    case macOS
}

enum FolderSidebarProfilePickerPresentation: Equatable, Sendable {
    case dialog
    case menu
}

enum FolderSidebarSourceExpansionPolicy {
    static func initialExpandedSourceIDs(
        sourceIDs: [MailSourceID],
        selectedSourceID: MailSourceID?
    ) -> Set<MailSourceID> {
        if let selectedSourceID, sourceIDs.contains(selectedSourceID) {
            return [selectedSourceID]
        }
        guard let firstSourceID = sourceIDs.first else { return [] }
        return [firstSourceID]
    }

    static func expandingSelection(
        _ selectedSourceID: MailSourceID,
        in expandedSourceIDs: Set<MailSourceID>
    ) -> Set<MailSourceID> {
        expandedSourceIDs.union([selectedSourceID])
    }

    static func toggling(
        _ sourceID: MailSourceID,
        in expandedSourceIDs: Set<MailSourceID>
    ) -> Set<MailSourceID> {
        var updated = expandedSourceIDs
        if updated.contains(sourceID) {
            updated.remove(sourceID)
        } else {
            updated.insert(sourceID)
        }
        return updated
    }
}

enum FolderSidebarSmartViewPresentation {
    /// Whether the Smart Views section is open.
    ///
    /// Selecting a smart view reveals the section, but only as a default: it was
    /// an `||`, which meant a selected smart view pinned the section open and the
    /// disclosure control did nothing. `userExpanded` is `nil` until the user
    /// touches that control, and their choice wins from then on — collapsing a
    /// section that contains the selection is ordinary behaviour everywhere else
    /// on the platform.
    static func isExpanded(
        userExpanded: Bool?,
        hasSelectedSmartView: Bool
    ) -> Bool {
        if let userExpanded { return userExpanded }
        return hasSelectedSmartView
    }

    /// The `userExpanded` value that flips whatever is currently on screen.
    static func toggled(
        userExpanded: Bool?,
        hasSelectedSmartView: Bool
    ) -> Bool {
        !isExpanded(
            userExpanded: userExpanded,
            hasSelectedSmartView: hasSelectedSmartView
        )
    }
}

enum FolderSidebarSelectionPresentation {
    static let cornerRadius = BrevRadius.md
    static let globalActionOpacity = 0.18
    static let folderOpacity = 0.26
}

struct FolderSidebarLayoutMetrics: Equatable, Sendable {
    let sidebarPadding: CGFloat
    let sectionSpacing: CGFloat
    let dividerVerticalPadding: CGFloat
    let profilePickerMinimumHeight: CGFloat
    let sourceHeaderMinimumHeight: CGFloat
    let folderRowMinimumHeight: CGFloat
    let disclosureHitSize: CGFloat
    let iconWidth: CGFloat
    let unreadBadgeMinimumWidth: CGFloat
    let unreadBadgeMinimumHeight: CGFloat
    let sourceHeaderHorizontalPadding: CGFloat
    let sourceHeaderVerticalPadding: CGFloat
    let folderRowBaseLeadingPadding: CGFloat
    let folderRowDepthIndent: CGFloat
    let folderRowTrailingPadding: CGFloat
    let folderRowVerticalPadding: CGFloat

    func folderRowLeadingPadding(depth: Int) -> CGFloat {
        folderRowBaseLeadingPadding + CGFloat(depth) * folderRowDepthIndent
    }
}

public struct FolderSidebarVisibilityPreferences: Equatable, Sendable {
    public let showStarred: Bool
    public let showSnoozed: Bool
    public let showScheduled: Bool
    public let showAllMail: Bool
    public let showSpam: Bool
    public let showTrash: Bool
    public let showArchive: Bool

    public static let defaults = FolderSidebarVisibilityPreferences(
        showStarred: true,
        showSnoozed: true,
        showScheduled: true,
        showAllMail: false,
        showSpam: true,
        showTrash: true,
        showArchive: true
    )

    public init(
        showStarred: Bool,
        showSnoozed: Bool,
        showScheduled: Bool,
        showAllMail: Bool,
        showSpam: Bool,
        showTrash: Bool,
        showArchive: Bool
    ) {
        self.showStarred = showStarred
        self.showSnoozed = showSnoozed
        self.showScheduled = showScheduled
        self.showAllMail = showAllMail
        self.showSpam = showSpam
        self.showTrash = showTrash
        self.showArchive = showArchive
    }

    public func isVisible(_ role: FolderRole) -> Bool {
        switch role {
        case .starred: return showStarred
        case .snoozed: return showSnoozed
        case .scheduled: return showScheduled
        case .allMail: return showAllMail
        case .spam: return showSpam
        case .trash: return showTrash
        case .archive: return showArchive
        default: return true
        }
    }
}

struct FolderSidebarRow: Equatable, Identifiable, Sendable {
    let folder: Folder
    let depth: Int
    let hasChildren: Bool

    var id: Folder.ID { folder.id }
}

struct FolderSidebarContextMenuPresentation: Equatable, Sendable {
    let canCreateSubfolder: Bool
    let canMarkAllAsRead: Bool
    let canSetLocalName: Bool
    let canClearLocalName: Bool
    let canRenameFolder: Bool
    let canDeleteFolder: Bool
    let canFlushFolder: Bool
    let canHideFolder: Bool
    let flushActionTitle: String
}

enum FolderSidebarContextMenuAction: Hashable, Sendable {
    case openInNewWindow
    case newSubfolder
    case collapseAll
    case expandAll
    case markAllAsRead
    case setLocalName
    case clearLocalName
    case hideFromMailboxList
    case renameFolder
    case deleteFolder
    case flushFolder
    case refresh
    case showInProfile
    case accountSettings
    case properties
    case downloadOffline
}

enum FolderSidebarContextMenuRole: Equatable, Sendable {
    case destructive
}

struct FolderSidebarContextMenuActionPresentation: Equatable, Sendable {
    let action: FolderSidebarContextMenuAction
    let title: String
    let symbolName: String
    let isEnabled: Bool
    let role: FolderSidebarContextMenuRole?

    init(
        action: FolderSidebarContextMenuAction,
        title: String,
        symbolName: String,
        isEnabled: Bool = true,
        role: FolderSidebarContextMenuRole? = nil
    ) {
        self.action = action
        self.title = title
        self.symbolName = symbolName
        self.isEnabled = isEnabled
        self.role = role
    }
}

struct FolderSidebarContextMenuSection: Equatable, Sendable {
    let actions: [FolderSidebarContextMenuActionPresentation]
}

struct FolderSidebarDesktopContextMenuPresentation: Equatable, Sendable {
    let sections: [FolderSidebarContextMenuSection]

    func action(_ action: FolderSidebarContextMenuAction) -> FolderSidebarContextMenuActionPresentation? {
        for section in sections {
            if let match = section.actions.first(where: { $0.action == action }) {
                return match
            }
        }
        return nil
    }
}

/// Carries a folder-load failure message together with a flag that
/// tells the UI whether the underlying error was a network failure.
/// This lets the sidebar show gentler copy when the device is offline.
public struct FolderLoadError: Equatable, Sendable {
    public let message: String
    public let isNetworkError: Bool

    public init(message: String, isNetworkError: Bool) {
        self.message = message
        self.isNetworkError = isNetworkError
    }
}

enum FolderSidebarPresentation {
    /// Whether a source exposes the provider-backed label/thread model used by
    /// the native sidebar presentation. The combination deliberately stays
    /// provider-neutral so generic IMAP sources keep their existing chrome.
    static func isProviderNativeLabelSource(capabilities: BackendCapabilities) -> Bool {
        capabilities.contains([.providerAPI, .labels, .serverSideThreading])
    }

    /// Returns per-source visibility without mutating the persisted generic
    /// preference. Provider-native label sources always expose All Mail.
    static func effectiveVisibility(
        capabilities: BackendCapabilities,
        persisted: FolderSidebarVisibilityPreferences
    ) -> FolderSidebarVisibilityPreferences {
        guard isProviderNativeLabelSource(capabilities: capabilities) else {
            return persisted
        }
        return FolderSidebarVisibilityPreferences(
            showStarred: persisted.showStarred,
            showSnoozed: persisted.showSnoozed,
            showScheduled: persisted.showScheduled,
            showAllMail: true,
            showSpam: persisted.showSpam,
            showTrash: persisted.showTrash,
            showArchive: persisted.showArchive
        )
    }

    static func shouldShowProfilePicker(profiles: [MailProfile]) -> Bool {
        profiles.contains { !$0.isSystem }
    }

    static func layoutMetrics(
        for platform: FolderSidebarPlatform,
        density: MailboxListDensity = .comfortable
    ) -> FolderSidebarLayoutMetrics {
        let base: FolderSidebarLayoutMetrics
        switch platform {
        case .iPhone, .iPad:
            base = touchLayoutMetrics
        case .macOS:
            base = macOSLayoutMetrics
        }
        return densityAdjustedLayoutMetrics(base, platform: platform, density: density)
    }

    private static func densityAdjustedLayoutMetrics(
        _ base: FolderSidebarLayoutMetrics,
        platform: FolderSidebarPlatform,
        density: MailboxListDensity
    ) -> FolderSidebarLayoutMetrics {
        let folderRowMinimumHeight: CGFloat
        let sourceHeaderMinimumHeight: CGFloat
        let profilePickerMinimumHeight: CGFloat
        let folderRowVerticalPadding: CGFloat
        switch platform {
        case .iPhone, .iPad:
            // Density may tighten the visible padding, but a touch surface never
            // shrinks below the platform's 44-point interaction floor.
            folderRowMinimumHeight = 44
            sourceHeaderMinimumHeight = max(base.sourceHeaderMinimumHeight, folderRowMinimumHeight)
            profilePickerMinimumHeight = max(44, folderRowMinimumHeight)
            folderRowVerticalPadding = switch density {
            case .compact: density.sidebarRowVerticalPadding
            case .comfortable: BrevSpacing.xs
            case .spacious: density.sidebarRowVerticalPadding
            }
        case .macOS:
            folderRowMinimumHeight = switch density {
            case .compact: 24
            case .comfortable: 28
            case .spacious: 34
            }
            sourceHeaderMinimumHeight = switch density {
            case .compact: 22
            case .comfortable: 26
            case .spacious: 32
            }
            profilePickerMinimumHeight = switch density {
            case .compact: 28
            case .comfortable: 32
            case .spacious: 38
            }
            folderRowVerticalPadding = density.sidebarRowVerticalPadding
        }

        return FolderSidebarLayoutMetrics(
            sidebarPadding: base.sidebarPadding,
            sectionSpacing: base.sectionSpacing,
            dividerVerticalPadding: base.dividerVerticalPadding,
            profilePickerMinimumHeight: profilePickerMinimumHeight,
            sourceHeaderMinimumHeight: sourceHeaderMinimumHeight,
            folderRowMinimumHeight: folderRowMinimumHeight,
            disclosureHitSize: base.disclosureHitSize,
            iconWidth: base.iconWidth,
            unreadBadgeMinimumWidth: base.unreadBadgeMinimumWidth,
            unreadBadgeMinimumHeight: base.unreadBadgeMinimumHeight,
            sourceHeaderHorizontalPadding: base.sourceHeaderHorizontalPadding,
            sourceHeaderVerticalPadding: max(
                base.sourceHeaderVerticalPadding,
                density.chromeVerticalPadding / 2
            ),
            folderRowBaseLeadingPadding: base.folderRowBaseLeadingPadding,
            folderRowDepthIndent: base.folderRowDepthIndent,
            folderRowTrailingPadding: base.folderRowTrailingPadding,
            folderRowVerticalPadding: folderRowVerticalPadding
        )
    }

    private static let touchLayoutMetrics = FolderSidebarLayoutMetrics(
        sidebarPadding: BrevSpacing.sm,
        sectionSpacing: BrevSpacing.xxs,
        dividerVerticalPadding: BrevSpacing.xs,
        profilePickerMinimumHeight: 44,
        sourceHeaderMinimumHeight: 44,
        folderRowMinimumHeight: 44,
        disclosureHitSize: 44,
        iconWidth: 20,
        unreadBadgeMinimumWidth: 20,
        unreadBadgeMinimumHeight: 18,
        sourceHeaderHorizontalPadding: BrevSpacing.md,
        sourceHeaderVerticalPadding: BrevSpacing.xs,
        folderRowBaseLeadingPadding: BrevSpacing.xs,
        folderRowDepthIndent: BrevSpacing.lg,
        folderRowTrailingPadding: BrevSpacing.sm,
        folderRowVerticalPadding: BrevSpacing.xs
    )

    private static let macOSLayoutMetrics = FolderSidebarLayoutMetrics(
        sidebarPadding: BrevSpacing.sm,
        sectionSpacing: 0,
        dividerVerticalPadding: BrevSpacing.xxs,
        profilePickerMinimumHeight: 28,
        sourceHeaderMinimumHeight: 22,
        folderRowMinimumHeight: 24,
        disclosureHitSize: 16,
        iconWidth: 16,
        unreadBadgeMinimumWidth: 18,
        unreadBadgeMinimumHeight: 16,
        sourceHeaderHorizontalPadding: BrevSpacing.sm,
        sourceHeaderVerticalPadding: BrevSpacing.xxs,
        folderRowBaseLeadingPadding: BrevSpacing.xs,
        folderRowDepthIndent: BrevSpacing.md,
        folderRowTrailingPadding: BrevSpacing.sm,
        folderRowVerticalPadding: BrevSpacing.xxs
    )

    static func profilePickerPresentation(
        for platform: FolderSidebarPlatform
    ) -> FolderSidebarProfilePickerPresentation {
        switch platform {
        case .iPhone, .iPad:
            .dialog
        case .macOS:
            .menu
        }
    }

    static func mailboxHeader(
        isSwitchingMailbox: Bool,
        isBlocked: Bool
    ) -> FolderSidebarMailboxHeaderPresentation {
        FolderSidebarMailboxHeaderPresentation(
            isDisabled: isSwitchingMailbox || isBlocked,
            statusMessage: mailboxHeaderStatusMessage(
                isSwitchingMailbox: isSwitchingMailbox,
                isBlocked: isBlocked
            )
        )
    }

    private static func mailboxHeaderStatusMessage(
        isSwitchingMailbox: Bool,
        isBlocked: Bool
    ) -> String? {
        if isSwitchingMailbox { return String(localized: "Switching mailbox…", bundle: .module) }
        if isBlocked { return String(localized: "Finishing current action…", bundle: .module) }
        return nil
    }

    static func contextMenu(
        folder: Folder,
        capabilities: BackendCapabilities,
        isActionBlocked: Bool,
        hasSourceIdentity: Bool = false,
        hasLocalAlias: Bool = false
    ) -> FolderSidebarContextMenuPresentation {
        let canCreateSubfolder = capabilities.contains(.folderCreate) && !isActionBlocked
        let canMarkAllAsRead = folder.unreadCount > 0 && !isActionBlocked
        let canSetLocalName = hasSourceIdentity && !isActionBlocked
        let canClearLocalName = hasLocalAlias && !isActionBlocked
        let canRenameFolder = folder.role == .custom
            && capabilities.contains(.folderRename)
            && !isActionBlocked
        let canDeleteFolder = folder.role == .custom
            && capabilities.contains(.folderDelete)
            && !isActionBlocked
        let canFlushFolder = (folder.role == .trash || folder.role == .spam)
            && capabilities.contains(.folderFlush)
            && !isActionBlocked
        let canHideFolder = hasSourceIdentity && !isActionBlocked

        return FolderSidebarContextMenuPresentation(
            canCreateSubfolder: canCreateSubfolder,
            canMarkAllAsRead: canMarkAllAsRead,
            canSetLocalName: canSetLocalName,
            canClearLocalName: canClearLocalName,
            canRenameFolder: canRenameFolder,
            canDeleteFolder: canDeleteFolder,
            canFlushFolder: canFlushFolder,
            canHideFolder: canHideFolder,
            flushActionTitle: flushFolderTitle(for: folder)
        )
    }

    static func desktopContextMenu(
        folder: Folder,
        capabilities: BackendCapabilities,
        isActionBlocked: Bool,
        hasSourceIdentity: Bool = false,
        hasLocalAlias: Bool = false,
        hasChildren: Bool = false,
        isExpanded: Bool = true,
        canExpandAll: Bool = false,
        canCollapseAll: Bool = false,
        canOpenInNewWindow: Bool = false,
        canShowInProfile: Bool = false,
        canOpenAccountSettings: Bool = false,
        canShowProperties: Bool = false,
        canDownloadOffline: Bool = false
    ) -> FolderSidebarDesktopContextMenuPresentation {
        let presentation = contextMenu(
            folder: folder,
            capabilities: capabilities,
            isActionBlocked: isActionBlocked,
            hasSourceIdentity: hasSourceIdentity,
            hasLocalAlias: hasLocalAlias
        )
        var sections: [FolderSidebarContextMenuSection] = []
        appendSection(
            &sections,
            actions: canOpenInNewWindow ? [
                .init(
                    action: .openInNewWindow,
                    title: String(localized: "Open in New Window", bundle: .module),
                    symbolName: "arrow.up.forward.square"
                )
            ] : []
        )
        appendSection(
            &sections,
            actions: [
                .init(
                    action: .newSubfolder,
                    title: String(localized: "New Subfolder…", bundle: .module),
                    symbolName: "folder.badge.plus",
                    isEnabled: presentation.canCreateSubfolder
                )
            ]
        )
        let disclosureAction: FolderSidebarContextMenuActionPresentation? = if hasChildren && isExpanded {
            .init(
                action: .collapseAll,
                title: String(localized: "Collapse All", bundle: .module),
                symbolName: "rectangle.compress.vertical",
                isEnabled: canCollapseAll
            )
        } else if hasChildren {
            .init(
                action: .expandAll,
                title: String(localized: "Expand All", bundle: .module),
                symbolName: "rectangle.expand.vertical",
                isEnabled: canExpandAll
            )
        } else {
            nil
        }
        appendSection(&sections, actions: disclosureAction.map { [$0] } ?? [])
        appendSection(
            &sections,
            actions: [
                .init(
                    action: .markAllAsRead,
                    title: String(localized: "Mark All as Read", bundle: .module),
                    symbolName: "envelope.open",
                    isEnabled: presentation.canMarkAllAsRead
                )
            ]
        )
        appendSection(
            &sections,
            actions: [
                .init(
                    action: .setLocalName,
                    title: String(localized: "Set Local Name…", bundle: .module),
                    symbolName: "textformat",
                    isEnabled: presentation.canSetLocalName
                ),
                .init(
                    action: .clearLocalName,
                    title: String(localized: "Clear Local Name", bundle: .module),
                    symbolName: "textformat.alt",
                    isEnabled: presentation.canClearLocalName
                ),
                .init(
                    action: .hideFromMailboxList,
                    title: String(localized: "Hide from Mailbox List", bundle: .module),
                    symbolName: "eye.slash",
                    isEnabled: presentation.canHideFolder
                )
            ]
        )
        var editActions: [FolderSidebarContextMenuActionPresentation] = [
            .init(
                action: .renameFolder,
                title: String(localized: "Rename Folder…", bundle: .module),
                symbolName: "pencil",
                isEnabled: presentation.canRenameFolder
            ),
            .init(
                action: .deleteFolder,
                title: String(localized: "Delete Folder", bundle: .module),
                symbolName: "trash",
                isEnabled: presentation.canDeleteFolder,
                role: .destructive
            )
        ]
        if presentation.canFlushFolder {
            editActions.append(.init(
                action: .flushFolder,
                title: presentation.flushActionTitle,
                symbolName: "trash.slash",
                isEnabled: presentation.canFlushFolder,
                role: .destructive
            ))
        }
        appendSection(&sections, actions: editActions)
        appendSection(
            &sections,
            actions: [
                .init(
                    action: .refresh,
                    title: String(localized: "Refresh", bundle: .module),
                    symbolName: "arrow.clockwise",
                    isEnabled: !isActionBlocked
                )
            ]
        )
        var accountActions: [FolderSidebarContextMenuActionPresentation] = []
        if canShowInProfile {
            accountActions.append(.init(
                action: .showInProfile,
                title: String(localized: "Show in Profile…", bundle: .module),
                symbolName: "rectangle.stack.person.crop"
            ))
        }
        if canOpenAccountSettings {
            accountActions.append(.init(
                action: .accountSettings,
                title: String(localized: "Account Settings…", bundle: .module),
                symbolName: "gearshape"
            ))
        }
        if canShowProperties {
            accountActions.append(.init(
                action: .properties,
                title: String(localized: "Properties…", bundle: .module),
                symbolName: "info.circle"
            ))
        }
        // NOTE: account-level "Download for Offline" is intentionally NOT offered
        // — there is no renderer for it in FolderSidebar (it would be an inert
        // menu item, the honesty problem #262 removed). Re-add here only once a
        // real handler exists. `canDownloadOffline` is retained for the eventual
        // wiring but currently produces no menu entry.
        _ = canDownloadOffline
        appendSection(&sections, actions: accountActions)
        return FolderSidebarDesktopContextMenuPresentation(sections: sections)
    }

    static func displayName(
        for folder: Folder,
        sourceID: MailSourceID?,
        aliasPreferences: FolderAliasPreferences,
        capabilities: BackendCapabilities = []
    ) -> String {
        if isProviderNativeLabelSource(capabilities: capabilities)
            && (folder.role == .starred || isProviderImportantFolder(folder)) {
            return folder.name
        }
        return FolderAliasPreferencesPolicy.displayName(
            for: folder,
            sourceID: sourceID,
            preferences: aliasPreferences
        )
    }

    private static func isProviderImportantFolder(_ folder: Folder) -> Bool {
        guard folder.role == .custom else { return false }
        return folder.id.caseInsensitiveCompare("IMPORTANT") == .orderedSame
            || folder.name.caseInsensitiveCompare("Important") == .orderedSame
    }

    private static func flushFolderTitle(for folder: Folder) -> String {
        switch folder.role {
        case .trash: return String(localized: "Empty Trash", bundle: .module)
        case .spam: return String(localized: "Delete Junk Mail", bundle: .module)
        default: return String(localized: "Empty Folder", bundle: .module)
        }
    }

    private static func appendSection(
        _ sections: inout [FolderSidebarContextMenuSection],
        actions: [FolderSidebarContextMenuActionPresentation]
    ) {
        guard !actions.isEmpty else { return }
        sections.append(FolderSidebarContextMenuSection(actions: actions))
    }

    static func status(
        folders: [Folder],
        loadError: FolderLoadError?,
        isOffline: Bool = false
    ) -> FolderSidebarStatus? {
        if let loadError {
            let trimmedError = loadErrorMessage(loadError.message)
            if folders.isEmpty {
                return FolderSidebarStatus(
                    title: String(localized: "Couldn't load folders", bundle: .module),
                    icon: "exclamationmark.triangle",
                    subtitle: trimmedError,
                    actionTitle: String(localized: "Try Again", bundle: .module)
                )
            }
            if loadError.isNetworkError && isOffline {
                return FolderSidebarStatus(
                    title: String(localized: "Offline", bundle: .module),
                    icon: "wifi.slash",
                    subtitle: String(localized: "Showing cached folders", bundle: .module),
                    actionTitle: String(localized: "Retry", bundle: .module)
                )
            }
            return FolderSidebarStatus(
                title: String(localized: "Folders may be stale", bundle: .module),
                icon: "wifi.slash",
                subtitle: String(localized: "Showing cached folders while Brev retries: \(trimmedError)", bundle: .module),
                actionTitle: String(localized: "Retry", bundle: .module)
            )
        }
        if folders.isEmpty {
            return FolderSidebarStatus(
                title: String(localized: "Setting up your Inbox", bundle: .module),
                icon: "arrow.triangle.2.circlepath",
                subtitle: String(
                    localized: "Brev is checking this account for folders. Your mail will appear here when the first sync finishes.",
                    bundle: .module
                ),
                actionTitle: String(localized: "Check Again", bundle: .module)
            )
        }
        return nil
    }

    static func visibleRows(
        folders: [Folder],
        visibility: FolderSidebarVisibilityPreferences = .defaults,
        collapsedFolderIDs: Set<Folder.ID> = []
    ) -> [FolderSidebarRow] {
        let visibleFolders = visibleFolders(
            folders,
            visibility: visibility
        )

        var foldersByID: [Folder.ID: Folder] = [:]
        for folder in visibleFolders where foldersByID[folder.id] == nil {
            foldersByID[folder.id] = folder
        }

        var childrenByParentID: [Folder.ID: [Folder]] = [:]
        for folder in visibleFolders {
            guard let parentID = folder.parentID,
                  foldersByID[parentID] != nil
            else {
                continue
            }
            childrenByParentID[parentID, default: []].append(folder)
        }

        var rows: [FolderSidebarRow] = []
        var processedFolderIDs: Set<Folder.ID> = []

        func markDescendantsProcessed(
            of folder: Folder,
            ancestors: Set<Folder.ID>
        ) {
            var nextAncestors = ancestors
            nextAncestors.insert(folder.id)
            for child in childrenByParentID[folder.id] ?? [] {
                guard !processedFolderIDs.contains(child.id),
                      !nextAncestors.contains(child.id)
                else {
                    continue
                }
                processedFolderIDs.insert(child.id)
                markDescendantsProcessed(of: child, ancestors: nextAncestors)
            }
        }

        func appendRows(
            from folder: Folder,
            depth: Int,
            ancestors: Set<Folder.ID>
        ) {
            guard !processedFolderIDs.contains(folder.id),
                  !ancestors.contains(folder.id)
            else {
                return
            }

            let children = childrenByParentID[folder.id] ?? []
            rows.append(FolderSidebarRow(
                folder: folder,
                depth: depth,
                hasChildren: !children.isEmpty
            ))
            processedFolderIDs.insert(folder.id)

            guard !collapsedFolderIDs.contains(folder.id) else {
                markDescendantsProcessed(of: folder, ancestors: ancestors)
                return
            }

            var nextAncestors = ancestors
            nextAncestors.insert(folder.id)
            for child in children {
                appendRows(from: child, depth: depth + 1, ancestors: nextAncestors)
            }
        }

        let roots = visibleFolders.filter { folder in
            guard let parentID = folder.parentID else { return true }
            return foldersByID[parentID] == nil
        }

        for root in roots {
            appendRows(from: root, depth: 0, ancestors: [])
        }

        for folder in visibleFolders where !processedFolderIDs.contains(folder.id) {
            appendRows(from: folder, depth: 0, ancestors: [])
        }

        return rows
    }

    static func visibleFolders(
        _ folders: [Folder],
        visibility: FolderSidebarVisibilityPreferences
    ) -> [Folder] {
        var hiddenFolderIDs: Set<Folder.ID> = []
        for folder in folders where !visibility.isVisible(folder.role) {
            hiddenFolderIDs.insert(folder.id)
        }

        var didHide = true
        while didHide {
            didHide = false
            for folder in folders where !hiddenFolderIDs.contains(folder.id) {
                guard let parentID = folder.parentID,
                      hiddenFolderIDs.contains(parentID)
                else {
                    continue
                }
                hiddenFolderIDs.insert(folder.id)
                didHide = true
            }
        }

        return folders.filter { !hiddenFolderIDs.contains($0.id) }
    }

    static func loadErrorInfo(for error: any Error) -> FolderLoadError {
        let isNetwork = error is MailBackendError
            && (error as? MailBackendError)?.isNetwork == true
        let message = loadErrorMessage(error.localizedDescription)
        return FolderLoadError(message: message, isNetworkError: isNetwork)
    }

    static func loadErrorMessage(for error: any Error) -> String {
        loadErrorMessage(error.localizedDescription)
    }

    private static func loadErrorMessage(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Couldn't load folders.", bundle: .module) : trimmed
    }
}
