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
import BrevThemes
import SwiftUI

public struct PerFolderSyncSection: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var symbolWidth = SettingsLayout.symbolWidth
    @State private var settings: AccountMailboxSyncSettings
    @State private var visibilityPreferences: FolderVisibilityPreferences
    @State private var relatedAutoLoadEnabled = false
    @State private var attachmentIndexingEnabled = false
    @State private var filter = ""

    private let folders: [Folder]
    private let sourceID: MailSourceID?
    private let settingsStore: SettingsPersistenceStore
    private let relatedConsentStore: RelatedConversationConsentStore
    private let attachmentConsentStore: AttachmentIndexConsentStore
    /// Whether the mailbox's backend supports local attachment indexing
    /// (ADR-0078). Gates the "Search inside attachments" control.
    private let supportsAttachmentIndexing: Bool
    private let emptyFolderMessage: String
    private let onReload: (() -> Void)?
    private let isLoading: Bool
    private let onPolicyChanged: ((Folder) -> Void)?
    private let onVisibilityChanged: ((Folder) -> Void)?

    public init(
        folders: [Folder],
        sourceID: MailSourceID? = nil,
        settings: AccountMailboxSyncSettings,
        settingsStore: SettingsPersistenceStore = .standard,
        relatedConsentStore: RelatedConversationConsentStore = .shared,
        attachmentConsentStore: AttachmentIndexConsentStore = .shared,
        supportsAttachmentIndexing: Bool = false,
        emptyFolderMessage: String? = nil,
        isLoading: Bool = false,
        onReload: (() -> Void)? = nil,
        onPolicyChanged: ((Folder) -> Void)? = nil,
        onVisibilityChanged: ((Folder) -> Void)? = nil
    ) {
        self.folders = folders
        self.isLoading = isLoading
        self.onReload = onReload
        self.sourceID = sourceID
        self.settingsStore = settingsStore
        self.relatedConsentStore = relatedConsentStore
        self.attachmentConsentStore = attachmentConsentStore
        self.supportsAttachmentIndexing = supportsAttachmentIndexing
        self.emptyFolderMessage = emptyFolderMessage ?? String(
            localized: "No folders available. Open a mailbox to configure per-folder sync.",
            bundle: .module
        )
        self.onPolicyChanged = onPolicyChanged
        self.onVisibilityChanged = onVisibilityChanged
        _settings = State(initialValue: settings)
        _visibilityPreferences = State(initialValue: settingsStore.folderVisibilityPreferences())
    }

    public var body: some View {
        SectionScaffold(
            title: String(localized: "Folder Sync", bundle: .module),
            subtitle: String(localized: "Choose offline retention and sidebar visibility for this mailbox.", bundle: .module)
        ) {
            SettingsGroupStack {
                folderOverridesGroup
                relatedMailGroup
                attachmentIndexingGroup
            }
        }
        .task(id: sourceID) {
            relatedAutoLoadEnabled = sourceID.map {
                relatedConsentStore.isAutoLoadEnabled(accountID: $0.accountID)
            } ?? false
            attachmentIndexingEnabled = sourceID.map {
                attachmentConsentStore.isEnabled(accountID: $0.accountID)
            } ?? false
        }
        // Retention can also change from the storage section; reload rather
        // than keep decoding the persisted payload during body evaluation.
        .onReceive(NotificationCenter.default.publisher(for: .brevMailboxSyncSettingsDidChange)) { _ in
            settings = settingsStore.accountMailboxSyncSettings()
        }
    }

    /// Per-mailbox consent for remote related-header lookup (ADR-0074). The
    /// explicit reader "Load related mail" action always stays available; this
    /// toggle only authorizes the same metadata lookup automatically when a
    /// conversation opens. The account comes from the context bar's mailbox —
    /// one mailbox belongs to exactly one account.
    private var relatedMailGroup: some View {
        SettingsGroup(
            title: String(localized: "Related mail", bundle: .module),
            subtitle: String(
                localized: "Look up conversation members across this mailbox's folders.",
                bundle: .module
            ),
            symbolName: "arrow.triangle.branch"
        ) {
            SettingsRowStack(spacing: BrevSpacing.md) {
                if sourceID == nil {
                    SettingsInfoCallout(
                        symbolName: "tray",
                        message: String(
                            localized: "Open a mailbox to control related-mail lookup.",
                            bundle: .module
                        ),
                        tone: .info
                    )
                } else {
                    SettingsToggleRow(
                        symbolName: "arrow.triangle.2.circlepath",
                        title: String(localized: "Automatically load related mail", bundle: .module),
                        subtitle: String(
                            localized: "When you open a conversation, ask the provider for related headers across this mailbox, including folders that aren't synced.",
                            bundle: .module
                        ),
                        isOn: relatedAutoLoadBinding
                    )

                    SettingsInfoCallout(
                        symbolName: "shield",
                        message: String(
                            localized: "Headers only. Bodies and attachments are never downloaded, and nothing is marked read. You can always use Load related mail on a single conversation instead.",
                            bundle: .module
                        ),
                        tone: .info
                    )
                }
            }
        }
    }

    private var relatedAutoLoadBinding: Binding<Bool> {
        Binding(
            get: { relatedAutoLoadEnabled },
            set: { newValue in
                relatedAutoLoadEnabled = newValue
                guard let accountID = sourceID?.accountID else { return }
                relatedConsentStore.setAutoLoadEnabled(newValue, accountID: accountID)
            }
        )
    }

    /// Per-account opt-in for local attachment-content indexing (ADR-0078).
    /// Capability-gated: only shown when the mailbox's backend advertises
    /// `.localAttachmentIndex`. All extraction is local; nothing is
    /// downloaded for indexing. Disabling removes every indexed row.
    private var attachmentIndexingGroup: some View {
        Group {
            if supportsAttachmentIndexing {
                SettingsGroup(
                    title: String(localized: "Attachments", bundle: .module),
                    subtitle: String(
                        localized: "Search the text inside attachments on this device.",
                        bundle: .module
                    ),
                    symbolName: "doc.text.magnifyingglass"
                ) {
                    SettingsRowStack(spacing: BrevSpacing.md) {
                        if sourceID == nil {
                            SettingsInfoCallout(
                                symbolName: "tray",
                                message: String(
                                    localized: "Open a mailbox to control attachment indexing.",
                                    bundle: .module
                                ),
                                tone: .info
                            )
                        } else {
                            SettingsToggleRow(
                                symbolName: "doc.text.magnifyingglass",
                                title: String(localized: "Search inside attachments", bundle: .module),
                                subtitle: attachmentIndexingSubtitle,
                                isOn: attachmentIndexingBinding
                            )

                            SettingsInfoCallout(
                                symbolName: "shield",
                                message: String(
                                    localized: "Local only. Indexed text never leaves this device, and turning this off deletes the index.",
                                    bundle: .module
                                ),
                                tone: .info
                            )
                        }
                    }
                }
            }
        }
    }

    private var attachmentIndexingSubtitle: String {
        #if os(iOS)
        String(
            localized: "Indexes text from attachments already on this iPhone; nothing is downloaded for it.",
            bundle: .module
        )
        #else
        String(
            localized: "Indexes text from attachments already on this Mac; nothing is downloaded for it.",
            bundle: .module
        )
        #endif
    }

    private var attachmentIndexingBinding: Binding<Bool> {
        Binding(
            get: { attachmentIndexingEnabled },
            set: { newValue in
                attachmentIndexingEnabled = newValue
                guard let accountID = sourceID?.accountID else { return }
                attachmentConsentStore.setEnabled(newValue, accountID: accountID)
            }
        )
    }

    @ViewBuilder
    private var refreshButton: some View {
        if let onReload {
            Button(action: onReload) {
                Label(String(localized: "Refresh", bundle: .module), systemImage: "arrow.clockwise")
            }
            .disabled(isLoading)
        }
    }

    @ViewBuilder
    private var filterField: some View {
        #if os(iOS)
        HStack(spacing: BrevSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .brevFont(.body)
                .foregroundStyle(theme.textTertiary.color)
            TextField(String(localized: "Filter folders", bundle: .module), text: $filter)
                .brevFont(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel(String(localized: "Filter folders", bundle: .module))
        }
        .padding(.horizontal, BrevSpacing.sm)
        .padding(.vertical, BrevSpacing.xs)
        .frame(maxWidth: .infinity, minHeight: 36)
        .settingsInlineSurface(cornerRadius: BrevRadius.md)
        #else
        TextField(String(localized: "Filter folders", bundle: .module), text: $filter)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel(String(localized: "Filter folders", bundle: .module))
        #endif
    }

    @ViewBuilder
    private var folderOverridesGroup: some View {
        #if os(iOS)
        iOSFolderSections
        #else
        macFolderOverridesGroup
        #endif
    }

    #if os(iOS)
    /// Folders as a plain list; each pushes a page with its own retention
    /// picker and sidebar switch instead of a three-column table.
    @ViewBuilder
    private var iOSFolderSections: some View {
        Section {
            filterField
            if isLoading {
                ProgressView().tint(theme.accent.color)
            }
            refreshButton
        }
        .listRowBackground(theme.bgPrimary.color)

        Section {
            if folders.isEmpty {
                Text(emptyFolderMessage)
                    .brevFont(.body)
                    .foregroundStyle(theme.textSecondary.color)
            } else {
                let rows = visibleRows
                ForEach(rows) { row in
                    NavigationLink {
                        folderDetail(row.folder)
                    } label: {
                        folderSummary(row)
                    }
                }
                if rows.isEmpty {
                    Text("No matching folders", bundle: .module)
                        .foregroundStyle(theme.textSecondary.color)
                }
            }
        } header: {
            Text("Folders", bundle: .module)
                .id(String(localized: "Per-folder overrides", bundle: .module))
                .textCase(nil)
                .brevFont(.footnote)
                .foregroundStyle(theme.textSecondary.color)
        } footer: {
            Text("Default follows the app's retention preference. Visibility only changes the sidebar.", bundle: .module)
                .brevFont(.footnote)
                .foregroundStyle(theme.textSecondary.color)
        }
        .listRowBackground(theme.bgPrimary.color)
    }

    private func folderSummary(_ row: FolderSyncRow) -> some View {
        let isHidden = sourceID.map {
            FolderVisibilityPreferencesPolicy.isHidden(row.folder.id, sourceID: $0, preferences: visibilityPreferences)
        } ?? false
        let retention = settings.override(for: row.folder.id, sourceID: sourceID)?.retentionPolicy
        return HStack(spacing: SettingsLayout.symbolSpacing) {
            SettingsSymbol(symbolName: folderIcon(for: row.folder.role))
            Text(row.folder.name)
                .brevFont(.body)
                .foregroundStyle(theme.textPrimary.color)
                .padding(.leading, CGFloat(min(row.depth, 6)) * 14)
            Spacer(minLength: BrevSpacing.sm)
            Text(isHidden ? String(localized: "Hidden", bundle: .module) : (retention?.displayName ?? String(
                localized: "Default",
                bundle: .module
            )))
            .brevFont(.footnote)
            .foregroundStyle(theme.textSecondary.color)
        }
        .accessibilityElement(children: .combine)
    }

    private func folderDetail(_ folder: Folder) -> some View {
        Form {
            Section {
                Toggle(isOn: mailboxListVisibilityBinding(for: folder)) {
                    Text("Show in sidebar", bundle: .module)
                        .foregroundStyle(theme.textPrimary.color)
                }
                .tint(theme.accent.color)
                .disabled(sourceID == nil)
                .accessibilityLabel(String(localized: "Show \(folder.name) in sidebar", bundle: .module))
                Picker(selection: retentionBinding(for: folder)) {
                    Text("Default", bundle: .module).tag(OfflineRetentionPolicy?.none)
                    ForEach(OfflineRetentionPolicy.allCases) { policy in
                        Text(policy.displayName).tag(Optional(policy))
                    }
                } label: {
                    Text("Keep offline", bundle: .module)
                        .foregroundStyle(theme.textPrimary.color)
                }
                .pickerStyle(.menu)
                .tint(theme.textSecondary.color)
                .accessibilityLabel(String(localized: "Offline retention for \(folder.name)", bundle: .module))
            } footer: {
                Text("Default follows the app's retention preference. Visibility only changes the sidebar.", bundle: .module)
                    .brevFont(.footnote)
                    .foregroundStyle(theme.textSecondary.color)
            }
            .listRowBackground(theme.bgPrimary.color)
        }
        .settingsFormChrome()
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
    }
    #endif

    private var macFolderOverridesGroup: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            ViewThatFits(in: .horizontal) {
                if !dynamicTypeSize.isAccessibilitySize {
                    HStack(spacing: BrevSpacing.sm) {
                        filterField
                        refreshButton
                    }
                }
                VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                    filterField
                    refreshButton
                }
            }
            if isLoading { ProgressView().controlSize(.small) }
            if folders.isEmpty {
                Text(emptyFolderMessage)
                    .brevFont(.body)
                    .foregroundStyle(theme.textSecondary.color)
                    .padding(.vertical, BrevSpacing.lg)
            } else {
                VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                    folderTableHeader
                    LazyVStack(spacing: 0) {
                        let rows = visibleRows
                        ForEach(rows) { row in
                            folderRow(row)
                            if row.id != rows.last?.id {
                                Rectangle().fill(theme.separator.color).frame(height: 1)
                            }
                        }
                    }
                }
                .padding(.horizontal, BrevSpacing.md)
                .padding(.vertical, BrevSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .settingsInlineSurface(cornerRadius: BrevRadius.md)
                if visibleRows.isEmpty {
                    Text("No matching folders", bundle: .module)
                        .foregroundStyle(theme.textSecondary.color)
                        .padding(.vertical, BrevSpacing.md)
                }
            }
            Text("Default follows the app's retention preference. Visibility only changes the sidebar.", bundle: .module)
                .brevFont(.footnote)
                .foregroundStyle(theme.textSecondary.color)
        }
    }

    /// Stacked accessibility rows carry their own "Keep offline" caption,
    /// so the header drops that column instead of mislabeling the layout.
    private var folderTableHeader: some View {
        ViewThatFits(in: .horizontal) {
            if !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: BrevSpacing.sm) {
                    Text("Folder", bundle: .module).frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
                    Text("Keep offline", bundle: .module).frame(width: 132, alignment: .leading)
                    Text("Show", bundle: .module)
                        .fixedSize()
                        .frame(width: Self.toggleColumnWidth, alignment: .trailing)
                }
            }
            HStack {
                Text("Folder", bundle: .module)
                Spacer()
                Text("Show", bundle: .module)
                    .fixedSize()
                    .frame(width: Self.toggleColumnWidth, alignment: .trailing)
            }
        }
        .brevFont(.footnote)
        .foregroundStyle(theme.textSecondary.color)
    }

    private var visibleRows: [FolderSyncRow] {
        let rows = FolderSyncRows.make(folders)
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? rows : rows.filter { $0.folder.name.localizedStandardContains(query) }
    }

    @ViewBuilder
    private func folderRow(_ row: FolderSyncRow) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityFolderRow(row)
            } else {
                regularFolderRow(row)
            }
        }
        .frame(minHeight: 40)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, BrevSpacing.xxs)
    }

    /// Accessibility sizes give each control its own line under the folder
    /// name so the menu never clips to a fixed column.
    private func accessibilityFolderRow(_ row: FolderSyncRow) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            HStack(alignment: .top) {
                folderIdentity(row)
                Spacer(minLength: BrevSpacing.sm)
                visibilityToggle(row.folder).frame(width: Self.toggleColumnWidth, alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                Text("Keep offline", bundle: .module)
                    .brevFont(.footnote)
                    .foregroundStyle(theme.textSecondary.color)
                retentionPicker(row.folder, fixedWidth: false)
                    .padding(.leading, -SettingsLayout.stackedMenuButtonInset)
            }
            .padding(.leading, CGFloat(min(row.depth, 6)) * 14 + symbolWidth + SettingsLayout.symbolSpacing)
        }
        .padding(.vertical, BrevSpacing.xs)
    }

    private func regularFolderRow(_ row: FolderSyncRow) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: BrevSpacing.sm) {
                folderIdentity(row).frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
                retentionPicker(row.folder)
                visibilityToggle(row.folder).frame(width: Self.toggleColumnWidth, alignment: .trailing)
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                    folderIdentity(row)
                    HStack(spacing: BrevSpacing.sm) {
                        Text("Keep offline", bundle: .module)
                            .brevFont(.footnote)
                            .foregroundStyle(theme.textSecondary.color)
                        retentionPicker(row.folder)
                    }
                }
                Spacer(minLength: BrevSpacing.sm)
                visibilityToggle(row.folder).frame(width: Self.toggleColumnWidth, alignment: .trailing)
            }
        }
    }

    /// Wide enough for the platform control: a macOS checkbox or a 51 pt iOS switch.
    private static let toggleColumnWidth: CGFloat = {
        #if os(iOS)
        52
        #else
        44
        #endif
    }()

    private func folderIdentity(_ row: FolderSyncRow) -> some View {
        HStack(spacing: SettingsLayout.symbolSpacing) {
            SettingsSymbol(symbolName: folderIcon(for: row.folder.role))
            Text(row.folder.name)
                .brevFont(.body)
                .foregroundStyle(theme.textPrimary.color)
                .lineLimit(2)
                .help(row.folder.name)
        }
        .padding(.leading, CGFloat(min(row.depth, 6)) * 14)
    }

    private func retentionPicker(_ folder: Folder, fixedWidth: Bool = true) -> some View {
        Picker(String(localized: "Offline retention for \(folder.name)", bundle: .module),
               selection: retentionBinding(for: folder)) {
            Text("Default", bundle: .module).tag(OfflineRetentionPolicy?.none)
            ForEach(OfflineRetentionPolicy.allCases) { policy in
                Text(policy.displayName).tag(Optional(policy))
            }
        }
        .labelsHidden()
        .frame(width: fixedWidth ? 132 : nil, alignment: .leading)
        .accessibilityLabel(String(localized: "Offline retention for \(folder.name)", bundle: .module))
    }

    private func visibilityToggle(_ folder: Folder) -> some View {
        Toggle(String(localized: "Show \(folder.name) in sidebar", bundle: .module),
               isOn: mailboxListVisibilityBinding(for: folder))
            .labelsHidden()
        #if os(macOS)
            .toggleStyle(.checkbox)
        #else
            .toggleStyle(.switch)
        #endif
            .disabled(sourceID == nil)
            .accessibilityLabel(String(localized: "Show \(folder.name) in sidebar", bundle: .module))
            .help(String(localized: "Show \(folder.name) in sidebar", bundle: .module))
    }

    private func retentionBinding(for folder: Folder) -> Binding<OfflineRetentionPolicy?> {
        Binding(
            get: { settings.override(for: folder.id, sourceID: sourceID)?.retentionPolicy },
            set: { newValue in
                settings = settingsStore.accountMailboxSyncSettings()
                settings.setRetentionPolicy(newValue, forFolderID: folder.id, sourceID: sourceID)
                settingsStore.save(settings)
                NotificationCenter.default.post(name: .brevMailboxSyncSettingsDidChange, object: nil)
                onPolicyChanged?(folder)
            }
        )
    }

    private func mailboxListVisibilityBinding(for folder: Folder) -> Binding<Bool> {
        Binding(
            get: {
                guard let sourceID else { return true }
                return !FolderVisibilityPreferencesPolicy.isHidden(
                    folder.id,
                    sourceID: sourceID,
                    preferences: visibilityPreferences
                )
            },
            set: { newValue in
                guard let sourceID else { return }
                let next = FolderVisibilityPreferencesPolicy.settingHidden(
                    !newValue,
                    folderID: folder.id,
                    sourceID: sourceID,
                    in: settingsStore.folderVisibilityPreferences()
                )
                visibilityPreferences = next
                settingsStore.save(next)
                onVisibilityChanged?(folder)
            }
        )
    }

    private func folderIcon(for role: FolderRole) -> String {
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

struct FolderSyncSettingsSection: View {
    @State private var folders: [Folder]
    @State private var sourceID: MailSourceID?
    @State private var isLoading = false
    @State private var loadErrorMessage: String?
    @State private var mailboxSyncSettings: AccountMailboxSyncSettings

    private let cachedFolders: [Folder]
    private let backend: (any MailBackend)?
    private let settingsStore: SettingsPersistenceStore

    init(
        folders: [Folder],
        sourceID: MailSourceID?,
        backend: (any MailBackend)?,
        settingsStore: SettingsPersistenceStore
    ) {
        self.backend = backend
        cachedFolders = folders
        self.settingsStore = settingsStore
        _folders = State(initialValue: folders)
        _sourceID = State(initialValue: sourceID)
        // Decoded once at init — PerFolderSyncSection keeps itself fresh via
        // .brevMailboxSyncSettingsDidChange, so body never re-reads the store.
        _mailboxSyncSettings = State(initialValue: settingsStore.accountMailboxSyncSettings())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.md) {
            PerFolderSyncSection(
                folders: folders,
                sourceID: sourceID,
                settings: mailboxSyncSettings,
                settingsStore: settingsStore,
                supportsAttachmentIndexing: backend?.extendedCapabilities
                    .contains(.localAttachmentIndex) ?? false,
                emptyFolderMessage: emptyFolderMessage,
                isLoading: isLoading,
                onReload: backend != nil && sourceID != nil ? { Task { await loadFolders() } } : nil
            )
        }
        .onChange(of: cachedFolders) { _, latest in folders = latest }
        .task(id: sourceID) {
            if folders.isEmpty, sourceID != nil { await loadFolders() }
        }
    }

    private var emptyFolderMessage: String {
        if isLoading {
            return String(localized: "Loading folders for the current mailbox…", bundle: .module)
        }
        if let loadErrorMessage {
            return String(localized: "Couldn't load folders: \(loadErrorMessage)", bundle: .module)
        }
        if sourceID == nil {
            return String(localized: "Choose a mailbox above to configure its folders.", bundle: .module)
        }
        return String(localized: "No folders available. Open a mailbox to configure per-folder sync.", bundle: .module)
    }

    private func loadFolders() async {
        guard let backend, let sourceID else { return }

        isLoading = true
        loadErrorMessage = nil
        do {
            let loaded = try await backend.folders(in: sourceID)
            guard !Task.isCancelled else { return }
            folders = loaded
        } catch {
            guard !Task.isCancelled else { return }
            let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            loadErrorMessage = message.isEmpty ? String(localized: "Unknown error", bundle: .module) : message
        }
        isLoading = false
    }
}

struct FolderSyncRow: Identifiable {
    let folder: Folder
    let depth: Int
    var id: Folder.ID { folder.id }
}

enum FolderSyncRows {
    static func make(_ folders: [Folder]) -> [FolderSyncRow] {
        let ids = Set(folders.map(\.id))
        let children = Dictionary(grouping: folders, by: { $0.parentID ?? "" })
        let roots = folders.filter { $0.parentID == nil || !ids.contains($0.parentID!) }
        var seen = Set<Folder.ID>()
        var result: [FolderSyncRow] = []
        for root in roots + folders {
            var pending: [(Folder, Int)] = [(root, 0)]
            while let (folder, depth) = pending.popLast() {
                guard seen.insert(folder.id).inserted else { continue }
                result.append(FolderSyncRow(folder: folder, depth: depth))
                for child in (children[folder.id] ?? []).reversed() {
                    pending.append((child, depth + 1))
                }
            }
        }
        return result
    }
}
