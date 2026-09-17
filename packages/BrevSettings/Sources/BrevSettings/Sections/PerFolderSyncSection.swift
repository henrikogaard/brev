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
            VStack(alignment: .leading, spacing: BrevSpacing.xl) {
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
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
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
                    VStack(alignment: .leading, spacing: BrevSpacing.md) {
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

    private var folderOverridesGroup: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            HStack {
                TextField(String(localized: "Filter folders", bundle: .module), text: $filter)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(String(localized: "Filter folders", bundle: .module))
                if let onReload {
                    Button(action: onReload) {
                        Label(String(localized: "Refresh", bundle: .module), systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            if isLoading { ProgressView().controlSize(.small) }
            if folders.isEmpty {
                Text(emptyFolderMessage)
                    .brevFont(.body)
                    .foregroundStyle(theme.textSecondary.color)
                    .padding(.vertical, BrevSpacing.lg)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: BrevSpacing.sm) {
                        Text("Folder", bundle: .module).frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
                        Text("Keep offline", bundle: .module).frame(width: 132, alignment: .leading)
                        Text("Show", bundle: .module).frame(width: 44)
                    }
                    HStack {
                        Text("Folder", bundle: .module)
                        Spacer()
                        Text("Show", bundle: .module).frame(width: 44)
                    }
                }
                .brevFont(.footnote)
                .foregroundStyle(theme.textSecondary.color)
                .padding(.horizontal, BrevSpacing.sm)
                LazyVStack(spacing: 0) {
                    ForEach(visibleRows) { row in
                        folderRow(row)
                        Rectangle().fill(theme.separator.color).frame(height: 1)
                    }
                }
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

    private var visibleRows: [FolderSyncRow] {
        let rows = FolderSyncRows.make(folders)
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? rows : rows.filter { $0.folder.name.localizedStandardContains(query) }
    }

    private func folderRow(_ row: FolderSyncRow) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: BrevSpacing.sm) {
                folderIdentity(row).frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
                retentionPicker(row.folder)
                visibilityToggle(row.folder).frame(width: 44)
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
                visibilityToggle(row.folder).frame(width: 44)
            }
        }
        .frame(minHeight: 40)
        .padding(.horizontal, BrevSpacing.sm)
        .padding(.vertical, BrevSpacing.xxs)
        .background(theme.bgPrimary.color)
    }

    private func folderIdentity(_ row: FolderSyncRow) -> some View {
        HStack(spacing: BrevSpacing.sm) {
            Image(systemName: folderIcon(for: row.folder.role))
                .foregroundStyle(theme.textSecondary.color)
                .frame(width: 18)
            Text(row.folder.name)
                .brevFont(.body)
                .foregroundStyle(theme.textPrimary.color)
                .lineLimit(2)
                .help(row.folder.name)
        }
        .padding(.leading, CGFloat(min(row.depth, 6)) * 14)
    }

    private func retentionPicker(_ folder: Folder) -> some View {
        Picker(String(localized: "Offline retention for \(folder.name)", bundle: .module),
               selection: retentionBinding(for: folder)) {
            Text("Default", bundle: .module).tag(OfflineRetentionPolicy?.none)
            ForEach(OfflineRetentionPolicy.allCases) { policy in
                Text(policy.displayName).tag(Optional(policy))
            }
        }
        .labelsHidden()
        .frame(width: 132)
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
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.md) {
            PerFolderSyncSection(
                folders: folders,
                sourceID: sourceID,
                settings: settingsStore.accountMailboxSyncSettings(),
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
