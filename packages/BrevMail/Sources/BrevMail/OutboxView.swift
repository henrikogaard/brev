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

/// Sheet showing submitted schedules and offline changes for one account.
///
/// Lets the user retry all pending changes at once or discard individual ones.
/// Backed by `OutboxManaging`; if the backend does not conform the sheet shows
/// an empty state.
public struct OutboxView: View {
    @Environment(\.brevTheme) private var theme
    @State private var mutations: [PendingMutation] = []
    @State private var isRetrying = false
    @State private var retryError: String?
    @State private var scheduled: [PendingScheduledSend] = []
    @State private var changingSchedule: PendingScheduledSend?
    @State private var reviewAction: ScheduleReviewAction?
    @State private var contextGeneration = 0
    @State private var activeSourceID: MailSourceID?
    @State private var activeBackendIdentity: ObjectIdentifier?

    private enum ScheduleReviewAction {
        case change(PendingScheduledSend), cancel(PendingScheduledSend)
    }

    private let backend: any MailBackend
    private let sourceID: MailSourceID?
    private let onClose: (() -> Void)?

    /// Creates the account's Outbox, filtering source-owned schedules to the effective mailbox.
    /// - Parameters:
    ///   - backend: Backend providing pending mutations and schedules.
    ///   - sourceID: Selected mailbox owner; nil keeps legacy unowned schedules only.
    ///   - onClose: Optional dismissal action for the containing sheet.
    public init(backend: any MailBackend, sourceID: MailSourceID? = nil, onClose: (() -> Void)? = nil) {
        self.backend = backend
        self.sourceID = sourceID
        _activeSourceID = State(initialValue: sourceID)
        _activeBackendIdentity = State(initialValue: ObjectIdentifier(backend))
        self.onClose = onClose
    }

    public var body: some View {
        NavigationStack {
            Group {
                if mutations.isEmpty && scheduled.isEmpty && retryError == nil {
                    emptyState
                } else {
                    mutationList
                }
            }
            .navigationTitle(String(localized: "Outbox", bundle: .module))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    #if os(iOS)
                    // Done closes the sheet; retry sits in the bottom bar and
                    // the list refreshes itself, so the nav bar carries one
                    // button.
                    ToolbarItem(placement: .confirmationAction) {
                        Button { onClose?() } label: { Text("Done", bundle: .module) }
                    }
                    if !mutations.isEmpty {
                        ToolbarItem(placement: .bottomBar) {
                            retryButton
                        }
                    }
                    #else
                    ToolbarItem(placement: .automatic) {
                        Button(String(localized: "Refresh", bundle: .module)) { Task { await loadMutations() } }
                            .disabled(isRetrying)
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Close", bundle: .module)) { onClose?() }
                    }
                    if !mutations.isEmpty {
                        ToolbarItem(placement: .primaryAction) {
                            retryButton
                        }
                    }
                    #endif
                }
        }
        .task(id: loadIdentity) {
            contextGeneration += 1
            activeSourceID = sourceID
            activeBackendIdentity = ObjectIdentifier(backend)
            let generation = contextGeneration
            await loadMutations(generation: generation)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                await loadMutations(generation: generation)
            }
        }
        .sheet(item: $changingSchedule) { entry in
            ScheduleSendSheet(initiallyScheduledDate: entry.scheduledFor) { date in
                changingSchedule = nil
                Task { await changeSchedule(entry, to: date ?? Date()) }
            }
            .brevSheetAppearance(theme)
        }
        .confirmationDialog(String(localized: "Review scheduled message", bundle: .module), isPresented: Binding(
            get: { reviewAction != nil }, set: { if !$0 { reviewAction = nil } }
        ), presenting: reviewAction) { action in
            switch action {
            case .change(let entry):
                Button(String(localized: "Choose send time…", bundle: .module)) { changingSchedule = entry; reviewAction = nil }
            case .cancel(let entry):
                Button(String(localized: "Remove schedule", bundle: .module)) {
                    reviewAction = nil
                    Task { await cancelSchedule(entry) }
                }
            }
        } message: { _ in
            Text(
                "If the previous delivery was uncertain, check Sent before retrying to avoid a duplicate. Removing a schedule does not recall delivered mail.",
                bundle: .module
            )
        }
    }

    private var emptyState: some View {
        MessageListEmptyStateView(
            status: MessageListStatus(
                title: String(localized: "No Pending Changes", bundle: .module),
                icon: "checkmark.circle",
                subtitle: String(
                    localized: "Scheduled messages and changes waiting to sync appear here.",
                    bundle: .module
                ),
                actionTitle: nil
            )
        )
    }

    private var mutationList: some View {
        List {
            Section {
                Text(backend.account.emailAddress).brevFont(.caption).foregroundStyle(theme.textSecondary.color)
            }
            .brevSheetRow()
            if let retryError {
                Section {
                    Text(retryError)
                        .brevFont(.footnote)
                        .foregroundStyle(theme.danger.color)
                }
                .brevSheetRow()
            }
            if !scheduled.isEmpty {
                Section(String(localized: "Scheduled", bundle: .module)) {
                    ForEach(scheduled) { entry in
                        ScheduledOutboxRow(entry: entry, isBusy: isRetrying,
                                           canEdit: backend.extensionService(ScheduledSendEditing.self) != nil,
                                           onChange: {
                                               if entry.state == .needsReview {
                                                   reviewAction = .change(entry)
                                               } else {
                                                   changingSchedule = entry
                                               }
                                           }, onCancel: {
                                               if entry.state == .needsReview {
                                                   reviewAction = .cancel(entry)
                                               } else {
                                                   Task { await cancelSchedule(entry) }
                                               }
                                           })
                    }
                }
                .brevSheetRow()
            }
            ForEach(mutations) { mutation in
                mutationRow(mutation)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { await discard(mutation) }
                        } label: {
                            Label(String(localized: "Discard", bundle: .module), systemImage: "trash")
                        }
                    }
                    .brevSheetRow()
            }
            if !mutations.isEmpty { Section {
                Button(role: .destructive) {
                    Task { await discardAll() }
                } label: {
                    HStack {
                        Spacer()
                        Text("Discard All Pending Changes", bundle: .module)
                            .brevFont(.subheadline)
                        Spacer()
                    }
                }
                .brevSheetRow()
            } }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .refreshable { await loadMutations() }
    }

    private func mutationRow(_ mutation: PendingMutation) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
            Text(mutation.kind.operationDescription)
                .brevFont(.subheadline)
                .foregroundStyle(theme.textPrimary.color)
            if !mutation.messageIDs.isEmpty {
                Text(
                    mutation.messageIDs.count == 1
                        ? String(localized: "1 message", bundle: .module)
                        : String(localized: "\(mutation.messageIDs.count) messages", bundle: .module)
                )
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
            }
            Text(mutation.createdAt, style: .relative)
                .brevFont(.caption)
                .foregroundStyle(theme.textTertiary.color)
        }
        .padding(.vertical, BrevSpacing.xxs)
    }

    private var retryButton: some View {
        Button {
            Task { await retryAll() }
        } label: {
            if isRetrying {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text("Retry sync changes", bundle: .module)
            }
        }
        .disabled(isRetrying)
    }

    private func loadMutations() async {
        await loadMutations(generation: contextGeneration)
    }

    private var loadIdentity: String {
        let selected = sourceID.map { "\($0.accountID):\($0.mailboxID)" } ?? "active"
        return "\(ObjectIdentifier(backend).hashValue):\(selected)"
    }

    private func effectiveSourceID() async -> MailSourceID? {
        let candidate: MailSourceID?
        if let activeSourceID {
            candidate = activeSourceID
        } else if let mailbox = try? await backend.currentMailbox() {
            candidate = backend.sourceID(for: mailbox)
        } else {
            candidate = nil
        }
        guard let candidate, candidate.accountID == backend.account.id,
              let mailboxes = try? await backend.mailboxes(),
              mailboxes.contains(where: { $0.id == candidate.mailboxID }) else { return nil }
        return candidate
    }

    private func isCurrentContext(generation: Int, sourceID expectedSourceID: MailSourceID?) async -> Bool {
        guard !Task.isCancelled,
              generation == contextGeneration,
              activeBackendIdentity == ObjectIdentifier(backend) else { return false }
        return await effectiveSourceID() == expectedSourceID
    }

    private func loadMutations(generation: Int) async {
        let owner = backend
        let requestedSourceID = await effectiveSourceID()
        let values = await owner.extensionService(OutboxManaging.self)?.pendingMutations() ?? []
        let scheduledValues = owner.extensionService(ScheduledSendManaging.self)?.pendingScheduledSends() ?? []
        guard await isCurrentContext(generation: generation, sourceID: requestedSourceID),
              ObjectIdentifier(owner) == ObjectIdentifier(backend) else { return }
        let currentSourceID = await effectiveSourceID()
        guard await isCurrentContext(generation: generation, sourceID: currentSourceID) else { return }
        mutations = values
        scheduled = ScheduledOutboxSourcePolicy.visibleEntries(
            scheduledValues,
            selectedSourceID: currentSourceID
        )
    }

    private func changeSchedule(_ entry: PendingScheduledSend, to date: Date) async {
        let generation = contextGeneration
        let selectedSourceID = await effectiveSourceID()
        guard await isCurrentContext(generation: generation, sourceID: selectedSourceID),
              ScheduledOutboxSourcePolicy.visibleEntries([entry], selectedSourceID: selectedSourceID)
              .contains(where: { $0.id == entry.id }) else { return }
        guard !isRetrying, let editor = backend.extensionService(ScheduledSendEditing.self) else { return }
        isRetrying = true
        retryError = nil
        defer { isRetrying = false }
        var actionError: String?
        do {
            if entry.state == .needsReview {
                try await editor.retryReviewedScheduledSend(id: entry.id, for: date)
            } else {
                try await editor.rescheduleSend(id: entry.id, for: date)
            }
            if date <= Date() { await editor.deliverDueScheduledSends() }
        } catch { actionError = error.localizedDescription }
        guard await isCurrentContext(generation: generation, sourceID: selectedSourceID) else { return }
        retryError = actionError
        await loadMutations(generation: generation)
    }

    private func cancelSchedule(_ entry: PendingScheduledSend) async {
        let generation = contextGeneration
        let selectedSourceID = await effectiveSourceID()
        guard await isCurrentContext(generation: generation, sourceID: selectedSourceID),
              ScheduledOutboxSourcePolicy.visibleEntries([entry], selectedSourceID: selectedSourceID)
              .contains(where: { $0.id == entry.id }) else { return }
        guard !isRetrying, let editor = backend.extensionService(ScheduledSendEditing.self) else { return }
        isRetrying = true
        retryError = nil
        defer { isRetrying = false }
        var actionError: String?
        do {
            _ = try await editor.cancelScheduledSend(id: entry.id)
        } catch {
            actionError = error.localizedDescription
        }
        guard await isCurrentContext(generation: generation, sourceID: selectedSourceID) else { return }
        retryError = actionError
        await loadMutations(generation: generation)
    }

    private func retryAll() async {
        let owner = backend
        let generation = contextGeneration
        let selectedSourceID = await effectiveSourceID()
        guard await isCurrentContext(generation: generation, sourceID: selectedSourceID) else { return }
        isRetrying = true
        retryError = nil
        defer { isRetrying = false }
        await owner.replayOfflineMutations()
        guard await isCurrentContext(generation: generation, sourceID: selectedSourceID) else { return }
        await loadMutations(generation: generation)
        guard await isCurrentContext(generation: generation, sourceID: selectedSourceID) else { return }
        if mutations.isEmpty && scheduled.isEmpty { onClose?() }
    }

    private func discard(_ mutation: PendingMutation) async {
        let owner = backend
        let generation = contextGeneration
        let selectedSourceID = await effectiveSourceID()
        guard await isCurrentContext(generation: generation, sourceID: selectedSourceID),
              let manager = owner.extensionService(OutboxManaging.self) else { return }
        await manager.discardMutation(id: mutation.id)
        guard await isCurrentContext(generation: generation, sourceID: selectedSourceID) else { return }
        await loadMutations(generation: generation)
    }

    private func discardAll() async {
        let owner = backend
        let generation = contextGeneration
        let selectedSourceID = await effectiveSourceID()
        guard await isCurrentContext(generation: generation, sourceID: selectedSourceID),
              let manager = owner.extensionService(OutboxManaging.self) else { return }
        await manager.discardAllMutations()
        guard await isCurrentContext(generation: generation, sourceID: selectedSourceID) else { return }
        await loadMutations(generation: generation)
        if scheduled.isEmpty { onClose?() }
    }
}
