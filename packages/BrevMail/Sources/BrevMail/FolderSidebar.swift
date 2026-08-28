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
import BrevPlugins
import BrevSettings
import BrevThemes
import SwiftUI

/// Runs a sidebar selection and reports the user activation separately so
/// reselecting an unchanged destination can still drive compact navigation.
enum FolderSidebarDestinationActivation {
    /// Applies `selection`, then notifies the parent that a destination was
    /// activated even when the selected identifier did not change.
    static func activate(
        selection: () -> Void,
        onActivated: (() -> Void)?
    ) {
        selection()
        onActivated?()
    }
}

/// Folder sidebar — drives folder selection in `MailNavigationState`.
///
/// Renders each `Folder` as a compact themed sidebar row with role
/// icon and unread count. Selection writes back to the shared
/// navigation state; the parent observes that to update the list pane.
public struct FolderSidebar: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.networkMonitor) private var monitor
    @AppStorage("folder.disclosureState") private var disclosureStateData = Data()
    @AppStorage(MailboxViewPreferenceKey.listDensity) private var listDensityRaw = MailboxListDensity.comfortable.rawValue
    /// In-memory copy of the disclosure state used for rendering. Decoding the
    /// stored JSON on every render (once per source section) made expand/collapse
    /// feel sluggish; the cache is seeded on appear and updated in place on toggle,
    /// so a disclosure change is an immediate, local state mutation.
    @State private var disclosureState = FolderDisclosureState()
    @State private var expandedSourceIDs: Set<MailSourceID> = []

    private func loadDisclosureState() -> FolderDisclosureState {
        (try? JSONDecoder().decode(FolderDisclosureState.self, from: disclosureStateData)) ?? FolderDisclosureState()
    }

    private func saveDisclosureState(_ state: FolderDisclosureState) {
        disclosureStateData = (try? JSONEncoder().encode(state)) ?? Data()
    }

    @State private var isProfilePickerDialogPresented = false
    @State private var selectedPluginContribution: RegisteredContribution?
    /// Progressive disclosure for built-in and custom Smart Views.
    /// `nil` until the user works the disclosure control; their choice wins from
    /// then on. See `FolderSidebarSmartViewPresentation`.
    @State private var smartViewsUserExpanded: Bool?
    /// Mirrors the persisted saved-search store purely to trigger a re-render
    /// when the editor saves; actual data is read via `SmartMailboxSettings.load()`.
    @AppStorage(SmartMailboxSettings.storageKey) private var smartMailboxData = Data()
    @State private var savedSearchEditorTarget: SavedSearchEditorTarget?
    @Bindable private var navigation: MailNavigationState
    private let folders: [Folder]
    private let loadError: FolderLoadError?
    private let sourceSections: [MailSourceSection]
    private let profiles: [MailProfile]
    private let activeProfileID: MailProfile.ID
    private let mailboxes: [Mailbox]
    private let activeMailboxID: String?
    private let isSwitchingMailbox: Bool
    private let isMailboxSwitchBlocked: Bool
    private let capabilitiesForSource: (MailSourceID?) -> BackendCapabilities
    private let isFolderActionBlocked: Bool
    private let folderVisibility: FolderSidebarVisibilityPreferences
    private let folderAliasPreferences: FolderAliasPreferences
    private let onSelectProfile: ((MailProfile.ID) -> Void)?
    private let onManageProfiles: (() -> Void)?
    private let onSwitchMailbox: ((String) -> Void)?
    private let onDropMessages: (([String], Folder) -> Void)?
    private let onDropSourceMessages: (([String], MailSourceID, Folder) -> Void)?
    private let onCreateSubfolder: ((Folder, MailSourceID?) -> Void)?
    private let onMarkFolderAsRead: ((Folder, MailSourceID?) -> Void)?
    private let onSetFolderLocalName: ((Folder, MailSourceID) -> Void)?
    private let onClearFolderLocalName: ((Folder, MailSourceID) -> Void)?
    private let onRenameFolder: ((Folder, MailSourceID?) -> Void)?
    private let onDeleteFolder: ((Folder, MailSourceID?) -> Void)?
    private let onFlushFolder: ((Folder, MailSourceID?) -> Void)?
    private let onHideFolder: ((Folder, MailSourceID) -> Void)?
    private let onRefreshFolder: ((Folder, MailSourceID?) -> Void)?
    private let onRetryLoad: (() -> Void)?
    private let outboxPendingCount: Int
    private let onOpenOutbox: (() -> Void)?
    private let onOpenSettings: (() -> Void)?
    private let onOpenMessages: (() -> Void)?

    public init(
        navigation: MailNavigationState,
        folders: [Folder],
        loadError: FolderLoadError? = nil,
        sourceSections: [MailSourceSection] = [],
        profiles: [MailProfile] = [],
        activeProfileID: MailProfile.ID = MailProfile.allMailboxesID,
        mailboxes: [Mailbox] = [],
        activeMailboxID: String? = nil,
        isSwitchingMailbox: Bool = false,
        isMailboxSwitchBlocked: Bool = false,
        capabilitiesForSource: @escaping (MailSourceID?) -> BackendCapabilities = { _ in [] },
        isFolderActionBlocked: Bool = false,
        folderAliasPreferences: FolderAliasPreferences = .defaults,
        onSelectProfile: ((MailProfile.ID) -> Void)? = nil,
        onManageProfiles: (() -> Void)? = nil,
        onSwitchMailbox: ((String) -> Void)? = nil,
        onDropMessages: (([String], Folder) -> Void)? = nil,
        onDropSourceMessages: (([String], MailSourceID, Folder) -> Void)? = nil,
        onCreateSubfolder: ((Folder, MailSourceID?) -> Void)? = nil,
        onMarkFolderAsRead: ((Folder, MailSourceID?) -> Void)? = nil,
        onSetFolderLocalName: ((Folder, MailSourceID) -> Void)? = nil,
        onClearFolderLocalName: ((Folder, MailSourceID) -> Void)? = nil,
        onRenameFolder: ((Folder, MailSourceID?) -> Void)? = nil,
        onDeleteFolder: ((Folder, MailSourceID?) -> Void)? = nil,
        onFlushFolder: ((Folder, MailSourceID?) -> Void)? = nil,
        onHideFolder: ((Folder, MailSourceID) -> Void)? = nil,
        onRefreshFolder: ((Folder, MailSourceID?) -> Void)? = nil,
        onRetryLoad: (() -> Void)? = nil,
        folderVisibility: FolderSidebarVisibilityPreferences = .defaults,
        outboxPendingCount: Int = 0,
        onOpenOutbox: (() -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil,
        onOpenMessages: (() -> Void)? = nil
    ) {
        self.navigation = navigation
        self.folders = folders
        self.loadError = loadError
        self.sourceSections = sourceSections
        self.profiles = profiles
        self.activeProfileID = activeProfileID
        self.mailboxes = mailboxes
        self.activeMailboxID = activeMailboxID
        self.isSwitchingMailbox = isSwitchingMailbox
        self.isMailboxSwitchBlocked = isMailboxSwitchBlocked
        self.capabilitiesForSource = capabilitiesForSource
        self.isFolderActionBlocked = isFolderActionBlocked
        self.folderAliasPreferences = folderAliasPreferences
        self.onSelectProfile = onSelectProfile
        self.onManageProfiles = onManageProfiles
        self.onSwitchMailbox = onSwitchMailbox
        self.onDropMessages = onDropMessages
        self.onDropSourceMessages = onDropSourceMessages
        self.onCreateSubfolder = onCreateSubfolder
        self.onMarkFolderAsRead = onMarkFolderAsRead
        self.onSetFolderLocalName = onSetFolderLocalName
        self.onClearFolderLocalName = onClearFolderLocalName
        self.onRenameFolder = onRenameFolder
        self.onDeleteFolder = onDeleteFolder
        self.onFlushFolder = onFlushFolder
        self.onHideFolder = onHideFolder
        self.onRefreshFolder = onRefreshFolder
        self.onRetryLoad = onRetryLoad
        self.folderVisibility = folderVisibility
        self.outboxPendingCount = outboxPendingCount
        self.onOpenOutbox = onOpenOutbox
        self.onOpenSettings = onOpenSettings
        self.onOpenMessages = onOpenMessages
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: sidebarMetrics.sectionSpacing) {
                if !sourceSections.isEmpty {
                    sourceTree
                } else if mailboxes.count > 1 {
                    mailboxHeader
                        .padding(.bottom, BrevSpacing.xs)
                    outboxButton
                    folderList(folders: folders, sourceID: nil, loadError: loadError)
                } else {
                    outboxButton
                    folderList(folders: folders, sourceID: nil, loadError: loadError)
                }
            }
            .padding(sidebarMetrics.sidebarPadding)
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        #if os(iOS)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                sidebarFooter
            }
        #endif
            .onAppear {
                disclosureState = loadDisclosureState()
                seedSourceExpansionIfNeeded()
            }
            .onChange(of: disclosureStateData) { disclosureState = loadDisclosureState() }
            .onChange(of: navigation.selectedSourceID) { _, selectedSourceID in
                guard let selectedSourceID else { return }
                expandedSourceIDs = FolderSidebarSourceExpansionPolicy.expandingSelection(
                    selectedSourceID,
                    in: expandedSourceIDs
                )
            }
            .sheet(item: $savedSearchEditorTarget) { target in
                switch target {
                case .create:
                    SavedSearchEditorView(onFinished: finishSavedSearchEditor)
                case .edit(let mailbox):
                    SavedSearchEditorView(editing: mailbox, onFinished: finishSavedSearchEditor)
                }
            }
    }

    /// Drives the saved-search editor sheet; identity-stable so the sheet
    /// presentation survives re-renders.
    private enum SavedSearchEditorTarget: Identifiable {
        case create
        case edit(SmartMailbox)

        var id: String {
            switch self {
            case .create: "create"
            case .edit(let mailbox): mailbox.id
            }
        }
    }

    /// iOS only. macOS reaches Settings from the app menu; iPhone has no menu
    /// bar, and the navigation bar's gear is easy to miss, so the sidebar keeps
    /// a persistent entry at its foot — where Spark keeps it.
    #if os(iOS)
    @ViewBuilder
    private var sidebarFooter: some View {
        if let onOpenSettings {
            Button(action: onOpenSettings) {
                Label(String(localized: "Settings", bundle: .module), systemImage: "gearshape")
                    .brevFont(.footnote)
                    .padding(.horizontal, BrevSpacing.md)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .background(Capsule().fill(theme.bgSecondary.color))
                    .foregroundStyle(theme.textPrimary.color)
            }
            .buttonStyle(.plain)
            .folderSidebarTouchTarget(minHeight: sidebarMetrics.folderRowMinimumHeight)
            .padding(.horizontal, BrevSpacing.md)
            .padding(.vertical, BrevSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The footer sits above a scrolling tree. Keep it opaque so account
            // and folder labels do not show through behind the Settings action.
            .background(theme.bgPrimary.color)
            .accessibilityLabel(String(localized: "Settings", bundle: .module))
        }
    }
    #endif

    @ViewBuilder
    private var sourceTree: some View {
        if showsProfilePicker {
            profilePicker
                .padding(.bottom, BrevSpacing.xs)
        }
        VStack(alignment: .leading, spacing: 0) {
            if showsUnifiedInbox {
                unifiedInboxButton
            }
            if showsSmartViews {
                smartViewsSection
            }
            outboxButton
        }
        .padding(.bottom, BrevSpacing.sm)

        ForEach(sourceSections) { section in
            let isExpanded = expandedSourceIDs.contains(section.id)
            VStack(alignment: .leading, spacing: sidebarMetrics.sectionSpacing) {
                sourceHeader(section, isExpanded: isExpanded)
                if isExpanded {
                    folderList(
                        folders: section.folders,
                        sourceID: section.id,
                        loadError: section.loadError
                    )
                }
            }
            .padding(
                .bottom,
                section.id == sourceSections.last?.id ? 0 : BrevSpacing.xs
            )
        }
        // Plugin-contributed sidebar panels live at the bottom, after the user's
        // own mailboxes and folders, so third-party extensions never sit above
        // real accounts.
        pluginSidebarItems
    }

    private var showsUnifiedInbox: Bool {
        sourceSections.filter { section in
            section.folders.contains { $0.role == .inbox }
        }.count > 1
    }

    private var showsProfilePicker: Bool {
        FolderSidebarPresentation.shouldShowProfilePicker(profiles: profiles)
    }

    private var showsSmartViews: Bool {
        !sourceSections.isEmpty
    }

    @ViewBuilder
    private var profilePicker: some View {
        switch profilePickerPresentation {
        case .dialog:
            Button {
                isProfilePickerDialogPresented = true
            } label: {
                profilePickerLabel
            }
            .buttonStyle(.plain)
            .confirmationDialog(
                String(localized: "Profile", bundle: .module),
                isPresented: $isProfilePickerDialogPresented,
                titleVisibility: .visible
            ) {
                profilePickerActions
            } message: {
                Text(verbatim: activeProfileName)
            }
        case .menu:
            Menu {
                profilePickerActions
            } label: {
                profilePickerLabel
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
    }

    @ViewBuilder
    private var profilePickerActions: some View {
        ForEach(profiles) { profile in
            Button {
                onSelectProfile?(profile.id)
            } label: {
                if profile.id == normalizedActiveProfileID {
                    Label {
                        Text(verbatim: profile.name)
                    } icon: {
                        Image(systemName: "checkmark")
                    }
                } else {
                    Text(verbatim: profile.name)
                }
            }
        }
        Divider()
        Button {
            onManageProfiles?()
        } label: {
            Label(String(localized: "Manage Profiles", bundle: .module), systemImage: "person.crop.rectangle.stack")
        }
    }

    private var profilePickerLabel: some View {
        HStack(spacing: BrevSpacing.sm) {
            Image(systemName: "person.crop.rectangle.stack")
                .foregroundStyle(theme.accent.color)
                .frame(width: sidebarMetrics.iconWidth, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: activeProfileName)
                    .brevFont(.footnote)
                    .foregroundStyle(theme.textPrimary.color)
                    .lineLimit(1)
                Text("Profile", bundle: .module)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textTertiary.color)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.textTertiary.color)
        }
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.sm)
        .frame(
            maxWidth: .infinity,
            minHeight: sidebarMetrics.profilePickerMinimumHeight,
            alignment: .leading
        )
        .background {
            RoundedRectangle(cornerRadius: BrevRadius.md)
                .fill(theme.bgSecondary.color.opacity(0.42))
        }
        .overlay {
            RoundedRectangle(cornerRadius: BrevRadius.md)
                .stroke(theme.border.color.opacity(0.45), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: BrevRadius.md))
        .contentShape(RoundedRectangle(cornerRadius: BrevRadius.md))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Profile", bundle: .module))
        .accessibilityValue(activeProfileName)
    }

    private var profilePickerPresentation: FolderSidebarProfilePickerPresentation {
        #if os(iOS)
        FolderSidebarPresentation.profilePickerPresentation(for: .iPhone)
        #else
        FolderSidebarPresentation.profilePickerPresentation(for: .macOS)
        #endif
    }

    private var normalizedActiveProfileID: MailProfile.ID {
        MailProfileSelectionPolicy.selectedProfileID(activeProfileID, profiles: profiles)
    }

    private var activeProfileName: String {
        profiles.first { $0.id == normalizedActiveProfileID }?.name
            ?? String(localized: "All Mailboxes", bundle: .module)
    }

    @ViewBuilder
    private var unifiedInboxButton: some View {
        Button {
            activateDestination { navigation.selectUnifiedInbox() }
        } label: {
            #if os(iOS)
            BrevListRow(
                title: String(localized: "All Inboxes", bundle: .module),
                isSelected: navigation.isUnifiedInboxSelected,
                leading: {
                    Image(systemName: "tray.full")
                        .foregroundStyle(theme.textSecondary.color)
                        .frame(width: sidebarMetrics.iconWidth, alignment: .center)
                },
                trailing: {
                    unreadBadge(unifiedUnreadCount)
                }
            )
            #else
            sidebarActionRow(
                title: String(localized: "All Inboxes", bundle: .module),
                isSelected: navigation.isUnifiedInboxSelected,
                alignment: .sourceHeader,
                leading: {
                    Image(systemName: "tray.full")
                        .foregroundStyle(theme.textSecondary.color)
                        .imageScale(.small)
                        .frame(width: sidebarMetrics.iconWidth, alignment: .center)
                },
                trailing: {
                    unreadBadge(unifiedUnreadCount)
                }
            )
            #endif
        }
        .buttonStyle(.plain)
        .folderSidebarTouchTarget(minHeight: sidebarMetrics.folderRowMinimumHeight)
    }

    private var unifiedUnreadCount: Int {
        sourceSections.reduce(into: 0) { count, section in
            count += section.folders.first { $0.role == .inbox }?.unreadCount ?? 0
        }
    }

    @ViewBuilder
    private var outboxButton: some View {
        if outboxPendingCount > 0 {
            Button {
                onOpenOutbox?()
            } label: {
                #if os(iOS)
                BrevListRow(
                    title: String(localized: "Outbox", bundle: .module),
                    isSelected: false,
                    leading: {
                        Image(systemName: "arrow.up.circle")
                            .foregroundStyle(theme.warning.color)
                            .frame(width: sidebarMetrics.iconWidth, alignment: .center)
                    },
                    trailing: {
                        unreadBadge(outboxPendingCount)
                    }
                )
                #else
                sidebarActionRow(
                    title: String(localized: "Outbox", bundle: .module),
                    isSelected: false,
                    leading: {
                        Image(systemName: "arrow.up.circle")
                            .foregroundStyle(theme.warning.color)
                            .imageScale(.small)
                            .frame(width: sidebarMetrics.iconWidth, alignment: .center)
                    },
                    trailing: {
                        unreadBadge(outboxPendingCount)
                    }
                )
                #endif
            }
            .buttonStyle(.plain)
            .folderSidebarTouchTarget(minHeight: sidebarMetrics.folderRowMinimumHeight)
        }
    }

    @ViewBuilder
    private var smartViewsSection: some View {
        let settings = smartViewSettings
        let isExpanded = FolderSidebarSmartViewPresentation.isExpanded(
            userExpanded: smartViewsUserExpanded,
            hasSelectedSmartView: hasSelectedSmartView
        )
        HStack(spacing: BrevSpacing.xs) {
            Button {
                smartViewsUserExpanded = FolderSidebarSmartViewPresentation.toggled(
                    userExpanded: smartViewsUserExpanded,
                    hasSelectedSmartView: hasSelectedSmartView
                )
            } label: {
                Text("Smart Views", bundle: .module)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                    .lineLimit(1)
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textTertiary.color)
            }
            .buttonStyle(.plain)
            .folderSidebarTouchTarget(minHeight: sidebarMetrics.disclosureHitSize)
            .accessibilityLabel(String(localized: "Smart Views", bundle: .module))
            .accessibilityValue(
                isExpanded
                    ? String(localized: "Expanded", bundle: .module)
                    : String(localized: "Collapsed", bundle: .module)
            )
            .accessibilityHint(
                isExpanded
                    ? String(localized: "Collapse Smart Views", bundle: .module)
                    : String(localized: "Expand Smart Views", bundle: .module)
            )

            Spacer(minLength: BrevSpacing.sm)

            Button {
                savedSearchEditorTarget = .create
            } label: {
                Image(systemName: "plus")
                    .foregroundStyle(theme.textSecondary.color)
                    .imageScale(.small)
                    .folderSidebarSquareTouchTarget(size: sidebarMetrics.disclosureHitSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "New Smart View", bundle: .module))
            .help(String(localized: "New Smart View", bundle: .module))

            smartViewManagementMenu(settings: settings)
        }
        .padding(.horizontal, sidebarMetrics.folderRowTrailingPadding)
        .padding(.vertical, sidebarMetrics.folderRowVerticalPadding)

        if isExpanded {
            smartViewButtons(settings: settings)
            if settings.isBuiltInEnabled(Self.allAttachmentsSmartViewVisibilityID) {
                allAttachmentsButton
            }
            customSmartViewButtons(settings: settings)
        }
    }

    private static let allAttachmentsSmartViewVisibilityID = "all-attachments"

    private var smartViewSettings: SmartMailboxSettings {
        _ = smartMailboxData
        return SmartMailboxSettings.load()
    }

    private var hasSelectedSmartView: Bool {
        MailboxSmartView.builtIns.contains { $0.isSelected(in: navigation) }
            || navigation.isAllAttachmentsSelected
            || navigation.selectedSavedSearchID != nil
    }

    @ViewBuilder
    private func smartViewButtons(settings: SmartMailboxSettings) -> some View {
        ForEach(MailboxSmartView.builtIns.filter { settings.isBuiltInEnabled($0.id) }) { smartView in
            Button {
                activateDestination { smartView.select(in: navigation) }
            } label: {
                #if os(iOS)
                BrevListRow(
                    title: smartView.title,
                    isSelected: smartView.isSelected(in: navigation),
                    leading: {
                        Image(systemName: smartView.symbolName)
                            .foregroundStyle(theme.textSecondary.color)
                            .frame(width: sidebarMetrics.iconWidth, alignment: .center)
                    }
                )
                #else
                sidebarActionRow(
                    title: smartView.title,
                    isSelected: smartView.isSelected(in: navigation),
                    leading: {
                        Image(systemName: smartView.symbolName)
                            .foregroundStyle(theme.textSecondary.color)
                            .imageScale(.small)
                            .frame(width: sidebarMetrics.iconWidth, alignment: .center)
                    },
                    trailing: {
                        EmptyView()
                    }
                )
                #endif
            }
            .buttonStyle(.plain)
            .folderSidebarTouchTarget(minHeight: sidebarMetrics.folderRowMinimumHeight)
        }
    }

    @ViewBuilder
    private func customSmartViewButtons(settings: SmartMailboxSettings) -> some View {
        let rows = SavedSearchSidebarPresentation.rows(from: settings.mailboxes)
        ForEach(rows) { row in
            Button {
                activateDestination { navigation.selectSavedSearch(id: row.id) }
            } label: {
                #if os(iOS)
                BrevListRow(
                    title: row.title,
                    isSelected: navigation.isSavedSearchSelected(id: row.id),
                    leading: {
                        Image(systemName: row.symbolName)
                            .foregroundStyle(theme.textSecondary.color)
                            .frame(width: sidebarMetrics.iconWidth, alignment: .center)
                    }
                )
                #else
                sidebarActionRow(
                    title: row.title,
                    isSelected: navigation.isSavedSearchSelected(id: row.id),
                    leading: {
                        Image(systemName: row.symbolName)
                            .foregroundStyle(theme.textSecondary.color)
                            .imageScale(.small)
                            .frame(width: sidebarMetrics.iconWidth, alignment: .center)
                    },
                    trailing: { EmptyView() }
                )
                #endif
            }
            .buttonStyle(.plain)
            .folderSidebarTouchTarget(minHeight: sidebarMetrics.folderRowMinimumHeight)
            .contextMenu {
                Button {
                    if let mailbox = settings.mailboxes.first(where: { $0.id == row.id }) {
                        savedSearchEditorTarget = .edit(mailbox)
                    }
                } label: {
                    Label(String(localized: "Edit", bundle: .module), systemImage: "pencil")
                }
                Button {
                    toggleCustomSmartView(id: row.id)
                } label: {
                    Label(String(localized: "Hide", bundle: .module), systemImage: "eye.slash")
                }
                Button(role: .destructive) {
                    deleteSavedSearch(id: row.id)
                } label: {
                    Label(String(localized: "Delete", bundle: .module), systemImage: "trash")
                }
            }
        }
    }

    private var allAttachmentsButton: some View {
        Button {
            activateDestination { navigation.selectAllAttachmentsSmartView() }
        } label: {
            #if os(iOS)
            BrevListRow(
                title: String(localized: "All Attachments", bundle: .module),
                isSelected: navigation.isAllAttachmentsSelected,
                leading: {
                    Image(systemName: "paperclip")
                        .foregroundStyle(theme.textSecondary.color)
                        .frame(width: sidebarMetrics.iconWidth, alignment: .center)
                }
            )
            #else
            sidebarActionRow(
                title: String(localized: "All Attachments", bundle: .module),
                isSelected: navigation.isAllAttachmentsSelected,
                leading: {
                    Image(systemName: "paperclip")
                        .foregroundStyle(theme.textSecondary.color)
                        .imageScale(.small)
                        .frame(width: sidebarMetrics.iconWidth, alignment: .center)
                },
                trailing: {
                    EmptyView()
                }
            )
            #endif
        }
        .buttonStyle(.plain)
        .folderSidebarTouchTarget(minHeight: sidebarMetrics.folderRowMinimumHeight)
    }

    private func smartViewManagementMenu(settings: SmartMailboxSettings) -> some View {
        Menu {
            Section(String(localized: "Built-in Smart Views", bundle: .module)) {
                ForEach(MailboxSmartView.builtIns) { smartView in
                    smartViewVisibilityButton(
                        title: smartView.title,
                        isEnabled: settings.isBuiltInEnabled(smartView.id)
                    ) {
                        toggleBuiltInSmartView(smartView)
                    }
                }
                smartViewVisibilityButton(
                    title: String(localized: "All Attachments", bundle: .module),
                    isEnabled: settings.isBuiltInEnabled(Self.allAttachmentsSmartViewVisibilityID)
                ) {
                    toggleAllAttachmentsSmartView()
                }
            }

            if !settings.mailboxes.isEmpty {
                Section(String(localized: "Custom Smart Views", bundle: .module)) {
                    ForEach(settings.mailboxes) { mailbox in
                        smartViewVisibilityButton(
                            title: mailbox.name,
                            isEnabled: mailbox.isEnabled
                        ) {
                            toggleCustomSmartView(id: mailbox.id)
                        }
                    }
                }
            }

            Divider()

            Button {
                savedSearchEditorTarget = .create
            } label: {
                Label(String(localized: "New Smart View", bundle: .module), systemImage: "plus")
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(theme.textSecondary.color)
                .imageScale(.small)
                .folderSidebarSquareTouchTarget(size: sidebarMetrics.disclosureHitSize)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel(String(localized: "Manage Smart Views", bundle: .module))
        .help(String(localized: "Manage Smart Views", bundle: .module))
    }

    private func smartViewVisibilityButton(
        title: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            if isEnabled {
                Label(title, systemImage: "checkmark")
            } else {
                Text(verbatim: title)
            }
        }
    }

    private func toggleBuiltInSmartView(_ smartView: MailboxSmartView) {
        var settings = smartViewSettings
        let willEnable = !settings.isBuiltInEnabled(smartView.id)
        settings.setBuiltIn(smartView.id, isEnabled: willEnable)
        settings.save()
        if !willEnable {
            leaveHiddenSmartViewIfNeeded(isSelected: smartView.isSelected(in: navigation))
        }
    }

    private func toggleAllAttachmentsSmartView() {
        var settings = smartViewSettings
        let willEnable = !settings.isBuiltInEnabled(Self.allAttachmentsSmartViewVisibilityID)
        settings.setBuiltIn(Self.allAttachmentsSmartViewVisibilityID, isEnabled: willEnable)
        settings.save()
        if !willEnable {
            leaveHiddenSmartViewIfNeeded(isSelected: navigation.isAllAttachmentsSelected)
        }
    }

    private func toggleCustomSmartView(id: SmartMailbox.ID) {
        var settings = smartViewSettings
        guard let index = settings.mailboxes.firstIndex(where: { $0.id == id }) else { return }
        let wasSelected = navigation.isSavedSearchSelected(id: id)
        settings.mailboxes[index].isEnabled.toggle()
        let isEnabled = settings.mailboxes[index].isEnabled
        settings.save()
        if !isEnabled {
            leaveHiddenSmartViewIfNeeded(isSelected: wasSelected)
        }
    }

    private func leaveHiddenSmartViewIfNeeded(isSelected: Bool) {
        guard isSelected else { return }
        if let section = sourceSections.first,
           let inbox = section.folders.first(where: { $0.role == .inbox }) {
            navigation.selectFolder(inbox.id, in: section.id)
        } else {
            navigation.selectUnifiedInbox()
        }
    }

    private func finishSavedSearchEditor() {
        let settings = SmartMailboxSettings.load()
        let shouldLeaveSelection = SavedSearchSidebarPresentation.shouldLeaveSelection(
            selectedID: navigation.selectedSavedSearchID,
            mailboxes: settings.mailboxes
        )
        savedSearchEditorTarget = nil
        leaveHiddenSmartViewIfNeeded(isSelected: shouldLeaveSelection)
    }

    private func deleteSavedSearch(id: SmartMailbox.ID) {
        let wasSelected = navigation.isSavedSearchSelected(id: id)
        var settings = SmartMailboxSettings.load()
        settings.remove(id: id)
        settings.save()
        leaveHiddenSmartViewIfNeeded(isSelected: wasSelected)
    }

    @ViewBuilder
    private var pluginSidebarItems: some View {
        let contributions = BrevPluginRegistry.shared.registeredContributions(for: .sidebarPanel)
        if !contributions.isEmpty {
            ForEach(contributions) { contribution in
                Button {
                    selectedPluginContribution = contribution
                } label: {
                    sidebarActionRow(
                        title: contribution.displayName,
                        isSelected: false,
                        leading: {
                            Image(systemName: contribution.sfSymbolName)
                                .foregroundStyle(theme.textSecondary.color)
                                .imageScale(.small)
                                .frame(width: sidebarMetrics.iconWidth, alignment: .center)
                        },
                        trailing: { EmptyView() }
                    )
                }
                .buttonStyle(.plain)
                .sheet(item: $selectedPluginContribution) { definition in
                    if let view = BrevPluginRegistry.shared.view(for: definition) {
                        view
                    }
                }
            }
            .padding(.top, BrevSpacing.xs)
        }
    }

    private func sidebarActionRow<Leading: View, Trailing: View>(
        title: String,
        isSelected: Bool,
        alignment: SidebarActionRowAlignment = .folderContent,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        let leadingPadding: CGFloat = switch alignment {
        case .folderContent:
            sidebarMetrics.folderRowLeadingPadding(depth: 0)
                + sidebarMetrics.disclosureHitSize
                + BrevSpacing.xxs
        case .sourceHeader:
            sidebarMetrics.sourceHeaderHorizontalPadding
        }

        return HStack(spacing: BrevSpacing.xs) {
            leading()
            Text(verbatim: title)
                .brevFont(.subheadline)
                .foregroundStyle(theme.textPrimary.color)
                .lineLimit(1)
            Spacer(minLength: BrevSpacing.sm)
            trailing()
        }
        .padding(.leading, leadingPadding)
        .padding(.trailing, sidebarMetrics.folderRowTrailingPadding)
        .padding(.vertical, sidebarMetrics.folderRowVerticalPadding)
        .frame(
            maxWidth: .infinity,
            minHeight: sidebarMetrics.folderRowMinimumHeight,
            alignment: .leading
        )
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: FolderSidebarSelectionPresentation.cornerRadius)
                    .fill(globalActionSelectionColor)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: FolderSidebarSelectionPresentation.cornerRadius))
    }

    /// Horizontal hierarchy for global sidebar controls and account folders.
    private enum SidebarActionRowAlignment {
        case folderContent
        case sourceHeader
    }

    private var globalActionSelectionColor: Color {
        theme.accent.color.opacity(FolderSidebarSelectionPresentation.globalActionOpacity)
    }

    private var folderSelectionColor: Color {
        theme.accent.color.opacity(FolderSidebarSelectionPresentation.folderOpacity)
    }

    @ViewBuilder
    private func sourceHeader(
        _ section: MailSourceSection,
        isExpanded: Bool
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                expandedSourceIDs = FolderSidebarSourceExpansionPolicy.toggling(
                    section.id,
                    in: expandedSourceIDs
                )
            }
        } label: {
            #if os(iOS)
            HStack(alignment: .center, spacing: BrevSpacing.sm) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textTertiary.color)
                    .frame(width: sidebarMetrics.disclosureHitSize, alignment: .center)
                Image(systemName: section.mailbox.isPrimary ? "tray.2" : "mail.stack")
                    .foregroundStyle(theme.textSecondary.color)
                    .frame(width: sidebarMetrics.iconWidth, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: section.title)
                        .brevFont(.footnote)
                        .foregroundStyle(theme.textPrimary.color)
                        .lineLimit(1)
                    Text(verbatim: section.subtitle)
                        .brevFont(.caption)
                        .foregroundStyle(theme.textTertiary.color)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, sidebarMetrics.sourceHeaderHorizontalPadding)
            .padding(.vertical, sidebarMetrics.sourceHeaderVerticalPadding)
            .frame(
                maxWidth: .infinity,
                minHeight: sidebarMetrics.sourceHeaderMinimumHeight,
                alignment: .leading
            )
            .background(theme.bgTertiary.color)
            .clipShape(RoundedRectangle(cornerRadius: BrevRadius.sm))
            #else
            HStack(alignment: .center, spacing: BrevSpacing.xs) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.textTertiary.color)
                    .frame(width: sidebarMetrics.disclosureHitSize, alignment: .center)
                Text(verbatim: section.title)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                Text(verbatim: section.subtitle)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textTertiary.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, sidebarMetrics.sourceHeaderHorizontalPadding)
            .padding(.vertical, sidebarMetrics.sourceHeaderVerticalPadding)
            .frame(
                maxWidth: .infinity,
                minHeight: sidebarMetrics.sourceHeaderMinimumHeight,
                alignment: .leading
            )
            .contentShape(Rectangle())
            #endif
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(section.title)
        .accessibilityValue(
            isExpanded
                ? String(localized: "Expanded", bundle: .module)
                : String(localized: "Collapsed", bundle: .module)
        )
    }

    private func seedSourceExpansionIfNeeded() {
        guard expandedSourceIDs.isEmpty else { return }
        expandedSourceIDs = FolderSidebarSourceExpansionPolicy.initialExpandedSourceIDs(
            sourceIDs: sourceSections.map(\.id),
            selectedSourceID: navigation.selectedSourceID
        )
    }

    @ViewBuilder
    private var mailboxHeader: some View {
        let presentation = FolderSidebarPresentation.mailboxHeader(
            isSwitchingMailbox: isSwitchingMailbox,
            isBlocked: isMailboxSwitchBlocked
        )
        VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
            Menu {
                ForEach(mailboxes) { mailbox in
                    Button {
                        if mailbox.id != activeMailboxID {
                            onSwitchMailbox?(mailbox.id)
                        }
                    } label: {
                        if mailbox.id == activeMailboxID {
                            Label(mailbox.email, systemImage: "checkmark")
                        } else {
                            Text(mailbox.email)
                        }
                    }
                }
            } label: {
                #if os(iOS)
                HStack(spacing: BrevSpacing.sm) {
                    Image(systemName: "tray.2")
                        .foregroundStyle(theme.textSecondary.color)
                        .frame(width: sidebarMetrics.iconWidth, alignment: .center)
                    Text(verbatim: activeMailbox?.email ?? String(localized: "Mailbox", bundle: .module))
                        .brevFont(.footnote)
                        .foregroundStyle(theme.textPrimary.color)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.textTertiary.color)
                }
                .padding(.horizontal, BrevSpacing.md)
                .padding(.vertical, BrevSpacing.sm)
                .frame(
                    maxWidth: .infinity,
                    minHeight: sidebarMetrics.profilePickerMinimumHeight,
                    alignment: .leading
                )
                .background {
                    RoundedRectangle(cornerRadius: BrevRadius.md)
                        .fill(theme.bgSecondary.color.opacity(0.42))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: BrevRadius.md)
                        .stroke(theme.border.color.opacity(0.45), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: BrevRadius.md))
                .contentShape(RoundedRectangle(cornerRadius: BrevRadius.md))
                #else
                HStack(spacing: BrevSpacing.sm) {
                    Image(systemName: "tray.2")
                        .foregroundStyle(theme.textSecondary.color)
                        .imageScale(.small)
                        .frame(width: sidebarMetrics.iconWidth, alignment: .center)
                    Text(verbatim: activeMailbox?.email ?? String(localized: "Mailbox", bundle: .module))
                        .brevFont(.footnote)
                        .foregroundStyle(theme.textPrimary.color)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.textTertiary.color)
                }
                .padding(.horizontal, sidebarMetrics.sourceHeaderHorizontalPadding)
                .padding(.vertical, sidebarMetrics.sourceHeaderVerticalPadding)
                .frame(
                    maxWidth: .infinity,
                    minHeight: sidebarMetrics.profilePickerMinimumHeight,
                    alignment: .leading
                )
                .contentShape(Rectangle())
                #endif
            }
            .disabled(presentation.isDisabled)
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)

            if let statusMessage = presentation.statusMessage {
                Text(statusMessage)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textTertiary.color)
                    .padding(.horizontal, BrevSpacing.xs)
            }
        }
    }

    @ViewBuilder
    private func folderList(
        folders: [Folder],
        sourceID: MailSourceID?,
        loadError: FolderLoadError?
    ) -> some View {
        if let status = FolderSidebarPresentation.status(
            folders: folders,
            loadError: loadError,
            isOffline: !monitor.isOnline
        ) {
            sidebarStatus(status)
        } else {
            let rows = FolderSidebarPresentation.visibleRows(
                folders: folders,
                visibility: effectiveFolderVisibility(for: sourceID),
                collapsedFolderIDs: collapsedFolderIDs(for: sourceID)
            )
            ForEach(rows) { row in
                folderRow(row, sourceID: sourceID)
            }
        }
    }

    private func folderRow(
        _ row: FolderSidebarRow,
        sourceID: MailSourceID?
    ) -> some View {
        let folder = row.folder
        let title = displayName(for: folder, sourceID: sourceID)
        return HStack(spacing: folderRowControlSpacing) {
            disclosureControl(for: row, sourceID: sourceID)
            Button {
                select(folder, in: sourceID)
            } label: {
                HStack(spacing: BrevSpacing.xs) {
                    roleIcon(for: folder.role)
                    Text(title)
                        .brevFont(.subheadline)
                        .foregroundStyle(theme.textPrimary.color)
                        .lineLimit(1)
                    Spacer(minLength: BrevSpacing.sm)
                    unreadBadge(folder.unreadCount)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .folderSidebarTouchTarget(minHeight: sidebarMetrics.folderRowMinimumHeight)
        }
        .padding(.leading, folderRowLeadingPadding(depth: row.depth))
        .padding(.trailing, sidebarMetrics.folderRowTrailingPadding)
        .padding(.vertical, sidebarMetrics.folderRowVerticalPadding)
        .frame(
            maxWidth: .infinity,
            minHeight: sidebarMetrics.folderRowMinimumHeight,
            alignment: .leading
        )
        .background {
            if isSelected(folder, in: sourceID) {
                RoundedRectangle(cornerRadius: FolderSidebarSelectionPresentation.cornerRadius)
                    .fill(folderSelectionColor)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: FolderSidebarSelectionPresentation.cornerRadius))
        .dropDestination(for: String.self) { representations, _ in
            handleDrop(representations, on: folder, sourceID: sourceID)
        }
        .contextMenu {
            folderContextMenu(folder: folder, sourceID: sourceID)
        }
    }

    @ViewBuilder
    private func disclosureControl(
        for row: FolderSidebarRow,
        sourceID: MailSourceID?
    ) -> some View {
        if row.hasChildren {
            let isExpanded = isFolderExpanded(row.folder.id, sourceID: sourceID)
            let title = displayName(for: row.folder, sourceID: sourceID)
            Button {
                toggleFolderDisclosure(row.folder.id, sourceID: sourceID)
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textTertiary.color)
                    .frame(
                        width: sidebarMetrics.disclosureHitSize,
                        height: sidebarMetrics.disclosureHitSize,
                        alignment: .center
                    )
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel(
                isExpanded
                    ? String(localized: "Collapse \(title)", bundle: .module)
                    : String(localized: "Expand \(title)", bundle: .module)
            )
        } else {
            Color.clear
                .frame(
                    width: sidebarMetrics.disclosureHitSize,
                    height: sidebarMetrics.disclosureHitSize
                )
        }
    }

    private func select(_ folder: Folder, in sourceID: MailSourceID?) {
        activateDestination {
            if let sourceID {
                navigation.selectFolder(folder.id, in: sourceID)
            } else {
                navigation.selectedFolderID = folder.id
                navigation.selectedMessageID = nil
            }
        }
    }

    private func activateDestination(_ selection: () -> Void) {
        FolderSidebarDestinationActivation.activate(
            selection: selection,
            onActivated: onOpenMessages
        )
    }

    private func handleDrop(
        _ representations: [String],
        on folder: Folder,
        sourceID: MailSourceID?
    ) -> Bool {
        guard let route = MessageDropRoutingPolicy.route(
            representations,
            destinationSourceID: sourceID,
            selectedSourceID: navigation.selectedSourceID
        ) else {
            return false
        }
        switch route {
        case .plain(let messageIDs):
            onDropMessages?(messageIDs, folder)
        case .source(let routeSourceID, let messageIDs):
            onDropSourceMessages?(messageIDs, routeSourceID, folder)
        }
        return true
    }

    private func collapsedFolderIDs(for sourceID: MailSourceID?) -> Set<Folder.ID> {
        guard let sourceID else {
            return disclosureState.withoutSource
        }
        return disclosureState.bySource[sourceID] ?? []
    }

    private func isFolderExpanded(_ folderID: Folder.ID, sourceID: MailSourceID?) -> Bool {
        !collapsedFolderIDs(for: sourceID).contains(folderID)
    }

    private func toggleFolderDisclosure(_ folderID: Folder.ID, sourceID: MailSourceID?) {
        var state = disclosureState
        if let sourceID {
            var ids = state.bySource[sourceID] ?? []
            if ids.remove(folderID) == nil {
                ids.insert(folderID)
            }
            if ids.isEmpty {
                state.bySource.removeValue(forKey: sourceID)
            } else {
                state.bySource[sourceID] = ids
            }
        } else {
            if state.withoutSource.remove(folderID) == nil {
                state.withoutSource.insert(folderID)
            }
        }
        // Update the in-memory cache first for an immediate UI response, then
        // persist. Rendering reads `disclosureState`, never the stored JSON.
        disclosureState = state
        saveDisclosureState(state)
    }

    private func setAllFoldersExpanded(_ expanded: Bool, sourceID: MailSourceID?) {
        var state = disclosureState
        if let sourceID {
            if expanded {
                state.bySource.removeValue(forKey: sourceID)
            } else {
                state.bySource[sourceID] = collapsibleFolderIDs(sourceID: sourceID)
            }
        } else if expanded {
            state.withoutSource.removeAll()
        } else {
            state.withoutSource = collapsibleFolderIDs(sourceID: nil)
        }
        disclosureState = state
        saveDisclosureState(state)
    }

    private func collapsibleFolderIDs(sourceID: MailSourceID?) -> Set<Folder.ID> {
        let folders = contextFolders(sourceID: sourceID)
        let parentIDs = Set(folders.compactMap(\.parentID))
        return Set(folders.map(\.id).filter { parentIDs.contains($0) })
    }

    private func contextFolders(sourceID: MailSourceID?) -> [Folder] {
        guard let sourceID else { return folders }
        return sourceSections.first(where: { $0.id == sourceID })?.folders ?? []
    }

    private func folderHasChildren(_ folder: Folder, sourceID: MailSourceID?) -> Bool {
        contextFolders(sourceID: sourceID).contains { $0.parentID == folder.id }
    }

    private func folderRowLeadingPadding(depth: Int) -> CGFloat {
        sidebarMetrics.folderRowLeadingPadding(depth: depth)
    }

    private var folderRowControlSpacing: CGFloat {
        #if os(iOS)
        BrevSpacing.xs
        #else
        BrevSpacing.xxs
        #endif
    }

    private func isSelected(_ folder: Folder, in sourceID: MailSourceID?) -> Bool {
        navigation.selectedFolderID == folder.id
            && navigation.selectedSourceID == sourceID
    }

    @ViewBuilder
    private func folderContextMenu(folder: Folder, sourceID: MailSourceID?) -> some View {
        let presentation = FolderSidebarPresentation.desktopContextMenu(
            folder: folder,
            capabilities: capabilitiesForSource(sourceID),
            isActionBlocked: isFolderActionBlocked,
            hasSourceIdentity: sourceID != nil,
            hasLocalAlias: hasLocalAlias(for: folder, sourceID: sourceID),
            hasChildren: folderHasChildren(folder, sourceID: sourceID),
            isExpanded: isFolderExpanded(folder.id, sourceID: sourceID),
            canExpandAll: !collapsedFolderIDs(for: sourceID).isEmpty,
            canCollapseAll: !collapsibleFolderIDs(sourceID: sourceID).isEmpty,
            canOpenAccountSettings: true
        )
        ForEach(presentation.sections.indices, id: \.self) { sectionIndex in
            if sectionIndex > 0 {
                Divider()
            }
            ForEach(presentation.sections[sectionIndex].actions, id: \.action) { action in
                folderContextMenuButton(action, folder: folder, sourceID: sourceID)
            }
        }
    }

    @ViewBuilder
    private func folderContextMenuButton(
        _ presentation: FolderSidebarContextMenuActionPresentation,
        folder: Folder,
        sourceID: MailSourceID?
    ) -> some View {
        switch presentation.action {
        case .newSubfolder:
            Button {
                onCreateSubfolder?(folder, sourceID)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .collapseAll:
            Button {
                setAllFoldersExpanded(false, sourceID: sourceID)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .expandAll:
            Button {
                setAllFoldersExpanded(true, sourceID: sourceID)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .markAllAsRead:
            Button {
                onMarkFolderAsRead?(folder, sourceID)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .setLocalName:
            Button {
                if let sourceID {
                    onSetFolderLocalName?(folder, sourceID)
                }
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .clearLocalName:
            Button {
                if let sourceID {
                    onClearFolderLocalName?(folder, sourceID)
                }
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .hideFromMailboxList:
            Button {
                if let sourceID {
                    onHideFolder?(folder, sourceID)
                }
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .renameFolder:
            Button {
                onRenameFolder?(folder, sourceID)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .deleteFolder:
            Button(role: .destructive) {
                onDeleteFolder?(folder, sourceID)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .flushFolder:
            Button(role: .destructive) {
                onFlushFolder?(folder, sourceID)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .refresh:
            Button {
                onRefreshFolder?(folder, sourceID)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .accountSettings:
            Button {
                onOpenSettings?()
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled || onOpenSettings == nil)
        case .openInNewWindow, .showInProfile, .properties, .downloadOffline:
            EmptyView()
        }
    }

    private func displayName(for folder: Folder, sourceID: MailSourceID?) -> String {
        FolderSidebarPresentation.displayName(
            for: folder,
            sourceID: sourceID,
            aliasPreferences: folderAliasPreferences,
            capabilities: capabilitiesForSource(sourceID)
        )
    }

    private func effectiveFolderVisibility(for sourceID: MailSourceID?) -> FolderSidebarVisibilityPreferences {
        FolderSidebarPresentation.effectiveVisibility(
            capabilities: capabilitiesForSource(sourceID),
            persisted: folderVisibility
        )
    }

    private func hasLocalAlias(for folder: Folder, sourceID: MailSourceID?) -> Bool {
        FolderAliasPreferencesPolicy.alias(
            for: folder.id,
            sourceID: sourceID,
            preferences: folderAliasPreferences
        ) != nil
    }

    private var activeMailbox: Mailbox? {
        mailboxes.first { $0.id == activeMailboxID }
    }

    private var sidebarMetrics: FolderSidebarLayoutMetrics {
        #if os(iOS)
        FolderSidebarPresentation.layoutMetrics(for: .iPhone, density: mailboxListDensity)
        #else
        FolderSidebarPresentation.layoutMetrics(for: .macOS, density: mailboxListDensity)
        #endif
    }

    private var mailboxListDensity: MailboxListDensity {
        MailboxListDensity(rawValue: listDensityRaw) ?? .comfortable
    }

    @ViewBuilder
    private func sidebarStatus(_ status: FolderSidebarStatus) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            Image(systemName: status.icon)
                .foregroundStyle(theme.textTertiary.color)
            Text(verbatim: status.title)
                .brevFont(.subheadline)
                .foregroundStyle(theme.textPrimary.color)
            Text(verbatim: status.subtitle)
                .brevFont(.caption)
                .foregroundStyle(theme.textTertiary.color)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle = status.actionTitle,
               let onRetryLoad {
                Button(action: onRetryLoad) {
                    Text(verbatim: actionTitle)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(theme.accent.color)
                .folderSidebarTouchTarget(minHeight: 44)
            }
        }
        .padding(.horizontal, BrevSpacing.xs)
        .padding(.vertical, BrevSpacing.md)
    }

    @ViewBuilder
    private func roleIcon(for role: FolderRole) -> some View {
        #if os(iOS)
        Image(systemName: systemImage(for: role))
            .foregroundStyle(theme.textSecondary.color)
            .frame(width: sidebarMetrics.iconWidth, alignment: .center)
        #else
        Image(systemName: systemImage(for: role))
            .foregroundStyle(theme.textSecondary.color)
            .imageScale(.small)
            .frame(width: sidebarMetrics.iconWidth, alignment: .center)
        #endif
    }

    @ViewBuilder
    private func unreadBadge(_ count: Int) -> some View {
        if count > 0 {
            #if os(iOS)
            Text(verbatim: "\(count)")
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
                .monospacedDigit()
                .padding(.horizontal, BrevSpacing.xs)
                .frame(
                    minWidth: sidebarMetrics.unreadBadgeMinimumWidth,
                    minHeight: sidebarMetrics.unreadBadgeMinimumHeight
                )
                .background(theme.bgTertiary.color)
                .clipShape(Capsule())
            #else
            Text(verbatim: "\(count)")
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
                .monospacedDigit()
                .frame(
                    minWidth: sidebarMetrics.unreadBadgeMinimumWidth,
                    minHeight: sidebarMetrics.unreadBadgeMinimumHeight,
                    alignment: .trailing
                )
            #endif
        }
    }

    private func systemImage(for role: FolderRole) -> String {
        switch role {
        case .inbox: return "tray"
        case .sent: return "paperplane"
        case .drafts: return "doc.text"
        case .trash: return "trash"
        case .spam: return "exclamationmark.octagon"
        case .archive: return "archivebox"
        case .snoozed: return "clock"
        case .scheduled: return "calendar.badge.clock"
        case .starred: return "flag"
        case .allMail: return "tray.full"
        case .custom: return "folder"
        }
    }
}

private extension View {
    @ViewBuilder
    func folderSidebarTouchTarget(minHeight: CGFloat) -> some View {
        #if os(iOS)
        frame(minHeight: minHeight)
            .contentShape(Rectangle())
        #else
        self
        #endif
    }

    @ViewBuilder
    func folderSidebarSquareTouchTarget(size: CGFloat) -> some View {
        #if os(iOS)
        frame(width: size, height: size)
            .contentShape(Rectangle())
        #else
        self
        #endif
    }
}

// MARK: - Disclosure state persistence

private struct FolderDisclosureState: Codable, Equatable {
    var bySource: [MailSourceID: Set<Folder.ID>] = [:]
    var withoutSource: Set<Folder.ID> = []
}
