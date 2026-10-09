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
import BrevCalendar
import BrevDesign
import BrevPlugins
import BrevThemes
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Top-level settings view. macOS mounts this inside `Settings { … }`,
/// iOS presents it modally or via a navigation push from the sidebar
/// gear button. See ADR-0012.
public struct SettingsView: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var navigation: SettingsNavigationState
    @State private var selectedPluginContribution: RegisteredContribution?
    @State private var accounts: [BrevAccount] = []
    @State private var currentAccountID: BrevAccount.ID?
    private var interfaceDensity: MailboxListDensity { MailboxListDensity(rawValue: interfaceDensityRaw) ?? .comfortable }
    @AppStorage(MailboxViewPreferenceKey.listDensity) private var interfaceDensityRaw = MailboxListDensity.platformDefault
        .rawValue
    @State private var searchText = ""
    @State private var searchTarget: String?
    @State private var selectedSourceID: MailSourceID?
    /// Mirrors the mail sidebar's icons preference (Settings → Mailbox View →
    /// Show folder icons) so one toggle compacts every icon rail.
    @AppStorage(FolderPreferences.Key.showIcons) private var showSidebarIcons = true
    @State private var folderExportController = MailFolderExportController()
    @State private var pimSourceModel: PIMSourceSettingsModel?
    private let mailboxContext: SettingsMailboxContext

    private let accountStore: any AccountStore
    private let settingsStore: SettingsPersistenceStore
    private let updateActions: SettingsUpdateActions
    private let updateRing: UpdateRing
    private let developerActions: DeveloperSettingsActions
    @Binding private var activeTheme: BrevTheme
    @Binding private var activeAppIcon: AppIconVariant
    private let backendProvider: @MainActor (BrevAccount.ID) -> (any MailBackend)?
    private let isAddAccountAvailable: Bool
    private let onAddAccount: () async -> Void
    private let onSetDefaultAccount: (BrevAccount) async -> Void
    private let onSignOut: (BrevAccount) async -> Void
    private let onRemoveAccount: (BrevAccount, Bool) async -> Void
    private let linkedSourcesProvider: @MainActor (BrevAccount.ID) async -> [PIMSource]
    private let onSignInRestoredAccount: (AccountBackupEntry) -> Void
    private let onAIProviderConfigurationChanged: () async -> Void
    private let onClose: (() -> Void)?
    private let allFolders: [Folder]
    private let currentFolderSourceID: MailSourceID?

    public init(
        accountStore: any AccountStore,
        activeTheme: Binding<BrevTheme>,
        activeAppIcon: Binding<AppIconVariant> = .constant(AppIconVariant.defaultVariant),
        sectionAvailability: SettingsSectionAvailability = .v1Default,
        initialSection: SettingsSection = .accounts,
        initialAccounts: [BrevAccount] = [],
        initialCurrentAccountID: BrevAccount.ID? = nil,
        mailboxContext: SettingsMailboxContext = .init(),
        settingsStore: SettingsPersistenceStore = .standard,
        updateActions: SettingsUpdateActions = .unavailable,
        updateRing: UpdateRing = .stable,
        developerActions: DeveloperSettingsActions = .unavailable,
        allFolders: [Folder] = [],
        currentFolderSourceID: MailSourceID? = nil,
        backendProvider: @MainActor @escaping (BrevAccount.ID) -> (any MailBackend)? = { _ in nil },
        pimSourceCoordinator: PIMSourceCoordinator? = nil,
        pimCollectionService: PIMCollectionService? = nil,
        pimEventSyncService: PIMEventSyncService? = nil,
        pimContactSyncService: PIMContactSyncService? = nil,
        pimTaskSyncService: PIMTaskSyncService? = nil,
        onEnableGooglePIMFeature: ((BrevAccount.ID, PIMSourceKind) async throws -> Void)? = nil,
        onEnableGooglePIMWrite: ((BrevAccount.ID, PIMSourceKind) async throws -> Void)? = nil,
        onReauthorizeGooglePIMSource: ((BrevAccount.ID, PIMSourceKind) async throws -> Void)? = nil,
        isAddAccountAvailable: Bool = true,
        onAddAccount: @escaping () async -> Void = {},
        onSetDefaultAccount: ((BrevAccount) async -> Void)? = nil,
        onSignOut: @escaping (BrevAccount) async -> Void = { _ in },
        onRemoveAccount: ((BrevAccount, Bool) async -> Void)? = nil,
        linkedSourcesProvider: @MainActor @escaping (BrevAccount.ID) async -> [PIMSource] = { _ in [] },
        onSignInRestoredAccount: @escaping (AccountBackupEntry) -> Void = { _ in },
        onAIProviderConfigurationChanged: @escaping () async -> Void = {},
        onClose: (() -> Void)? = nil
    ) {
        self.accountStore = accountStore
        self.mailboxContext = mailboxContext
        _selectedSourceID = State(initialValue: mailboxContext.selectedSourceID)
        self.settingsStore = settingsStore
        _interfaceDensityRaw = AppStorage(wrappedValue: MailboxListDensity.platformDefault.rawValue,
                                          MailboxViewPreferenceKey.listDensity, store: settingsStore.defaults)
        self.updateActions = updateActions
        self.updateRing = updateRing
        self.developerActions = developerActions
        _activeTheme = activeTheme
        _activeAppIcon = activeAppIcon
        _accounts = State(initialValue: initialAccounts)
        _currentAccountID = State(
            initialValue: SettingsInitialAccountSelection.currentAccountID(
                from: initialCurrentAccountID,
                accounts: initialAccounts
            )
        )
        _navigation = State(
            initialValue: SettingsNavigationState(
                selected: initialSection,
                availability: sectionAvailability
            )
        )
        self.allFolders = allFolders
        self.currentFolderSourceID = currentFolderSourceID
        self.backendProvider = backendProvider
        _pimSourceModel = State(
            initialValue: pimSourceCoordinator.map {
                PIMSourceSettingsModel(
                    coordinator: $0,
                    collectionService: pimCollectionService,
                    eventSyncService: pimEventSyncService,
                    contactSyncService: pimContactSyncService,
                    taskSyncService: pimTaskSyncService,
                    googleFeatureHandler: onEnableGooglePIMFeature,
                    googleWriteFeatureHandler: onEnableGooglePIMWrite,
                    googleReauthorizeHandler: onReauthorizeGooglePIMSource
                )
            }
        )
        self.isAddAccountAvailable = isAddAccountAvailable
        self.onAddAccount = onAddAccount
        self.onSetDefaultAccount = onSetDefaultAccount ?? { account in
            await accountStore.setCurrent(account.id)
        }
        self.onSignOut = onSignOut
        self.onRemoveAccount = onRemoveAccount ?? { account, _ in
            await accountStore.remove(account.id)
        }
        self.linkedSourcesProvider = linkedSourcesProvider
        self.onAIProviderConfigurationChanged = onAIProviderConfigurationChanged
        self.onSignInRestoredAccount = onSignInRestoredAccount
        self.onClose = onClose
    }

    public var body: some View {
        settingsContent
            .brevDesktopSizing()
            .defaultAppStorage(settingsStore.defaults)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if folderExportController.state != .idle {
                    MailFolderExportStatusView(
                        state: folderExportController.state, sourceTitle: folderExportController.sourceTitle,
                        onCancel: { folderExportController.cancel() }, onDismiss: { folderExportController.dismiss() }
                    )
                    .padding(BrevSpacing.sm)
                }
            }
            .background(BrevWindowSurfaceBackground(role: .settings).ignoresSafeArea())
            .tint(theme.accent.color)
            .onChange(of: exportBackendSessionIDs) { previous, current in
                folderExportController.reconcileSessions(previous: previous, current: current)
            }
            .onChange(of: mailboxContext) { previous, next in
                selectedSourceID = next.selection(replacing: previous, current: selectedSourceID)
            }
            .task {
                accounts = await accountStore.accounts
                currentAccountID = await accountStore.current?.id
                for await snapshot in accountStore.subscribe() {
                    accounts = snapshot
                    currentAccountID = await accountStore.current?.id
                }
            }
    }

    private var exportBackendSessionIDs: [ObjectIdentifier] {
        // Export can still own account A after switching account or settings page.
        accounts.compactMap { backendProvider($0.id).map { ObjectIdentifier($0) } }
    }

    @ViewBuilder
    private var settingsContent: some View {
        switch settingsLayout {
        case .split:
            splitSettingsContent
        case .stack:
            compactSettingsContent
        }
    }

    private var settingsLayout: SettingsLayoutKind {
        #if os(iOS)
        SettingsLayoutPolicy.layout(
            for: horizontalSizeClass,
            device: settingsDevice
        )
        #else
        .split
        #endif
    }

    #if os(iOS)
    private var settingsDevice: SettingsDeviceIdiom {
        UIDevice.current.userInterfaceIdiom == .pad ? .pad : .phone
    }

    @ToolbarContentBuilder
    private var settingsDismissToolbar: some ToolbarContent {
        if SettingsDismissButtonPolicy.showsDismissButton(device: settingsDevice) {
            ToolbarItem(placement: .topBarTrailing) {
                Button(String(localized: "Done", bundle: .module)) {
                    closeSettings()
                }
                .accessibilityLabel(String(localized: "Close Settings", bundle: .module))
                .foregroundStyle(theme.textPrimary.color)
            }
        }
    }

    #endif

    private func closeSettings() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private var splitSettingsContent: some View {
        #if os(iOS)
        NavigationSplitView {
            sidebar
                .frame(minWidth: 260, idealWidth: 300)
        } detail: {
            selectedDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbar { settingsDismissToolbar }
        }
        // ~640 fits the narrowest regular-width iPad split scene (~678 pt);
        // the macOS window keeps its wider floor below.
        .frame(minWidth: 640, idealWidth: 820, minHeight: 480)
        #else
        NavigationSplitView {
            sidebar
                .frame(minWidth: 236, idealWidth: 248)
                // SwiftUI adds a sidebar toggle to any macOS
                // `NavigationSplitView`. Settings windows do not have one —
                // System Settings, Mail, and Xcode all keep the pane list
                // permanently visible, because collapsing it strands the user
                // in a detail pane with no way back to the list. The modifier
                // belongs on the column that contributes the item, not on the
                // split view.
                .toolbar(removing: .sidebarToggle)
        } detail: {
            selectedDetail
                .frame(minWidth: 620, idealWidth: 740, minHeight: 540)
        }
        .frame(minWidth: 900, minHeight: 600)
        #endif
    }

    private var compactSettingsContent: some View {
        NavigationStack {
            List {
                if !normalizedSearchText.isEmpty {
                    ForEach(searchResults) { result in
                        NavigationLink {
                            compactPane(for: result.section)
                                .environment(\.settingsSearchTarget, result.target)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(result.title)
                                Text(result.section.category.title + " › " + result.section.title).brevFont(.footnote)
                            }
                        }
                        .listRowBackground(theme.bgPrimary.color)
                    }
                } else {
                    compactRootSections
                }
                if filteredSettingsGroups.isEmpty {
                    settingsSearchEmptyState
                }
                if normalizedSearchText.isEmpty {
                    pluginSettingsGroup
                }
            }
            .navigationTitle(String(localized: "Settings", bundle: .module))
            .searchable(
                text: $searchText,
                placement: .automatic,
                prompt: String(localized: "Search Settings", bundle: .module)
            )
            #if os(iOS)
            .toolbar { settingsDismissToolbar }
            #endif
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.plain)
            #endif
            .scrollContentBackground(.hidden)
            .background(theme.bgSecondary.color.ignoresSafeArea())
        }
    }

    /// One root list in the iOS Settings style: a section per category, each
    /// row pushing straight to its pane. Multi-pane categories keep their name
    /// as the section header; single-pane categories need none.
    @ViewBuilder
    private var compactRootSections: some View {
        ForEach(navigation.availability.visibleCategories) { category in
            let sections = category.sections(in: navigation.availability)
            Section {
                ForEach(sections) { section in
                    NavigationLink {
                        compactPane(for: section)
                    } label: {
                        sectionRow(section)
                    }
                    .listRowBackground(theme.bgPrimary.color)
                }
            } header: {
                if sections.count > 1 {
                    Text(category.title)
                        .textCase(nil)
                        .foregroundStyle(theme.textSecondary.color)
                }
            }
        }
    }

    private func compactPane(for section: SettingsSection) -> some View {
        scopedDetail(for: section)
            .navigationTitle(section.title)
            .onAppear { navigation.select(section) }
        #if os(iOS)
            .toolbar { settingsDismissToolbar }
        #endif
    }

    @ViewBuilder
    private var sidebar: some View {
        Group {
            if !normalizedSearchText.isEmpty {
                List {
                    if searchResults.isEmpty { settingsSearchEmptyState }
                    ForEach(searchResults) { result in
                        Button {
                            searchTarget = result.target
                            selectedPluginContribution = nil
                            navigation.select(result.section)
                        } label: {
                            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                                Text(result.title).foregroundStyle(theme.textPrimary.color)
                                Text(result.section.category.title + " › " + result.section.title)
                                    .brevFont(.footnote)
                                    .foregroundStyle(theme.textSecondary.color)
                            }
                            .padding(.vertical, BrevSpacing.xs)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                List {
                    Section { sidebarCategoryRows(supplementary: false) }
                    Section { sidebarCategoryRows(supplementary: true) }
                    if filteredSettingsGroups.isEmpty {
                        settingsSearchEmptyState
                    }
                    if normalizedSearchText.isEmpty {
                        pluginSettingsGroup
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(
            text: $searchText,
            placement: .sidebar,
            prompt: String(localized: "Search Settings", bundle: .module)
        )
        .scrollContentBackground(.hidden)
        .background(BrevWindowSurfaceBackground(role: .sidebar).ignoresSafeArea())
        #if os(macOS)
            .background(BrevSplitViewColumnTransparencyFixer())
            // Handle arrows when the native sidebar list itself holds keyboard focus.
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                guard normalizedSearchText.isEmpty else { return .ignored }
                let categories = navigation.availability.visibleCategories
                guard let index = categories.firstIndex(of: navigation.selected.category) else { return .ignored }
                let offset = press.key == .downArrow ? 1 : -1
                let next = min(max(index + offset, 0), categories.count - 1)
                selectedPluginContribution = nil
                searchTarget = nil
                selectCategory(categories[next])
                return .handled
            }
        #endif
    }

    private func selectCategory(_ category: SettingsCategory) {
        guard let section = category.sections(in: navigation.availability).first else { return }
        selectedPluginContribution = nil
        searchTarget = nil
        navigation.select(section)
    }

    private func categoryRow(_ category: SettingsCategory) -> some View {
        HStack(spacing: BrevSpacing.sm) {
            if showSidebarIcons {
                Image(systemName: category.symbolName)
                    .brevFont(.body)
                #if os(iOS)
                    .dynamicTypeSize(...DynamicTypeSize.large)
                #endif
                    .foregroundStyle(theme.textSecondary.color)
                    .frame(width: SettingsLayout.symbolWidth)
            }
            Text(category.title)
                .lineLimit(nil)
                .brevFont(.body)
                .foregroundStyle(theme.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .settingsTouchTarget()
    }

    private func sidebarCategoryRows(supplementary: Bool) -> some View {
        ForEach(navigation.availability.visibleCategories.filter { $0.isSupplementary == supplementary }) { category in
            let selected = selectedPluginContribution == nil && navigation.selected.category == category
            Button { selectCategory(category) } label: {
                sidebarRowChrome(categoryRow(category), selected: selected)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .listRowInsets(sidebarRowInsets)
        }
    }

    /// Selection pill shared by category and extension rows so every sidebar
    /// icon sits on one column under the search field's glyph.
    private func sidebarRowChrome(_ row: some View, selected: Bool) -> some View {
        row
            .padding(.horizontal, BrevSpacing.sm)
            .padding(
                .vertical,
                (MailboxListDensity(rawValue: interfaceDensityRaw) ?? .comfortable).desktopSpacing(BrevSpacing.xs)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? theme.selection.color : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: BrevRadius.md))
            .contentShape(Rectangle())
    }

    /// The sidebar list insets rows a few points inside the search field;
    /// pull the pill out so both share the same leading and trailing edges.
    private var sidebarRowInsets: EdgeInsets {
        #if os(macOS)
        EdgeInsets(top: 1, leading: -BrevSpacing.xs, bottom: 1, trailing: -BrevSpacing.xs)
        #else
        EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0)
        #endif
    }

    @ViewBuilder
    private var pluginSettingsGroup: some View {
        let contributions = BrevPluginRegistry.shared.registeredContributions(for: .settingsPanel)
        if !contributions.isEmpty {
            Section {
                ForEach(contributions) { contribution in
                    #if os(iOS)
                    NavigationLink {
                        if let view = BrevPluginRegistry.shared.view(for: contribution) {
                            view
                                .environment(\.brevTheme, theme)
                                .navigationTitle(contribution.displayName)
                        }
                    } label: {
                        pluginSettingsRow(contribution)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: BrevSpacing.md, bottom: 0, trailing: BrevSpacing.md))
                    .listRowBackground(theme.bgPrimary.color)
                    #else
                    Button {
                        selectedPluginContribution = contribution
                    } label: {
                        sidebarRowChrome(
                            pluginSettingsRow(contribution),
                            selected: selectedPluginContribution == contribution
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedPluginContribution == contribution ? .isSelected : [])
                    .listRowInsets(sidebarRowInsets)
                    #endif
                }
            } header: {
                Text("Extensions", bundle: .module)
                    .brevFont(.footnote)
                    .foregroundStyle(theme.textSecondary.color)
                #if os(macOS)
                    .padding(.leading, BrevSpacing.sm)
                #endif
            }
        }
    }

    private func pluginSettingsRow(_ contribution: RegisteredContribution) -> some View {
        HStack(spacing: BrevSpacing.sm) {
            if showSidebarIcons {
                Image(systemName: contribution.sfSymbolName)
                    .symbolRenderingMode(.hierarchical)
                    .brevFont(.body)
                #if os(iOS)
                    .dynamicTypeSize(...DynamicTypeSize.large)
                #endif
                    .foregroundStyle(theme.textSecondary.color)
                    .frame(width: SettingsLayout.symbolWidth)
            }
            Text(contribution.displayName)
                .brevFont(.body)
                .foregroundStyle(theme.textPrimary.color)
        }
        .settingsTouchTarget()
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func detail(for section: SettingsSection) -> some View {
        switch section {
        case .accounts:
            AccountsSection(
                accounts: accounts,
                currentAccountID: currentAccountID,
                backendProvider: backendProvider,
                isAddAccountAvailable: isAddAccountAvailable,
                onAddAccount: onAddAccount,
                onSetDefault: onSetDefaultAccount,
                onSignOut: onSignOut,
                onRemoveAccount: onRemoveAccount,
                linkedSourcesProvider: linkedSourcesProvider,
                onSignInRestoredAccount: onSignInRestoredAccount
            )
        case .appearance:
            AppearanceSection(
                activeTheme: $activeTheme,
                activeAppIcon: $activeAppIcon,
                settingsStore: settingsStore
            )
        case .mailboxView:
            MailboxViewSection(settingsStore: settingsStore)
        case .signature:
            SignatureSection(settingsStore: settingsStore, accounts: accounts)
        case .compose:
            ComposeSection(settingsStore: settingsStore)
        case .templates:
            TemplatesSection(settingsStore: settingsStore, accounts: accounts)
        case .vipAndReminders:
            VIPAndRemindersSection(settingsStore: settingsStore)
        case .smartViews:
            SmartViewsSection(mailboxes: mailboxContext.mailboxes, settingsStore: settingsStore)
        case .rules:
            RulesSection(
                settingsStore: settingsStore,
                accounts: accounts,
                currentAccountID: selectedSourceID?.accountID ?? currentAccountID,
                backendProvider: backendProvider
            )
        case .autoReply:
            VacationResponderSection(
                settingsStore: settingsStore,
                accounts: accounts,
                currentAccountID: selectedSourceID?.accountID ?? currentAccountID,
                backendProvider: backendProvider
            )
        case .folderSync:
            FolderSyncSettingsSection(
                folders: selectedMailbox?.folders ?? allFolders,
                sourceID: selectedMailbox?.id ?? currentFolderSourceID,
                backend: currentBackend,
                settingsStore: settingsStore
            )
            .id(selectedSourceID)
        case .mailStorage:
            MailStorageSection(
                account: currentAccount,
                backend: currentBackend,
                settingsStore: settingsStore,
                localBackend: backendProvider(LocalMailBackend.accountID) as? LocalMailBackend
            )
            .id(selectedSourceID?.accountID)
        case .calendarContacts:
            CalendarContactsSection(
                model: pimSourceModel,
                googleAccounts: accounts.filter {
                    $0.backendIdentifier == BrevAccount.gmailAPIBackendIdentifier
                }
            )
        case .importExport:
            ImportExportSection(
                backendProvider: backendProvider,
                accounts: accounts,
                currentAccountID: selectedSourceID?.accountID ?? currentAccountID,
                exportController: folderExportController,
                allFolders: allFolders,
                settingsStore: settingsStore,
                localBackendProvider: {
                    backendProvider(LocalMailBackend.accountID) as? LocalMailBackend
                }
            )
        case .security:
            SecuritySection(settingsStore: settingsStore)
        case .preferenceSync:
            PreferenceSyncSection(settingsStore: settingsStore)
        case .privacy:
            PrivacySection(settingsStore: settingsStore)
        case .notifications:
            NotificationSection(settingsStore: settingsStore, accounts: accounts)
        case .updates:
            UpdatesSection(
                settingsStore: settingsStore,
                updateActions: updateActions,
                ring: updateRing
            )
        case .aiWriter:
            AIWriterSection(
                settingsStore: settingsStore,
                accounts: accounts,
                onProviderConfigurationChanged: onAIProviderConfigurationChanged
            )
        case .developer:
            DeveloperSection(settingsStore: settingsStore, actions: developerActions)
        case .about:
            AboutSection()
        }
    }

    @ViewBuilder
    private var selectedDetail: some View {
        if let contribution = selectedPluginContribution,
           let view = BrevPluginRegistry.shared.view(for: contribution) {
            view
                .environment(\.brevTheme, theme)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                let category = navigation.selected.category
                let sections = category.sections(in: navigation.availability)
                if sections.count > 1 {
                    VStack(alignment: .leading, spacing: BrevSpacing.md) {
                        Text(category.title).brevFont(.headline)
                            .foregroundStyle(theme.textPrimary.color)
                        ViewThatFits(in: .horizontal) {
                            if !dynamicTypeSize.isAccessibilitySize {
                                sectionPicker(category: category, sections: sections)
                                    .pickerStyle(.segmented)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            sectionPicker(category: category, sections: sections)
                                .pickerStyle(.menu)
                        }
                    }
                    .padding(.horizontal, SettingsLayout.paneHorizontalInset(interfaceDensity))
                    .padding(.vertical, BrevSpacing.lg)
                    Divider().overlay(theme.border.color)
                }
                scopedDetail(for: navigation.selected)
                    .environment(\.settingsSearchTarget, searchTarget)
            }
        }
    }

    private func sectionPicker(category: SettingsCategory, sections: [SettingsSection]) -> some View {
        Picker(category.title, selection: Binding(
            get: { navigation.selected },
            set: { section in searchTarget = nil; navigation.select(section) }
        )) {
            ForEach(sections) { section in Text(section.title).tag(section) }
        }
        .labelsHidden()
    }

    private func scopedDetail(for section: SettingsSection) -> some View {
        #if os(iOS)
        // iPhone panes scroll the scope with their content so the large
        // navigation title flows straight into the pane, as in iOS Settings.
        detail(for: section)
            .environment(\.settingsScopeCaption, settingsScopeCaption(for: section))
            .environment(\.settingsScopeAccessory, inlineSettingsScope(for: section))
            .background(BrevWindowSurfaceBackground(role: .content).ignoresSafeArea())
        #else
        VStack(spacing: 0) {
            settingsScope(for: section)
            detail(for: section)
        }
        .environment(\.settingsScopeCaption, settingsScopeCaption(for: section))
        #endif
    }

    #if os(iOS)
    private func inlineSettingsScope(for section: SettingsSection) -> AnyView? {
        switch section {
        case .mailStorage:
            AnyView(
                SettingsRowLabel(
                    symbolName: "person.crop.circle",
                    title: currentAccount?.emailAddress ?? String(localized: "No account selected", bundle: .module),
                    subtitle: String(localized: "Storage and repair actions apply to this entire account.", bundle: .module)
                )
            )
        case .folderSync:
            AnyView(inlineMailboxPicker)
        default:
            nil
        }
    }

    @ViewBuilder
    private var inlineMailboxPicker: some View {
        if mailboxContext.mailboxes.isEmpty {
            SettingsRowLabel(
                symbolName: "tray",
                title: String(localized: "Mailbox", bundle: .module),
                subtitle: String(localized: "Open a mailbox in Mail to choose its settings.", bundle: .module)
            )
        } else {
            ViewThatFits(in: .horizontal) {
                if !dynamicTypeSize.isAccessibilitySize {
                    HStack(spacing: BrevSpacing.md) {
                        mailboxRowTitle
                        Spacer(minLength: BrevSpacing.sm)
                        mailboxMenu.fixedSize()
                            .padding(.trailing, -SettingsLayout.menuButtonInset)
                    }
                }
                VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                    mailboxRowTitle
                    wrappingMailboxMenu
                        .settingsStackedControl()
                }
            }
            .frame(minHeight: 44)
        }
    }

    private var mailboxRowTitle: some View {
        HStack(spacing: SettingsLayout.symbolSpacing) {
            SettingsSymbol(symbolName: "tray")
            Text("Mailbox", bundle: .module)
                .brevFont(.body)
                .foregroundStyle(theme.textPrimary.color)
        }
    }

    /// The system menu button clips a wrapped label, so accessibility sizes
    /// use a plain menu whose label can grow onto a second line.
    private var wrappingMailboxMenu: some View {
        Menu {
            mailboxPicker.pickerStyle(.inline)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: BrevSpacing.xxs) {
                Text(selectedMailbox.map(mailboxPickerTitle) ?? String(localized: "Choose mailbox", bundle: .module))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
            }
            .brevFont(.body)
            .foregroundStyle(theme.textSecondary.color)
        }
        .accessibilityLabel(String(localized: "Settings mailbox", bundle: .module))
    }

    private var mailboxMenu: some View {
        mailboxPicker
            .pickerStyle(.menu)
            .accessibilityLabel(String(localized: "Settings mailbox", bundle: .module))
    }

    private var mailboxPicker: some View {
        Picker(String(localized: "Mailbox", bundle: .module), selection: $selectedSourceID) {
            if selectedMailbox == nil {
                Text("Choose mailbox", bundle: .module).tag(MailSourceID?.none)
            }
            ForEach(mailboxContext.mailboxes) { item in
                Text(verbatim: mailboxPickerTitle(item)).tag(Optional(item.id))
            }
        }
        .labelsHidden()
    }
    #endif

    private func settingsScopeCaption(for section: SettingsSection) -> String? {
        [.appearance, .mailboxView, .compose, .vipAndReminders, .privacy, .preferenceSync].contains(section)
            ? String(localized: "Applies to all mailboxes", bundle: .module)
            : nil
    }

    private var selectedMailbox: SettingsMailbox? {
        mailboxContext.mailboxes.first { $0.id == selectedSourceID }
    }

    @ViewBuilder
    private func settingsScope(for section: SettingsSection) -> some View {
        if section == .mailStorage {
            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                Text(currentAccount?.emailAddress ?? String(localized: "No account selected", bundle: .module))
                    .brevFont(.body)
                    .foregroundStyle(theme.textPrimary.color)
                Text("Storage and repair actions apply to this entire account.", bundle: .module)
                    .brevFont(.footnote)
                    .foregroundStyle(theme.textSecondary.color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SettingsLayout.paneHorizontalInset(interfaceDensity))
            .padding(.vertical, BrevSpacing.sm)
            .background(theme.bgSecondary.color)
        } else if section == .folderSync {
            Group {
                if mailboxContext.mailboxes.isEmpty {
                    SettingsRowLabel(
                        symbolName: "tray",
                        title: String(localized: "Mailbox", bundle: .module),
                        subtitle: String(localized: "Open a mailbox in Mail to choose its settings.", bundle: .module)
                    )
                } else {
                    SettingsPickerRow(
                        symbolName: "tray",
                        title: String(localized: "Mailbox", bundle: .module),
                        subtitle: String(localized: "These settings apply only to the selected mailbox.", bundle: .module),
                        selection: $selectedSourceID
                    ) {
                        if selectedMailbox == nil {
                            Text("Choose mailbox", bundle: .module).tag(MailSourceID?.none)
                        }
                        ForEach(mailboxContext.mailboxes) { item in
                            Text(verbatim: mailboxPickerTitle(item))
                                .tag(Optional(item.id))
                        }
                    }
                    .accessibilityLabel(String(localized: "Settings mailbox", bundle: .module))
                }
            }
            .padding(.horizontal, SettingsLayout.paneHorizontalInset(interfaceDensity))
            .padding(.vertical, BrevSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.bgSecondary.color)
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.separator.color).frame(height: 1)
            }
        }
    }

    /// Display names stay short in the scope menu; the address is only added
    /// when two mailboxes would otherwise read the same.
    private func mailboxPickerTitle(_ item: SettingsMailbox) -> String {
        let name = item.mailbox.displayName
        let isAmbiguous = name.isEmpty
            || mailboxContext.mailboxes.filter { $0.mailbox.displayName == name }.count > 1
        return isAmbiguous ? item.mailbox.email : name
    }

    private var currentBackend: (any MailBackend)? {
        guard let accountID = currentAccount?.id else { return nil }
        return backendProvider(accountID)
    }

    private var currentAccount: BrevAccount? {
        guard let currentAccountID = selectedSourceID?.accountID ?? currentAccountID else { return accounts.first }
        return accounts.first { $0.id == currentAccountID }
    }

    private func sectionRow(_ section: SettingsSection) -> some View {
        HStack(spacing: BrevSpacing.sm) {
            if showSidebarIcons {
                // Fixed icon column so wide SF Symbols (paintpalette, calendar.badge…)
                // don't push labels out of vertical alignment with narrower glyphs.
                SettingsSymbol(symbolName: section.symbolName)
            }
            Text(section.title)
                .brevFont(.body)
                .foregroundStyle(theme.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .settingsTouchTarget()
    }

    private var searchResults: [SettingsSearchResult] {
        SettingsSearchResult.results(for: normalizedSearchText, sections: navigation.availability.visibleSections)
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredSettingsGroups: [(group: SettingsSectionGroup, sections: [SettingsSection])] {
        navigation.availability.groupedVisibleSections(matching: normalizedSearchText)
    }

    private var settingsSearchEmptyState: some View {
        VStack(spacing: BrevSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.textTertiary.color)
            Text("No Settings Found", bundle: .module)
                .brevFont(.headline)
                .foregroundStyle(theme.textPrimary.color)
            Text("Try a setting name, action, or provider.", bundle: .module)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BrevSpacing.lg)
    }
}

private extension View {
    @ViewBuilder
    func settingsTouchTarget() -> some View {
        #if os(iOS)
        frame(minHeight: 44)
            .contentShape(Rectangle())
        #else
        self
        #endif
    }
}

enum SettingsInitialAccountSelection {
    static func currentAccountID(
        from requestedID: BrevAccount.ID?,
        accounts: [BrevAccount]
    ) -> BrevAccount.ID? {
        guard !accounts.isEmpty else { return nil }
        if let requestedID,
           accounts.contains(where: { $0.id == requestedID }) {
            return requestedID
        }
        return accounts[0].id
    }
}

private struct RoadmapSection: View {
    let title: String
    let subtitle: String

    var body: some View {
        SectionScaffold(title: title, subtitle: subtitle) {
            EmptyView()
        }
    }
}
