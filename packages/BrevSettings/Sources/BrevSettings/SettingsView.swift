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
    @State private var searchTarget: String?
    @State private var selectedSourceID: MailSourceID?
    private let mailboxContext: SettingsMailboxContext

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
        mailboxContext: SettingsMailboxContext = .init(),
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
        self.mailboxContext = mailboxContext
        _selectedSourceID = State(initialValue: mailboxContext.selectedSourceID)
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
                            scopedDetail(for: result.section)
                                .environment(\.settingsSearchTarget, result.target)
                                .navigationTitle(result.section.title)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(result.title)
                                Text(result.section.title).brevFont(.footnote)
                            }
                        }
                    }
                } else {
                    ForEach(filteredSettingsGroups, id: \.group) { entry in
                        compactSettingsGroup(entry.group, sections: entry.sections)
                    }
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
        if let header = group.headerLabel {
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
                scopedDetail(for: section)
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
                                Text(result.section.title)
                                    .brevFont(.footnote)
                                    .foregroundStyle(theme.textSecondary.color)
                            }
                            .padding(.vertical, BrevSpacing.xs)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
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
            .onMoveCommand { direction in
                guard normalizedSearchText.isEmpty, direction == .up || direction == .down else { return }
                let sections = filteredSettingsGroups
                    .flatMap(\.sections)
                guard let index = sections.firstIndex(of: navigation.selected) else { return }
                let offset = direction == .down ? 1 : direction == .up ? -1 : 0
                let next = min(max(index + offset, 0), sections.count - 1)
                selectedPluginContribution = nil
                searchTarget = nil
                navigation.select(sections[next])
            }
        #endif
    }

    /// Renders one sidebar group: an optional header label (per
    /// `SettingsSectionGroup.headerLabel`) followed by its section rows.
    /// Every named group shares the same heading and row alignment.
    @ViewBuilder
    private func sidebarGroup(
        _ group: SettingsSectionGroup,
        sections: [SettingsSection]
    ) -> some View {
        if let header = group.headerLabel {
            Section {
                sidebarRows(for: sections)
            } header: {
                Text(header)
                    .brevFont(.footnote)
                    .foregroundStyle(theme.textSecondary.color)
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
            Button {
                selectedPluginContribution = nil
                searchTarget = nil
                navigation.select(section)
            } label: {
                sectionRow(section)
                    .padding(.horizontal, BrevSpacing.sm)
                    .padding(.vertical, BrevSpacing.xxs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(navigation.selected == section ? theme.selection.color : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: BrevRadius.sm))
                    .overlay(alignment: .leading) {
                        if navigation.selected == section {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(BrevSelectionPalette(theme: theme).indicator.color)
                                .frame(width: 2, height: 18)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(navigation.selected == section ? .isSelected : [])
            .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
            #endif
        }
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
                    #else
                    Button {
                        selectedPluginContribution = contribution
                    } label: {
                        pluginSettingsRow(contribution)
                    }
                    .buttonStyle(.plain)
                    #endif
                }
            } header: {
                Text("Extensions", bundle: .module)
                    .brevFont(.footnote)
                    .foregroundStyle(theme.textSecondary.color)
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
                settingsStore: settingsStore
            )
            .id(selectedSourceID?.accountID)
        case .calendarContacts:
            CalendarContactsSection()
        case .importExport:
            ImportExportSection(
                backendProvider: backendProvider,
                accounts: accounts,
                currentAccountID: selectedSourceID?.accountID ?? currentAccountID,
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
            scopedDetail(for: navigation.selected)
                .environment(\.settingsSearchTarget, searchTarget)
        }
    }

    private func scopedDetail(for section: SettingsSection) -> some View {
        VStack(spacing: 0) {
            settingsScope(for: section)
            detail(for: section)
        }
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
            .padding(.horizontal, BrevSpacing.xl)
            .padding(.vertical, BrevSpacing.sm)
            .background(theme.bgSecondary.color)
        } else if section == .folderSync {
            HStack(spacing: BrevSpacing.md) {
                Image(systemName: "tray")
                if mailboxContext.mailboxes.isEmpty {
                    Text("Open a mailbox in Mail to choose its settings.", bundle: .module)
                } else {
                    Picker(String(localized: "Mailbox", bundle: .module), selection: $selectedSourceID) {
                        if selectedMailbox == nil {
                            Text("Choose mailbox", bundle: .module).tag(MailSourceID?.none)
                        }
                        ForEach(mailboxContext.mailboxes) { item in
                            Text(verbatim: "\(item.mailbox.displayName) · \(item.mailbox.email)")
                                .tag(Optional(item.id))
                        }
                    }
                    .accessibilityLabel(String(localized: "Settings mailbox", bundle: .module))
                }
            }
            .brevFont(.body)
            .foregroundStyle(theme.textPrimary.color)
            .padding(.horizontal, BrevSpacing.xl)
            .padding(.vertical, BrevSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.bgSecondary.color)
        } else if [.appearance, .mailboxView, .compose, .vipAndReminders].contains(section) {
            Text("Applies to all mailboxes", bundle: .module)
                .brevFont(.footnote)
                .foregroundStyle(theme.textSecondary.color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, BrevSpacing.xl)
                .padding(.top, BrevSpacing.sm)
        }
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
