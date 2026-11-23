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

import BrevAvatars
import BrevBackend
import BrevDesign
import BrevThemes
import SwiftUI

/// Locally discovered message carrying parsed `List-Unsubscribe` headers (#295).
struct SubscriptionsCandidate: Equatable, Sendable {
    let sourceID: MailSourceID
    let header: MessageHeader
    let listUnsubscribe: ListUnsubscribeOptions?
}

/// One newsletter/subscription sender row in the Subscriptions view (#295).
struct SubscriptionSenderGroup: Identifiable, Equatable, Sendable {
    let id: String
    let sourceID: MailSourceID
    let senderName: String
    let senderEmail: String
    let headers: [MessageHeader]
    let lastReceived: Date
    let unsubscribeOptions: ListUnsubscribeOptions

    var messageCount: Int { headers.count }

    /// Confirmation presentation describing the exact unsubscribe action before execution.
    var primaryUnsubscribeAction: MessageListUnsubscribeActionPresentation? {
        MessageListUnsubscribePresentation.resolve(options: unsubscribeOptions)?.actions.first
    }

    /// Plain-language explanation of what confirming Unsubscribe will do.
    var confirmationSummary: String? {
        guard let action = primaryUnsubscribeAction else { return nil }
        switch action.method {
        case .https(let url, _):
            let host = url.host ?? url.absoluteString
            // Brev opens HTTPS unsubscribe targets in the user's browser rather
            // than issuing an automatic background POST (ADR-0006).
            return String(
                format: String(
                    localized: "Brev will open %@ in your browser. The site may learn your IP address and request time.",
                    bundle: .module
                ),
                host
            )
        case .mailto(let url):
            let target = url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
            return String(
                format: String(
                    localized: "Brev will open an unsubscribe email draft addressed to %@. Nothing is sent until you press Send.",
                    bundle: .module
                ),
                target
            )
        }
    }
}

/// Builds the Subscriptions catalog strictly from locally cached headers and
/// cached `List-Unsubscribe` metadata — never fetches from the network (#295, ADR-0006).
enum SubscriptionsCatalogBuilder {
    static func build(candidates: [SubscriptionsCandidate]) -> [SubscriptionSenderGroup] {
        struct SenderKey: Hashable {
            let sourceID: MailSourceID
            let senderEmail: String
        }

        var grouped: [SenderKey: [SubscriptionsCandidate]] = [:]
        for candidate in candidates {
            guard let options = candidate.listUnsubscribe, !options.methods.isEmpty else { continue }
            let email = candidate.header.from.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !email.isEmpty else { continue }
            let key = SenderKey(sourceID: candidate.sourceID, senderEmail: email)
            grouped[key, default: []].append(candidate)
        }

        return grouped.compactMap { key, members in
            let sorted = members.sorted { lhs, rhs in
                if lhs.header.date != rhs.header.date { return lhs.header.date > rhs.header.date }
                return lhs.header.id < rhs.header.id
            }
            guard let newest = sorted.first, let options = newest.listUnsubscribe else { return nil }
            let displayName = newest.header.from.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedName = (displayName?.isEmpty == false ? displayName : nil) ?? newest.header.from.email
            return SubscriptionSenderGroup(
                id: "\(key.sourceID.accountID)|\(key.sourceID.mailboxID)|\(key.senderEmail)",
                sourceID: key.sourceID,
                senderName: resolvedName,
                senderEmail: newest.header.from.email,
                headers: sorted.map(\.header),
                lastReceived: newest.header.date,
                unsubscribeOptions: options
            )
        }
        .sorted { lhs, rhs in
            if lhs.lastReceived != rhs.lastReceived { return lhs.lastReceived > rhs.lastReceived }
            return lhs.senderName.localizedCaseInsensitiveCompare(rhs.senderName) == .orderedAscending
        }
    }
}

/// Reusable archive-all helper for Subscriptions with full `UndoQueue` support (#295).
enum SubscriptionsActions {
    /// Archives a single folder's subscription messages and registers undo.
    @MainActor
    @discardableResult
    static func archiveAll(
        headers: [MessageHeader],
        sourceID: MailSourceID,
        from sourceFolder: Folder,
        to archiveFolder: Folder,
        backend: any MailBackend,
        undoQueue: UndoQueue
    ) async -> Bool {
        let messageIDs = headers.map(\.id)
        guard !messageIDs.isEmpty else { return false }
        let lease = undoQueue.beginMutation()
        defer { undoQueue.endMutation(lease) }
        do {
            let receipt = try await backend.moveWithUndo(
                messageIDs: messageIDs,
                from: sourceFolder,
                to: archiveFolder,
                sourceID: sourceID
            )
            undoQueue.registerMoves(
                [receipt],
                description: String(localized: "Archived", bundle: .module),
                lease: lease
            )
            return true
        } catch {
            return false
        }
    }

    /// Archives every non-archived message in `group` across all source folders
    /// and registers one combined `UndoQueue` entry. Returns `true` only when
    /// every folder move succeeds without error (#295).
    @MainActor
    @discardableResult
    static func archiveAllMessages(
        in group: SubscriptionSenderGroup,
        folders: [Folder],
        backend: any MailBackend,
        undoQueue: UndoQueue
    ) async -> Bool {
        guard let archiveFolder = folders.first(where: { $0.role == .archive }) else {
            return false
        }
        let byFolder = Dictionary(grouping: group.headers, by: \.folderID)
            .filter { $0.key != archiveFolder.id }
            .sorted { $0.key < $1.key }
        guard !byFolder.isEmpty else { return true }

        var receipts: [MailMoveUndo?] = []
        var allSucceeded = true
        let lease = undoQueue.beginMutation()
        defer { undoQueue.endMutation(lease) }

        for (folderID, folderHeaders) in byFolder {
            let sourceFolder = folders.first { $0.id == folderID }
                ?? Folder(id: folderID, name: folderID, role: .custom)
            do {
                let receipt = try await backend.moveWithUndo(
                    messageIDs: folderHeaders.map(\.id),
                    from: sourceFolder,
                    to: archiveFolder,
                    sourceID: group.sourceID
                )
                receipts.append(receipt)
            } catch {
                allSucceeded = false
            }
        }

        // Preserve every folder's optional receipt so `MailMoveUndoRegistration`
        // suppresses partial Undo if any completed move lacks an Undo receipt.
        if !receipts.isEmpty {
            undoQueue.registerMoves(
                receipts,
                description: String(localized: "Archived", bundle: .module),
                lease: lease
            )
        }
        return allSucceeded
    }
}

/// Sidebar destination listing every locally detected newsletter/subscription
/// sender with confirmed Unsubscribe and undoable Archive all (#295).
struct SubscriptionsView: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 30

    let refreshKey: Int
    let load: () async -> [SubscriptionSenderGroup]
    let canArchive: (SubscriptionSenderGroup) -> Bool
    let onArchiveAll: (SubscriptionSenderGroup) async -> Bool
    let onConfirmedUnsubscribe: (SubscriptionSenderGroup, ListUnsubscribeMethod) -> Void
    let onSelectMessage: (MailSourceID, MessageHeader) -> Void

    @State private var groups: [SubscriptionSenderGroup] = []
    @State private var isLoading = false
    @State private var pendingConfirmationGroup: SubscriptionSenderGroup?
    @State private var archiveErrorGroupID: String?

    init(
        refreshKey: Int,
        load: @escaping () async -> [SubscriptionSenderGroup],
        canArchive: @escaping (SubscriptionSenderGroup) -> Bool,
        onArchiveAll: @escaping (SubscriptionSenderGroup) async -> Bool,
        onConfirmedUnsubscribe: @escaping (SubscriptionSenderGroup, ListUnsubscribeMethod) -> Void,
        onSelectMessage: @escaping (MailSourceID, MessageHeader) -> Void,
        preloaded: [SubscriptionSenderGroup]? = nil
    ) {
        self.refreshKey = refreshKey
        self.load = load
        self.canArchive = canArchive
        self.onArchiveAll = onArchiveAll
        self.onConfirmedUnsubscribe = onConfirmedUnsubscribe
        self.onSelectMessage = onSelectMessage
        _groups = State(initialValue: preloaded ?? [])
    }

    var body: some View {
        Group {
            if isLoading, groups.isEmpty {
                BrevSkeletonList(rowCount: 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groups.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(groups) { group in
                            row(for: group)
                                .padding(.horizontal, BrevSpacing.md)
                                .overlay(alignment: .bottom) {
                                    Rectangle()
                                        .fill(BrevSeparator.color(for: theme))
                                        .frame(height: 0.5)
                                }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(theme.bgPrimary.color)
        .task(id: refreshKey) {
            if groups.isEmpty { isLoading = true }
            let loaded = await load()
            guard !Task.isCancelled else { return }
            groups = loaded
            isLoading = false
        }
        .alert(
            pendingConfirmationGroup?.primaryUnsubscribeAction?.confirmationTitle
                ?? String(localized: "Unsubscribe", bundle: .module),
            isPresented: Binding(
                get: { pendingConfirmationGroup != nil },
                set: { if !$0 { pendingConfirmationGroup = nil } }
            )
        ) {
            if let group = pendingConfirmationGroup,
               let action = group.primaryUnsubscribeAction {
                Button(action.confirmButtonTitle, role: .destructive) {
                    pendingConfirmationGroup = nil
                    onConfirmedUnsubscribe(group, action.method)
                }
            }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) {
                pendingConfirmationGroup = nil
            }
        } message: {
            if let summary = pendingConfirmationGroup?.confirmationSummary {
                Text(verbatim: summary)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: BrevSpacing.sm) {
            Image(systemName: "newspaper")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(theme.textTertiary.color)
                .accessibilityHidden(true)
            Text("No subscriptions found", bundle: .module)
                .brevFont(.headline)
                .foregroundStyle(theme.textPrimary.color)
            Text("Newsletters with List-Unsubscribe headers appear here automatically from your cached mail.", bundle: .module)
                .brevFont(.callout)
                .foregroundStyle(theme.textSecondary.color)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding(BrevSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(for group: SubscriptionSenderGroup) -> some View {
        HStack(spacing: BrevSpacing.md) {
            Text(verbatim: InitialsAvatar.initials(displayName: group.senderName, email: group.senderEmail))
                .brevFont(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(theme.textSecondary.color)
                .frame(width: avatarSize, height: avatarSize)
                .background(Circle().fill(theme.bgTertiary.color))
                .accessibilityHidden(true)

            Button {
                if let latest = group.headers.first {
                    onSelectMessage(group.sourceID, latest)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: group.senderName)
                        .brevFont(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(theme.textPrimary.color)
                        .lineLimit(1)
                    Text(verbatim: subtitle(for: group))
                        .brevFont(.caption)
                        .foregroundStyle(theme.textSecondary.color)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: BrevSpacing.xs) {
                Button {
                    pendingConfirmationGroup = group
                } label: {
                    Text("Unsubscribe", bundle: .module)
                        .brevFont(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(group.primaryUnsubscribeAction == nil)

                if canArchive(group) {
                    Button {
                        Task {
                            archiveErrorGroupID = nil
                            let succeeded = await onArchiveAll(group)
                            if succeeded {
                                groups.removeAll { $0.id == group.id }
                            } else {
                                archiveErrorGroupID = group.id
                                let reloaded = await load()
                                guard !Task.isCancelled else { return }
                                groups = reloaded
                            }
                        }
                    } label: {
                        Text("Archive all", bundle: .module)
                            .brevFont(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, BrevSpacing.xs)
        .overlay(alignment: .bottomLeading) {
            if archiveErrorGroupID == group.id {
                Text("Couldn't archive all messages from this sender.", bundle: .module)
                    .brevFont(.caption)
                    .foregroundStyle(theme.danger.color)
            }
        }
    }

    private func subtitle(for group: SubscriptionSenderGroup) -> String {
        let countText = String(
            format: String(localized: "%lld messages", bundle: .module, locale: locale),
            locale: locale,
            Int64(group.messageCount)
        )
        let dateText = group.lastReceived.formatted(.dateTime.day().month(.abbreviated).locale(locale))
        return "\(countText) · \(dateText)"
    }
}
