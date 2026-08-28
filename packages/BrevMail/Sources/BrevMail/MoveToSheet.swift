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

/// Searchable "Move To…" folder chooser sheet.
///
/// Presents all available folders filtered by a search query. Tapping
/// a folder invokes `onMove` with the message IDs and selected folder,
/// then dismisses via `onClose`. The current folder is highlighted and
/// excluded from the moveable candidates.
public struct MoveToSheet: View {
    @Environment(\.brevTheme) private var theme
    @State private var searchText = ""
    @State private var isMoving = false
    @State private var moveError: String?
    @State private var recentFolderIDs: [Folder.ID]

    private let allFolders: [Folder]
    private let messageIDs: [String]
    private let title: String
    private let currentFolderID: Folder.ID?
    private let sourceID: MailSourceID?
    private let folderAliasPreferences: FolderAliasPreferences
    private let recentStore: MoveToRecentFolderStore
    private let onMove: ([String], Folder) async throws -> Void
    private let onClose: (() -> Void)?

    public init(
        allFolders: [Folder],
        messageIDs: [String],
        title: String? = nil,
        currentFolderID: Folder.ID? = nil,
        sourceID: MailSourceID? = nil,
        folderAliasPreferences: FolderAliasPreferences = .defaults,
        recentStore: MoveToRecentFolderStore = MoveToRecentFolderStore(),
        onMove: @escaping ([String], Folder) async throws -> Void,
        onClose: (() -> Void)? = nil
    ) {
        self.allFolders = allFolders
        self.messageIDs = messageIDs
        self.title = title ?? String(localized: "Move To", bundle: .module)
        self.currentFolderID = currentFolderID
        self.sourceID = sourceID
        self.folderAliasPreferences = folderAliasPreferences
        self.recentStore = recentStore
        self.onMove = onMove
        self.onClose = onClose
        _recentFolderIDs = State(initialValue: sourceID.map { recentStore.recentFolderIDs(for: $0) } ?? [])
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            BrevDivider()
            searchField
            BrevDivider()
            folderList
            if let moveError {
                errorFooter(moveError)
            }
        }
        .frame(minWidth: 320, idealWidth: 380)
        .background(theme.bgPrimary.color)
    }

    // MARK: - Sub-views

    private var header: some View {
        HStack {
            Text(verbatim: title)
                .brevFont(.headline)
                .foregroundStyle(theme.textPrimary.color)
            Spacer()
            Button {
                onClose?()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(theme.textTertiary.color)
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.sm)
    }

    private var searchField: some View {
        HStack(spacing: BrevSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.textTertiary.color)
                .font(.system(size: 14))
            TextField(String(localized: "Search folders", bundle: .module), text: $searchText)
                .brevFont(.body)
                .foregroundStyle(theme.textPrimary.color)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.textTertiary.color)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.sm)
    }

    private var folderList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                let candidates = filteredFolders
                if candidates.isEmpty {
                    emptyState
                } else {
                    ForEach(candidates) { folder in
                        folderRow(folder)
                        if folder.id != candidates.last?.id {
                            BrevDivider()
                                .padding(.horizontal, BrevSpacing.md)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 400)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: BrevSpacing.xs) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 28))
                .foregroundStyle(theme.textTertiary.color)
            Text(
                searchText.isEmpty
                    ? String(localized: "No folders available", bundle: .module)
                    : String(localized: "No matching folders", bundle: .module)
            )
            .brevFont(.subheadline)
            .foregroundStyle(theme.textSecondary.color)
        }
        .padding(.vertical, BrevSpacing.lg)
        .frame(maxWidth: .infinity)
    }

    private func folderRow(_ folder: Folder) -> some View {
        let isCurrent = folder.id == currentFolderID
        let title = displayName(for: folder)
        return Button {
            guard !isCurrent, !isMoving else { return }
            Task { await performMove(to: folder) }
        } label: {
            HStack(spacing: BrevSpacing.sm) {
                Image(systemName: systemImage(for: folder.role))
                    .foregroundStyle(isCurrent ? theme.accent.color : theme.textSecondary.color)
                    .frame(width: 20, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .brevFont(.subheadline)
                        .foregroundStyle(isCurrent ? theme.accent.color : theme.textPrimary.color)
                        .lineLimit(1)
                }
                Spacer(minLength: BrevSpacing.xs)
                if isCurrent {
                    Text("Current", bundle: .module)
                        .brevFont(.caption)
                        .foregroundStyle(theme.textTertiary.color)
                } else if folder.unreadCount > 0 {
                    Text(verbatim: "\(folder.unreadCount)")
                        .brevFont(.caption)
                        .foregroundStyle(theme.textSecondary.color)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, BrevSpacing.md)
            .padding(.vertical, BrevSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isCurrent || isMoving)
        .opacity(isCurrent ? 0.5 : 1)
    }

    @ViewBuilder
    private func errorFooter(_ message: String) -> some View {
        BrevDivider()
        HStack(spacing: BrevSpacing.xs) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(theme.danger.color)
                .font(.system(size: 13))
            Text(verbatim: message)
                .brevFont(.caption)
                .foregroundStyle(theme.danger.color)
                .lineLimit(2)
        }
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.sm)
    }

    // MARK: - Helpers

    private var filteredFolders: [Folder] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let candidates = MoveToRecentFolderStore.sortedMoveCandidates(
            from: allFolders,
            currentFolderID: currentFolderID,
            recentFolderIDs: recentFolderIDs
        )
        guard !query.isEmpty else { return candidates }
        return candidates.filter { folder in
            displayName(for: folder).lowercased().contains(query)
                || folder.name.lowercased().contains(query)
        }
    }

    private func displayName(for folder: Folder) -> String {
        FolderAliasPreferencesPolicy.displayName(
            for: folder,
            sourceID: sourceID,
            preferences: folderAliasPreferences
        )
    }

    private func performMove(to folder: Folder) async {
        isMoving = true
        moveError = nil
        do {
            try await onMove(messageIDs, folder)
            if let sourceID {
                recentStore.record(folderID: folder.id, sourceID: sourceID)
                recentFolderIDs = recentStore.recentFolderIDs(for: sourceID)
            }
            onClose?()
        } catch {
            moveError = error.localizedDescription
        }
        isMoving = false
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
