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

    private let folders: [Folder]
    private let sourceID: MailSourceID?
    private let settingsStore: SettingsPersistenceStore
    private let emptyFolderMessage: String
    private let onPolicyChanged: ((Folder) -> Void)?
    private let onVisibilityChanged: ((Folder) -> Void)?

    public init(
        folders: [Folder],
        sourceID: MailSourceID? = nil,
        settings: AccountMailboxSyncSettings,
        settingsStore: SettingsPersistenceStore = .standard,
        emptyFolderMessage: String? = nil,
        onPolicyChanged: ((Folder) -> Void)? = nil,
        onVisibilityChanged: ((Folder) -> Void)? = nil
    ) {
        self.folders = folders
        self.sourceID = sourceID
        self.settingsStore = settingsStore
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
            subtitle: String(localized: "Override the account's cache and visibility settings per folder.", bundle: .module)
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.xl) {
                folderOverridesGroup
            }
        }
    }

    private var folderOverridesGroup: some View {
        SettingsGroup(
            title: String(localized: "Per-folder overrides", bundle: .module),
            subtitle: String(localized: "Fine-tune caching and sync for each folder.", bundle: .module),
            symbolName: "folder.badge.gearshape"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                if folders.isEmpty {
                    SettingsInfoCallout(
                        symbolName: "folder.badge.questionmark",
                        message: emptyFolderMessage,
                        tone: .info
                    )
                } else {
                    ForEach(folders) { folder in
                        folderRow(folder)
                    }
                }
            }
        }
    }

    private func folderRow(_ folder: Folder) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            HStack(alignment: .center, spacing: BrevSpacing.md) {
                Image(systemName: folderIcon(for: folder.role))
                    .foregroundStyle(theme.textSecondary.color)
                    .frame(width: 18, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name)
                        .brevFont(.body)
                        .foregroundStyle(theme.textPrimary.color)
                    Text("Unread: \(folder.unreadCount)", bundle: .module)
                        .brevFont(.caption)
                        .foregroundStyle(theme.textTertiary.color)
                }

                Spacer(minLength: BrevSpacing.md)
            }

            HStack(alignment: .center, spacing: BrevSpacing.md) {
                Text("Retention", bundle: .module)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textTertiary.color)
                    .frame(width: 80, alignment: .leading)

                Picker(String(localized: "Retention", bundle: .module), selection: retentionBinding(for: folder)) {
                    Text("Default", bundle: .module).tag(OfflineRetentionPolicy?.none)
                    ForEach(OfflineRetentionPolicy.allCases) { policy in
                        Text(policy.displayName).tag(Optional(policy))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if sourceID != nil {
                SettingsToggleRow(
                    symbolName: "sidebar.left",
                    title: String(localized: "Show in mailbox list", bundle: .module),
                    subtitle: String(
                        localized: "Hide this folder from mailbox navigation without changing sync.",
                        bundle: .module
                    ),
                    isOn: mailboxListVisibilityBinding(for: folder)
                )
            }
        }
        .padding(BrevSpacing.md)
        .background(theme.bgSecondary.color.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: BrevRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: BrevRadius.md)
                .stroke(theme.border.color.opacity(0.45), lineWidth: 1)
        }
    }

    private func retentionBinding(for folder: Folder) -> Binding<OfflineRetentionPolicy?> {
        Binding(
            get: { settings.folderOverrides[folder.id]?.retentionPolicy },
            set: { newValue in
                settings.setRetentionPolicy(newValue, forFolderID: folder.id)
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
                    in: visibilityPreferences
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

    private let backend: (any MailBackend)?
    private let settingsStore: SettingsPersistenceStore

    init(
        folders: [Folder],
        sourceID: MailSourceID?,
        backend: (any MailBackend)?,
        settingsStore: SettingsPersistenceStore
    ) {
        self.backend = backend
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
                emptyFolderMessage: emptyFolderMessage
            )

            if shouldShowLoadButton {
                BrevButton(
                    isLoading ? String(localized: "Loading...", bundle: .module) : String(
                        localized: "Load Folders",
                        bundle: .module
                    ),
                    style: .secondary
                ) {
                    Task { await loadFolders() }
                }
                .disabled(isLoading)
            }
        }
    }

    private var shouldShowLoadButton: Bool {
        backend != nil && (folders.isEmpty || sourceID == nil)
    }

    private var emptyFolderMessage: String {
        if isLoading {
            return String(localized: "Loading folders for the current mailbox…", bundle: .module)
        }
        if let loadErrorMessage {
            return String(localized: "Couldn't load folders: \(loadErrorMessage)", bundle: .module)
        }
        if backend != nil {
            return String(localized: "Load folders for the current mailbox to configure per-folder sync.", bundle: .module)
        }
        return String(localized: "No folders available. Open a mailbox to configure per-folder sync.", bundle: .module)
    }

    private func loadFolders() async {
        guard let backend else { return }

        isLoading = true
        loadErrorMessage = nil
        do {
            let mailbox = try await backend.currentMailbox()
            let resolvedSourceID = backend.sourceID(for: mailbox)
            folders = try await backend.folders(in: resolvedSourceID)
            sourceID = resolvedSourceID
        } catch {
            let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            loadErrorMessage = message.isEmpty ? String(localized: "Unknown error", bundle: .module) : message
        }
        isLoading = false
    }
}
