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
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var navigation: SettingsNavigationState
    @State private var selectedPluginContribution: RegisteredContribution?
    @State private var accounts: [BrevAccount] = []
    @State private var currentAccountID: BrevAccount.ID?
    @State private var searchText = ""
    @State private var isAdvancedExpanded: Bool

    private let accountStore: any AccountStore
    private let settingsStore: SettingsPersistenceStore
    private let updateActions: SettingsUpdateActions
    private let developerActions: DeveloperSettingsActions
    @Binding private var activeTheme: BrevTheme
    @Binding private var activeAppIcon: AppIconVariant
    private let backendProvider: @MainActor (BrevAccount.ID) -> (any MailBackend)?
    private let isAddAccountAvailable: Bool
    private let onAddAccount: () async -> Void
    private let onSetDefaultAccount: (BrevAccount) async -> Void
    private let onSignOut: (BrevAccount) async -> Void
    private let onRemoveAccount: (BrevAccount) async -> Void
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
        settingsStore: SettingsPersistenceStore = .standard,
        updateActions: SettingsUpdateActions = .unavailable,
        developerActions: DeveloperSettingsActions = .unavailable,
        allFolders: [Folder] = [],
        currentFolderSourceID: MailSourceID? = nil,
        backendProvider: @MainActor @escaping (BrevAccount.ID) -> (any MailBackend)? = { _ in nil },
        isAddAccountAvailable: Bool = true,
        onAddAccount: @escaping () async -> Void = {},
        onSetDefaultAccount: ((BrevAccount) async -> Void)? = nil,
        onSignOut: @escaping (BrevAccount) async -> Void = { _ in },
        onRemoveAccount: ((BrevAccount) async -> Void)? = nil,
        onAIProviderConfigurationChanged: @escaping () async -> Void = {},
        onClose: (() -> Void)? = nil
    ) {
        self.accountStore = accountStore
        self.settingsStore = settingsStore
        self.updateActions = updateActions
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
        _isAdvancedExpanded = State(initialValue: initialSection.group == .advanced)
        self.allFolders = allFolders
        self.currentFolderSourceID = currentFolderSourceID
        self.backendProvider = backendProvider
        self.isAddAccountAvailable = isAddAccountAvailable
        self.onAddAccount = onAddAccount
        self.onSetDefaultAccount = onSetDefaultAccount ?? { account in
            await accountStore.setCurrent(account.id)
        }
        self.onSignOut = onSignOut
        self.onRemoveAccount = onRemoveAccount ?? { account in
            await accountStore.remove(account.id)
        }
        self.onAIProviderConfigurationChanged = onAIProviderConfigurationChanged
        self.onClose = onClose
    }

    public var body: some View {
        settingsContent
            .background(BrevWindowSurfaceBackground(role: .settings).ignoresSafeArea())
            .tint(theme.accent.color)
            .accessibilityAddTraits(.isModal)
            .task {
                accounts = await accountStore.accounts
                currentAccountID = await accountStore.current?.id
                for await snapshot in accountStore.subscribe() {
                    accounts = snapshot
                    currentAccountID = await accountStore.current?.id
                }
            }
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
        .frame(minWidth: 760, idealWidth: 820, minHeight: 680)
        #else
        NavigationSplitView {
            sidebar
                .frame(minWidth: 190, idealWidth: 210)
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
        .frame(minWidth: 860, minHeight: 600)
        #endif
    }

    private var compactSettingsContent: some View {
        NavigationStack {
            List {
                ForEach(filteredSettingsGroups, id: \.group) { entry in
                    compactSettingsGroup(entry.group, sections: entry.sections)
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
            .background(BrevWindowSurfaceBackground(role: .content).ignoresSafeArea())
        }
    }

    /// Mirrors sidebar grouping so iPhone list headers match split layout.
    @ViewBuilder
    private func compactSettingsGroup(
        _ group: SettingsSectionGroup,
        sections: [SettingsSection]
    ) -> some View {
        if group == .advanced, normalizedSearchText.isEmpty {
            Section {
                DisclosureGroup(
                    String(localized: "Advanced", bundle: .module),
                    isExpanded: $isAdvancedExpanded
                ) {
                    compactSettingsRows(for: sections)
                }
            }
        } else if let header = group.headerLabel {
            Section(header) {
                compactSettingsRows(for: sections)
            }
        } else {
            Section {
                compactSettingsRows(for: sections)
            }
        }
    }

    @ViewBuilder
    private func compactSettingsRows(for sections: [SettingsSection]) -> some View {
        ForEach(sections) { section in
            NavigationLink {
                detail(for: section)
                    .navigationTitle(section.title)
                #if os(iOS)
                    .toolbar { settingsDismissToolbar }
                #endif
            } label: {
                sectionRow(section)
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    navigation.select(section)
                }
            )
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        Group {
            #if os(iOS)
            List {
                ForEach(filteredSettingsGroups, id: \.group) { entry in
                    sidebarGroup(entry.group, sections: entry.sections)
                }
                if filteredSettingsGroups.isEmpty {
                    settingsSearchEmptyState
                }
                if normalizedSearchText.isEmpty {
                    pluginSettingsGroup
                }
            }
            #else
            List(selection: sidebarBinding) {
                ForEach(filteredSettingsGroups, id: \.group) { entry in
                    sidebarGroup(entry.group, sections: entry.sections)
                }
                if filteredSettingsGroups.isEmpty {
                    settingsSearchEmptyState
                }
                if normalizedSearchText.isEmpty {
                    pluginSettingsGroup
                }
            }
            #endif
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
        #endif
    }

    /// Renders one sidebar group: an optional header label (per
    /// `SettingsSectionGroup.headerLabel`) followed by its section rows.
    /// `.top` renders without a header so Accounts sits flush at the top.
    /// Advanced destinations stay collapsed until requested or matched by search.
    @ViewBuilder
    private func sidebarGroup(
        _ group: SettingsSectionGroup,
        sections: [SettingsSection]
    ) -> some View {
        if group == .advanced, normalizedSearchText.isEmpty {
            Section {
                DisclosureGroup(
                    String(localized: "Advanced", bundle: .module),
                    isExpanded: $isAdvancedExpanded
                ) {
                    sidebarRows(for: sections)
                }
            }
        } else if let header = group.headerLabel {
            Section(header) {
                sidebarRows(for: sections)
            }
        } else {
            sidebarRows(for: sections)
        }
    }

    @ViewBuilder
    private func sidebarRows(for sections: [SettingsSection]) -> some View {
        ForEach(sections) { section in
            #if os(iOS)
            Button {
                selectedPluginContribution = nil
                navigation.select(section)
            } label: {
                sectionRow(section)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(
                navigation.selected == section ? theme.selection.color : Color.clear
            )
            #else
            sectionRow(section)
                .tag(section)
                .simultaneousGesture(TapGesture().onEnded {
                    selectedPluginContribution = nil
                })
            #endif
        }
    }

    @ViewBuilder
    private var pluginSettingsGroup: some View {
        let contributions = BrevPluginRegistry.shared.registeredContributions(for: .settingsPanel)
        if !contributions.isEmpty {
            Section(String(localized: "Extensions", bundle: .module)) {
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
                    #else
                    Button {
                        selectedPluginContribution = contribution
                    } label: {
                        pluginSettingsRow(contribution)
                    }
                    .buttonStyle(.plain)
                    #endif
                }
            }
        }
    }

    private func pluginSettingsRow(_ contribution: RegisteredContribution) -> some View {
        HStack(spacing: BrevSpacing.sm) {
            Image(systemName: contribution.sfSymbolName)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.accent.color)
                .frame(width: 18, alignment: .center)
            Text(contribution.displayName)
                .brevFont(.body)
                .foregroundStyle(theme.textPrimary.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var sidebarBinding: Binding<SettingsSection?> {
        Binding(
            get: { navigation.selected },
            set: {
                selectedPluginContribution = nil
                if let s = $0 { navigation.select(s) }
            }
        )
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
                onRemoveAccount: onRemoveAccount
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
        case .rules:
            RulesSection(
                settingsStore: settingsStore,
                accounts: accounts,
                currentAccountID: currentAccountID,
                backendProvider: backendProvider
            )
        case .autoReply:
            VacationResponderSection(
                settingsStore: settingsStore,
                accounts: accounts,
                currentAccountID: currentAccountID,
                backendProvider: backendProvider
            )
        case .folderSync:
            FolderSyncSettingsSection(
                folders: allFolders,
                sourceID: currentFolderSourceID,
                backend: currentBackend,
                settingsStore: settingsStore
            )
        case .mailStorage:
            MailStorageSection(
                account: currentAccount,
                backend: currentBackend,
                settingsStore: settingsStore
            )
        case .calendarContacts:
            CalendarContactsSection()
        case .importExport:
            ImportExportSection(
                backendProvider: backendProvider,
                accounts: accounts,
                currentAccountID: currentAccountID,
                allFolders: allFolders
            )
        case .security:
            SecuritySection(settingsStore: settingsStore)
        case .privacy:
            PrivacySection(settingsStore: settingsStore)
        case .notifications:
            NotificationSection(settingsStore: settingsStore, accounts: accounts)
        case .updates:
            UpdatesSection(
                settingsStore: settingsStore,
                updateActions: updateActions
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
            detail(for: navigation.selected)
        }
    }

    private var currentBackend: (any MailBackend)? {
        guard let accountID = currentAccount?.id else { return nil }
        return backendProvider(accountID)
    }

    private var currentAccount: BrevAccount? {
        guard let currentAccountID else { return accounts.first }
        return accounts.first { $0.id == currentAccountID }
    }

    private func sectionRow(_ section: SettingsSection) -> some View {
        HStack(spacing: BrevSpacing.sm) {
            // Fixed icon column so wide SF Symbols (paintpalette, calendar.badge…)
            // don't push labels out of vertical alignment with narrower glyphs.
            Image(systemName: section.symbolName)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.accent.color)
                .frame(width: 18, alignment: .center)
            Text(section.title)
                .brevFont(.body)
                .foregroundStyle(theme.textPrimary.color)
        }
        .settingsTouchTarget()
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
