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
    #if os(macOS)
    @Environment(\.controlActiveState) private var controlActiveState
    #endif
    private var selectionPalette: MailSelectionPalette {
        #if os(macOS)
        // Focused-pane selection tint (Apple Mail): the selected row keeps
        // the full selection fill only while this pane holds keyboard focus.
        MailSelectionPalette(theme: theme, isActive: controlActiveState != .inactive && sidebarKeyboardFocus)
        #else
        MailSelectionPalette(theme: theme)
        #endif
    }

    @Environment(\.brevTheme) private var theme
    @Environment(\.networkMonitor) private var monitor
    @AppStorage("folder.disclosureState") private var disclosureStateData = Data()
    @AppStorage("mailbox.disclosureState") private var mailboxDisclosureData = Data()
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

    @State private var selectedPluginContribution: RegisteredContribution?
    /// Progressive disclosure for built-in and custom Smart Views.
    /// `nil` until the user works the disclosure control; their choice wins from
    /// then on. See `FolderSidebarSmartViewPresentation`.
    @State private var smartViewsUserExpanded: Bool?
    /// Mirrors the persisted saved-search store purely to trigger a re-render
    /// when the editor saves; actual data is read via `SmartMailboxSettings.load()`.
    @AppStorage(SmartMailboxSettings.storageKey) private var smartMailboxData = Data()
    @State private var showsSmartViewSettings = false
    @State private var savedSearchEditorTarget: SavedSearchEditorTarget?
    #if os(macOS)
    /// Focus on the sidebar — while held, arrow keys drive the selection
    /// through the visible destinations (Mail.app behavior).
    @FocusState private var sidebarKeyboardFocus: Bool
    #endif
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
    /// Opens the Calendar browsing surface (ADR-0072). Nil hides the
    /// footer entry — sessions without PIM wiring never show it.
    private let onOpenCalendar: (() -> Void)?
    /// Opens the Contacts browsing surface (ADR-0072). Nil hides the
    /// footer entry — sessions without PIM wiring never show it.
    private let onOpenContacts: (() -> Void)?
    /// Opens the Tasks browsing surface (ADR-0072 #12). Nil hides the
    /// footer entry — sessions without PIM wiring never show it.
    private let onOpenTasks: (() -> Void)?
    private let onOpenMessages: (() -> Void)?
    /// "New Local Folder…" (ADR-0077) — always offered while a local backend
    /// exists, even when the local account is hidden for having no folders.
    private let onNewLocalFolder: (() -> Void)?

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
        onOpenCalendar: (() -> Void)? = nil,
        onOpenContacts: (() -> Void)? = nil,
        onOpenTasks: (() -> Void)? = nil,
        onOpenMessages: (() -> Void)? = nil,
        onNewLocalFolder: (() -> Void)? = nil
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
        self.onOpenCalendar = onOpenCalendar
        self.onOpenContacts = onOpenContacts
        self.onOpenTasks = onOpenTasks
        self.onOpenMessages = onOpenMessages
        self.onNewLocalFolder = onNewLocalFolder
    }

    public var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            if !profiles.isEmpty || onManageProfiles != nil {
                profileSwitcher
                    .padding(.horizontal, sidebarMetrics.sidebarPadding)
                    .padding(.top, BrevSpacing.xs)
                    .padding(.bottom, sidebarMetrics.sectionSpacing)
            }
            #endif
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: sidebarMetrics.sectionSpacing) {
                        if !sourceSections.isEmpty || !profiles.isEmpty {
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
                #if os(macOS)
                // focusSection puts the sidebar in the Tab key loop so the
                // keyboard focus ring below can actually engage.
                .focusSection()
                .focusable()
                .focused($sidebarKeyboardFocus)
                .focusEffectDisabled()
                .onKeyPress(.upArrow) {
                    // Arrow input may arrive via a focused child — claim
                    // container focus so the ring reflects keyboard use.
                    sidebarKeyboardFocus = true
                    moveSidebarKeyboardSelection(by: -1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    sidebarKeyboardFocus = true
                    moveSidebarKeyboardSelection(by: 1)
                    return .handled
                }
                .onKeyPress(.leftArrow) {
                    sidebarKeyboardFocus = true
                    sidebarKeyboardCollapseOrAscend()
                    return .handled
                }
                .onKeyPress(.rightArrow) {
                    sidebarKeyboardFocus = true
                    sidebarKeyboardExpandSelection()
                    return .handled
                }
                .onKeyPress(.return) {
                    // Return opens the highlighted destination's message
                    // list: Outbox activates its own presentation, every
                    // other destination hands keyboard focus to the list
                    // column (Apple Mail's mailbox-activation hand-off).
                    if sidebarKeyboardSelectionItem == .outbox {
                        if let item = sidebarKeyboardSelectionItem {
                            activateSidebarKeyboardItem(item)
                        }
                    } else {
                        onOpenMessages?()
                    }
                    return .handled
                }
                // No visible ring — Apple Mail implies the focused pane
                // by the row selection tint alone.
                .onChange(of: sidebarKeyboardSelectionItem) { _, item in
                    guard let item else { return }
                    proxy.scrollTo(item)
                }
                #endif
            }
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        #if os(iOS)
            .toolbar {
                if !profiles.isEmpty || onManageProfiles != nil {
                    ToolbarItem(placement: .principal) {
                        profileSwitcher
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                sidebarFooter
            }
        #endif
            .onAppear {
                disclosureState = loadDisclosureState()
                restoreSourceExpansion()
                #if os(macOS)
                // Mail starts cold with the mailbox column as the key view,
                // so its selection renders in the active tint at launch.
                sidebarKeyboardFocus = true
                #endif
            }
            .onChange(of: disclosureStateData) { disclosureState = loadDisclosureState() }
            .onChange(of: expandedSourceIDs) {
                mailboxDisclosureData = (try? JSONEncoder().encode(expandedSourceIDs)) ?? Data()
            }
            .onChange(of: mailboxDisclosureData) {
                if let saved = try? JSONDecoder().decode(Set<MailSourceID>.self, from: mailboxDisclosureData) {
                    expandedSourceIDs = saved
                }
            }
            .onChange(of: navigation.selectedSourceID) { _, selectedSourceID in
                guard let selectedSourceID, navigation.browsingFolderID == nil else { return }
                expandedSourceIDs = FolderSidebarSourceExpansionPolicy.expandingSelection(
                    selectedSourceID,
                    in: expandedSourceIDs
                )
            }
            .onChange(of: smartMailboxData) {
                let settings = smartViewSettings
                let selectedHidden = !settings.showInSidebar && hasSelectedSmartView
                    || MailboxSmartView.builtIns.contains { $0.isSelected(in: navigation) && !settings.isBuiltInEnabled($0.id) }
                    || navigation.isAllAttachmentsSelected && !settings.isBuiltInEnabled(Self.allAttachmentsSmartViewVisibilityID)
                    || SavedSearchSidebarPresentation.shouldLeaveSelection(
                        selectedID: navigation.selectedSavedSearchID, mailboxes: settings.mailboxes
                    )
                leaveHiddenSmartViewIfNeeded(isSelected: selectedHidden)
            }
            .sheet(isPresented: $showsSmartViewSettings) {
                VStack(spacing: 0) {
                    SmartViewsSection(mailboxes: smartViewMailboxes)
                    HStack {
                        Spacer()
                        Button(String(localized: "Done", bundle: .module)) { showsSmartViewSettings = false }
                            .keyboardShortcut(.defaultAction)
                    }
                    .padding(BrevSpacing.lg)
                }
                .background(theme.bgPrimary.color)
                #if os(macOS)
                    .frame(width: 680, height: 570)
                #endif
            }
            .sheet(item: $savedSearchEditorTarget) { target in
                switch target {
                case .create:
                    SavedSearchEditorView(mailboxes: smartViewMailboxes, onFinished: finishSavedSearchEditor)
                case .edit(let mailbox):
                    SavedSearchEditorView(editing: mailbox, mailboxes: smartViewMailboxes, onFinished: finishSavedSearchEditor)
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

    /// iOS only. macOS reaches Settings, Calendar, and Contacts from the
    /// app/Window menus; iPhone has no menu bar, and the navigation bar's
    /// gear is easy to miss, so the sidebar keeps persistent entries at its
    /// foot — where Spark keeps it.
    #if os(iOS)
    @ViewBuilder
    private var sidebarFooter: some View {
        if onOpenSettings != nil || onOpenCalendar != nil
            || onOpenContacts != nil || onOpenTasks != nil {
            VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                if let onOpenCalendar {
                    footerButton(
                        title: String(localized: "Calendar", bundle: .module),
                        systemImage: "calendar",
                        action: onOpenCalendar
                    )
                }
                if let onOpenContacts {
                    footerButton(
                        title: String(localized: "Contacts", bundle: .module),
                        systemImage: "person.crop.circle",
                        action: onOpenContacts
                    )
                }
                if let onOpenTasks {
                    footerButton(
                        title: String(localized: "Tasks", bundle: .module),
                        systemImage: "checklist",
                        action: onOpenTasks
                    )
                }
                if let onOpenSettings {
                    footerButton(
                        title: String(localized: "Settings", bundle: .module),
                        systemImage: "gearshape",
                        action: onOpenSettings
                    )
                }
            }
            .padding(.horizontal, BrevSpacing.md)
            .padding(.vertical, BrevSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The footer sits above a scrolling tree. Keep it opaque so account
            // and folder labels do not show through behind the footer actions.
            .background(theme.bgPrimary.color)
        }
    }

    private func footerButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .brevFont(.footnote)
                .padding(.horizontal, BrevSpacing.md)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .background(Capsule().fill(theme.bgSecondary.color))
                .foregroundStyle(theme.textPrimary.color)
        }
        .buttonStyle(.plain)
        .folderSidebarTouchTarget(minHeight: sidebarMetrics.folderRowMinimumHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(title)
    }
    #endif

    @ViewBuilder
    private var sourceTree: some View {
        VStack(alignment: .leading, spacing: 0) {
            if sourceSections.count > 1 {
                unifiedInboxShortcut
            }
            if showsSmartViews, smartViewSettings.showInSidebar {
                VStack(alignment: .leading, spacing: 0) {
                    smartViewsSection
                }
                #if os(macOS)
                .padding(.top, sidebarMetrics.sectionSpacing)
                #endif
            }
            outboxButton
        }
        .padding(.bottom, sidebarMetrics.sectionSpacing)

        if sourceSections.isEmpty {
            if normalizedActiveProfileID == MailProfile.allMailboxesID {
                // Preserve the existing startup/cache/error presentation while
                // the all-mailbox workspace is still discovering its sources.
                folderList(folders: folders, sourceID: nil, loadError: loadError)
            } else {
                Text(
                    "No available mailboxes in this profile. Check Accounts in Settings or choose another profile.",
                    bundle: .module
                )
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
                .padding(.vertical, BrevSpacing.sm)
            }
        }

        ForEach(sourceSections) { section in
            Section {
                if expandedSourceIDs.contains(section.id) {
                    folderList(folders: section.folders, sourceID: section.id, loadError: section.loadError)
                }
            } header: {
                mailboxDisclosureHeader(section)
                    .padding(.top, sidebarMetrics.sectionSpacing)
            }
        }
        // Plugin-contributed sidebar panels live at the bottom, after the user's
        // own mailboxes and folders, so third-party extensions never sit above
        // real accounts.
        pluginSidebarItems
    }

    private var showsSmartViews: Bool { !sourceSections.isEmpty }

    private var profileContentSpacing: CGFloat {
        #if os(macOS)
        BrevSpacing.xs
        #else
        BrevSpacing.sm
        #endif
    }

    private var profileHeaderTitle: String {
        normalizedActiveProfileID == MailProfile.allMailboxesID
            ? String(localized: "Mailboxes", bundle: .module) : activeProfileName
    }

    private var profileSwitcher: some View {
        Menu {
            ForEach(profiles) { profile in
                Button { onSelectProfile?(profile.id) } label: {
                    menuChoice(profile.name, isSelected: profile.id == normalizedActiveProfileID)
                }
                .disabled(onSelectProfile == nil)
            }
            if let onManageProfiles {
                Divider()
                Button(action: onManageProfiles) {
                    Label(String(localized: "Manage Profiles", bundle: .module), systemImage: "person.crop.rectangle.stack")
                }
            }
        } label: {
            #if os(iOS)
            HStack(spacing: BrevSpacing.xxs) {
                Text(verbatim: profileHeaderTitle)
                    .brevFont(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.textPrimary.color)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: sidebarMetrics.profilePickerMinimumHeight)
            .contentShape(Rectangle())
            #else
            HStack(spacing: BrevSpacing.xxs) {
                Text(verbatim: profileHeaderTitle)
                    .brevFont(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.textSecondary.color)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textTertiary.color)
                    .accessibilityHidden(true)
            }
            .padding(.leading, sidebarMetrics.folderRowBaseLeadingPadding)
            .padding(.trailing, sidebarMetrics.sourceHeaderHorizontalPadding)
            .padding(.vertical, sidebarMetrics.sourceHeaderVerticalPadding)
            .frame(maxWidth: .infinity, minHeight: sidebarMetrics.sourceHeaderMinimumHeight, alignment: .leading)
            .contentShape(Rectangle())
            #endif
        }
        #if os(macOS)
        .tint(theme.textSecondary.color)
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        #endif
        .menuOrder(.fixed)
        .accessibilityLabel(String(localized: "Profile", bundle: .module))
        .accessibilityValue(activeProfileName)
        .help(String(localized: "Choose which mailboxes are visible", bundle: .module))
    }

    private var unifiedInboxShortcut: some View {
        Button {
            activateDestination { navigation.selectUnifiedInbox() }
        } label: {
            sidebarActionRow(title: String(localized: "All Inboxes", bundle: .module),
                             isSelected: navigation.isUnifiedInboxSelected, alignment: .sourceHeader) {
                Image(systemName: "tray.2")
                    .foregroundStyle(theme.textSecondary.color)
                    .font(.body)
                    .frame(width: sidebarMetrics.iconWidth)
            } trailing: {
                unreadBadge(unifiedUnreadCount)
            }
        }
        .buttonStyle(.plain)
        #if os(macOS)
            .id(SidebarKeyboardItem.unifiedInbox)
        #endif
    }

    @ViewBuilder
    private func menuChoice(_ title: String, isSelected: Bool) -> some View {
        if isSelected {
            Label { Text(verbatim: title) } icon: { Image(systemName: "checkmark") }
        } else {
            Text(verbatim: title)
        }
    }

    private func mailboxDisclosureHeader(_ section: MailSourceSection) -> some View {
        let isExpanded = expandedSourceIDs.contains(section.id)
        return Button {
            expandedSourceIDs = FolderSidebarSourceExpansionPolicy.toggling(section.id, in: expandedSourceIDs)
        } label: {
            #if os(iOS)
            HStack(spacing: BrevSpacing.xs) {
                Text(verbatim: section.title)
                    .brevFont(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: sidebarMetrics.disclosureHitSize)
                    .accessibilityHidden(true)
                Spacer(minLength: BrevSpacing.sm)
                if section.loadError != nil {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(theme.warning.color)
                } else if !isExpanded {
                    unreadBadge(section.folders.first { $0.role == .inbox }?.unreadCount ?? 0)
                }
            }
            .foregroundStyle(theme.textSecondary.color)
            .padding(.leading, sidebarMetrics.sourceHeaderHorizontalPadding)
            .padding(.trailing, sidebarMetrics.folderRowTrailingPadding)
            .padding(.vertical, sidebarMetrics.sourceHeaderVerticalPadding)
            .frame(maxWidth: .infinity, minHeight: sidebarMetrics.sourceHeaderMinimumHeight, alignment: .leading)
            .contentShape(Rectangle())
            #else
            HStack(spacing: BrevSpacing.xxs) {
                Text(verbatim: section.title)
                    .brevFont(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textTertiary.color)
                    .accessibilityHidden(true)
                Spacer(minLength: BrevSpacing.sm)
                if section.loadError != nil {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(theme.warning.color)
                } else if !isExpanded {
                    unreadBadge(section.folders.first { $0.role == .inbox }?.unreadCount ?? 0)
                }
            }
            .foregroundStyle(theme.textSecondary.color)
            .padding(.leading, sidebarMetrics.folderRowLeadingPadding(depth: 0))
            .padding(.trailing, sidebarMetrics.folderRowTrailingPadding)
            .padding(.vertical, sidebarMetrics.sourceHeaderVerticalPadding)
            .frame(maxWidth: .infinity, minHeight: sidebarMetrics.sourceHeaderMinimumHeight, alignment: .leading)
            .contentShape(Rectangle())
            #endif
        }
        .buttonStyle(.plain)
        .help("\(section.title)\n\(section.subtitle)")
        .accessibilityLabel("\(section.title), \(section.subtitle)")
        .accessibilityValue(isExpanded
            ? String(localized: "Expanded mailbox", bundle: .module)
            : String(localized: "Collapsed mailbox", bundle: .module))
        .contextMenu {
            // The local account's account-level menu (ADR-0077).
            if section.account.id == LocalMailBackend.accountID,
               let onNewLocalFolder {
                Button {
                    onNewLocalFolder()
                } label: {
                    Label(
                        String(localized: "New Local Folder…", bundle: .module),
                        systemImage: "folder.badge.plus"
                    )
                }
            }
        }
    }

    private var normalizedActiveProfileID: MailProfile.ID {
        MailProfileSelectionPolicy.selectedProfileID(activeProfileID, profiles: profiles)
    }

    private var activeProfileName: String {
        profiles.first { $0.id == normalizedActiveProfileID }?.name
            ?? String(localized: "All Mailboxes", bundle: .module)
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
            #if os(macOS)
                .id(SidebarKeyboardItem.outbox)
            #endif
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
                #if os(iOS)
                HStack(spacing: profileContentSpacing) {
                    Text("Smart Views", bundle: .module)
                        .brevFont(.caption)
                        .foregroundStyle(theme.textSecondary.color)
                        .lineLimit(1)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.textTertiary.color)
                        .accessibilityHidden(true)
                }
                #else
                HStack(spacing: BrevSpacing.xxs) {
                    Text("Smart Views", bundle: .module)
                        .brevFont(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.textSecondary.color)
                        .lineLimit(1)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.textTertiary.color)
                        .accessibilityHidden(true)
                }
                #endif
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

            Menu {
                Button(String(localized: "New Smart View", bundle: .module)) {
                    savedSearchEditorTarget = .create
                }
                Button(String(localized: "Manage Smart Views", bundle: .module)) {
                    showsSmartViewSettings = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(theme.textSecondary.color)
                    .folderSidebarSquareTouchTarget(size: sidebarMetrics.disclosureHitSize)
            }
            #if os(macOS)
            .menuStyle(.button)
            #endif
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityLabel(String(localized: "Smart View Actions", bundle: .module))
            .help(String(localized: "Smart View Actions", bundle: .module))
        }
        #if os(macOS)
        .padding(.leading, sidebarMetrics.folderRowLeadingPadding(depth: 0))
        .padding(.trailing, sidebarMetrics.folderRowTrailingPadding)
        .frame(minHeight: sidebarMetrics.folderRowMinimumHeight)
        #else
        .padding(.horizontal, sidebarMetrics.folderRowTrailingPadding)
        #endif
        .padding(.vertical, sidebarMetrics.folderRowVerticalPadding)

        if isExpanded {
            ForEach(settings.orderedEntries.filter(\.isEnabled)) { entry in
                if let builtInID = entry.builtInID {
                    if builtInID == Self.allAttachmentsSmartViewVisibilityID {
                        allAttachmentsButton
                    } else if let smartView = MailboxSmartView.builtIns.first(where: { $0.id == builtInID }) {
                        smartViewButton(smartView)
                    }
                } else if let mailbox = entry.mailbox {
                    customSmartViewButtons(settings: SmartMailboxSettings(mailboxes: [mailbox]))
                }
            }
        }
    }

    private var smartViewMailboxes: [SettingsMailbox] {
        sourceSections.map { SettingsMailbox(account: $0.account, mailbox: $0.mailbox, folders: $0.folders) }
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
    private func smartViewButton(_ smartView: MailboxSmartView) -> some View {
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
        #if os(macOS)
            .id(SidebarKeyboardItem.smartView(smartView.id))
        #endif
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
            #if os(macOS)
                .id(SidebarKeyboardItem.savedSearch(row.id))
            #endif
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
        #if os(macOS)
            .id(SidebarKeyboardItem.allAttachments)
        #endif
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
            #if os(macOS)
            sidebarMetrics.folderRowLeadingPadding(depth: 0)
                + sidebarMetrics.disclosureHitSize + BrevSpacing.xxs
            #else
            sidebarMetrics.sourceHeaderHorizontalPadding
            #endif
        }

        return HStack(spacing: BrevSpacing.xs) {
            leading()
            Text(verbatim: title)
            #if os(macOS)
                .brevFont(.body)
                .fontWeight(.regular)
            #else
                .brevFont(.subheadline)
            #endif
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
                #if os(iOS)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1).fill(selectionPalette.indicator.color)
                            .frame(width: 2).padding(.vertical, BrevSpacing.xs)
                    }
                #endif
            } else {
                #if os(macOS)
                SidebarRowHoverFill()
                #endif
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
        selectionPalette.background.color
    }

    private var folderSelectionColor: Color {
        selectionPalette.background.color
    }

    private func restoreSourceExpansion() {
        expandedSourceIDs = FolderSidebarSourceExpansionPolicy.restoredExpandedSourceIDs(
            from: mailboxDisclosureData,
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
                if let onNewLocalFolder {
                    Divider()
                    Button {
                        onNewLocalFolder()
                    } label: {
                        Label(
                            String(localized: "New Local Folder…", bundle: .module),
                            systemImage: "externaldrive"
                        )
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
                .brevQuietSurface()
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
            if let sourceID {
                ForEach(rows.map { ScopedFolderRow(row: $0, sourceID: sourceID) }) { scoped in
                    folderRow(scoped.row, sourceID: sourceID)
                }
            } else {
                ForEach(rows) { row in
                    folderRow(row, sourceID: nil)
                }
            }
        }
    }

    /// Provider folder IDs can repeat in another expanded mailbox.
    private struct ScopedFolderRow: Identifiable {
        let row: FolderSidebarRow
        let sourceID: MailSourceID
        var id: SourceFolderID { SourceFolderID(sourceID: sourceID, folderID: row.folder.id) }
    }

    #if os(macOS)
    /// Pointer-hover fill for sidebar rows — invisible until the pointer
    /// enters, matching the message list's hover feedback. Selection
    /// renders instead, so this only shows on unselected rows.
    private struct SidebarRowHoverFill: View {
        @Environment(\.brevTheme) private var theme
        @State private var isHovered = false

        var body: some View {
            RoundedRectangle(cornerRadius: FolderSidebarSelectionPresentation.cornerRadius)
                .fill(theme.bgSecondary.color)
                .opacity(isHovered ? 1 : 0)
                .onHover { isHovered = $0 }
                .animation(.easeOut(duration: 0.12), value: isHovered)
        }
    }
    #endif

    private func folderRow(
        _ row: FolderSidebarRow,
        sourceID: MailSourceID?
    ) -> some View {
        let folder = row.folder
        let title = displayName(for: folder, sourceID: sourceID)
        return HStack(spacing: folderRowControlSpacing) {
            #if os(macOS)
            disclosureControl(for: row, sourceID: sourceID)
            #endif
            Button {
                select(folder, in: sourceID)
            } label: {
                HStack(spacing: BrevSpacing.xs) {
                    roleIcon(for: folder.role)
                    Text(title)
                    #if os(iOS)
                        .brevFont(.body)
                    #else
                        .brevFont(.body)
                        .fontWeight(.regular)
                    #endif
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
            #if os(iOS)
            if row.hasChildren {
                disclosureControl(for: row, sourceID: sourceID)
            }
            #endif
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
                #if os(iOS)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1).fill(selectionPalette.indicator.color)
                            .frame(width: 2).padding(.vertical, BrevSpacing.xs)
                    }
                #endif
            } else {
                #if os(macOS)
                SidebarRowHoverFill()
                #endif
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: FolderSidebarSelectionPresentation.cornerRadius))
        #if os(macOS)
            .id(
                sourceID
                    .map {
                        SidebarKeyboardItem.folder(
                            SourceFolderID(sourceID: $0, folderID: folder.id)
                        )
                    } ?? .rootFolder(folder.id)
            )
        #endif
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
                    .font(.system(size: 11, weight: .semibold))
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
                navigation.selectFolder(folder.id, in: nil)
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
        navigation.selectedCollectionFolderID == nil
            && navigation.selectedFolderID == folder.id
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
            .font(.body)
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
                .foregroundStyle(theme.textTertiary.color)
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

    #if os(macOS)

    // MARK: - macOS keyboard navigation

    /// A selectable sidebar destination in paint order. Section headers
    /// and disclosure controls are skipped — arrows move between the
    /// destinations themselves, like Mail.app's mailbox list.
    private enum SidebarKeyboardItem: Hashable {
        case unifiedInbox
        case smartView(String)
        case allAttachments
        case savedSearch(SmartMailbox.ID)
        case outbox
        case folder(SourceFolderID)
        case rootFolder(Folder.ID)
    }

    /// A keyboard-reachable destination plus its row, when it renders a
    /// folder — depth and child state drive the left/right arrows.
    private struct SidebarKeyboardTarget {
        let item: SidebarKeyboardItem
        let row: FolderSidebarRow?
        let sourceID: MailSourceID?
    }

    /// Visible destinations in paint order — mirrors the rows the body
    /// lays out so arrow keys walk the same sequence the eye scans.
    private var sidebarKeyboardTargets: [SidebarKeyboardTarget] {
        var targets: [SidebarKeyboardTarget] = []
        if sourceSections.count > 1 {
            targets.append(
                SidebarKeyboardTarget(item: .unifiedInbox, row: nil, sourceID: nil)
            )
        }
        if showsSmartViews, smartViewSettings.showInSidebar,
           FolderSidebarSmartViewPresentation.isExpanded(
               userExpanded: smartViewsUserExpanded,
               hasSelectedSmartView: hasSelectedSmartView
           ) {
            for entry in smartViewSettings.orderedEntries.filter(\.isEnabled) {
                if let builtInID = entry.builtInID {
                    let item: SidebarKeyboardItem =
                        builtInID == Self.allAttachmentsSmartViewVisibilityID
                            ? .allAttachments
                            : .smartView(builtInID)
                    targets.append(
                        SidebarKeyboardTarget(item: item, row: nil, sourceID: nil)
                    )
                } else if let mailbox = entry.mailbox {
                    for row in SavedSearchSidebarPresentation.rows(from: [mailbox]) {
                        targets.append(
                            SidebarKeyboardTarget(
                                item: .savedSearch(row.id),
                                row: nil,
                                sourceID: nil
                            )
                        )
                    }
                }
            }
        }
        if outboxPendingCount > 0 {
            targets.append(
                SidebarKeyboardTarget(item: .outbox, row: nil, sourceID: nil)
            )
        }
        if sourceSections.isEmpty {
            // Outside the source tree the folder list always renders;
            // inside it the list only shows for the all-mailboxes profile.
            let foldersShown = profiles.isEmpty
                || normalizedActiveProfileID == MailProfile.allMailboxesID
            if foldersShown {
                targets += sidebarKeyboardFolderTargets(
                    folders: folders,
                    sourceID: nil
                )
            }
        } else {
            for section in sourceSections
                where expandedSourceIDs.contains(section.id) {
                targets += sidebarKeyboardFolderTargets(
                    folders: section.folders,
                    sourceID: section.id
                )
            }
        }
        return targets
    }

    private func sidebarKeyboardFolderTargets(
        folders: [Folder],
        sourceID: MailSourceID?
    ) -> [SidebarKeyboardTarget] {
        FolderSidebarPresentation.visibleRows(
            folders: folders,
            visibility: effectiveFolderVisibility(for: sourceID),
            collapsedFolderIDs: collapsedFolderIDs(for: sourceID)
        ).map { row in
            SidebarKeyboardTarget(
                item: sourceID
                    .map {
                        SidebarKeyboardItem.folder(
                            SourceFolderID(sourceID: $0, folderID: row.folder.id)
                        )
                    } ?? .rootFolder(row.folder.id),
                row: row,
                sourceID: sourceID
            )
        }
    }

    /// The keyboard item matching the current navigation selection, when
    /// the selection is one of the reachable destinations.
    private var sidebarKeyboardSelectionItem: SidebarKeyboardItem? {
        if navigation.isUnifiedInboxSelected { return .unifiedInbox }
        if navigation.isAllAttachmentsSelected { return .allAttachments }
        if let searchID = navigation.selectedSavedSearchID {
            return .savedSearch(searchID)
        }
        if let smartView = MailboxSmartView.builtIns
            .first(where: { $0.isSelected(in: navigation) }) {
            return .smartView(smartView.id)
        }
        if let folderID = navigation.selectedFolderID {
            if let sourceID = navigation.selectedSourceID {
                return .folder(
                    SourceFolderID(sourceID: sourceID, folderID: folderID)
                )
            }
            return .rootFolder(folderID)
        }
        return nil
    }

    private func moveSidebarKeyboardSelection(by offset: Int) {
        let targets = sidebarKeyboardTargets
        guard !targets.isEmpty else { return }
        let current = sidebarKeyboardSelectionItem
            .flatMap { item in
                targets.firstIndex { $0.item == item }
            }
        let index: Int
        if let current {
            index = min(max(current + offset, 0), targets.count - 1)
        } else {
            index = offset > 0 ? 0 : targets.count - 1
        }
        activateSidebarKeyboardItem(targets[index].item)
    }

    /// Left arrow: collapse the expanded folder under the selection, or
    /// jump selection up to its parent on a leaf/collapsed folder.
    private func sidebarKeyboardCollapseOrAscend() {
        let targets = sidebarKeyboardTargets
        guard let index = targets.firstIndex(
            where: { $0.item == sidebarKeyboardSelectionItem }
        ),
            let row = targets[index].row
        else { return }
        if row.hasChildren,
           isFolderExpanded(row.folder.id, sourceID: targets[index].sourceID) {
            toggleFolderDisclosure(
                row.folder.id,
                sourceID: targets[index].sourceID
            )
        } else if row.depth > 0,
                  let parent = targets[..<index].last(
                      where: { $0.row?.depth == row.depth - 1 }
                  ) {
            activateSidebarKeyboardItem(parent.item)
        }
    }

    /// Right arrow: expand the collapsed folder under the selection, or
    /// descend selection into its first child when already expanded.
    private func sidebarKeyboardExpandSelection() {
        let targets = sidebarKeyboardTargets
        guard let index = targets.firstIndex(
            where: { $0.item == sidebarKeyboardSelectionItem }
        ) else { return }
        guard let row = targets[index].row,
              row.hasChildren
        else {
            // → on a leaf drills into the message list for the selected
            // destination — the Finder column-view drill gesture. Outbox
            // keeps its dedicated presentation instead.
            if targets[index].item == .outbox {
                activateSidebarKeyboardItem(targets[index].item)
            } else {
                onOpenMessages?()
            }
            return
        }
        if isFolderExpanded(row.folder.id, sourceID: targets[index].sourceID) {
            if let child = targets[(index + 1)...].first(
                where: { $0.row?.depth == row.depth + 1 }
            ) {
                activateSidebarKeyboardItem(child.item)
            }
        } else {
            toggleFolderDisclosure(
                row.folder.id,
                sourceID: targets[index].sourceID
            )
        }
    }

    private func activateSidebarKeyboardItem(_ item: SidebarKeyboardItem) {
        switch item {
        case .unifiedInbox:
            activateDestination { navigation.selectUnifiedInbox() }
        case .smartView(let builtInID):
            if let smartView = MailboxSmartView.builtIns
                .first(where: { $0.id == builtInID }) {
                activateDestination { smartView.select(in: navigation) }
            }
        case .allAttachments:
            activateDestination { navigation.selectAllAttachmentsSmartView() }
        case .savedSearch(let id):
            activateDestination { navigation.selectSavedSearch(id: id) }
        case .outbox:
            onOpenOutbox?()
        case .folder, .rootFolder:
            if let target = sidebarKeyboardTargets.first(
                where: { $0.item == item }
            ),
                let folder = target.row?.folder {
                select(folder, in: target.sourceID)
            }
        }
    }
    #endif
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
