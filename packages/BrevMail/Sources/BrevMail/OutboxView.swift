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
    @State private var contextTransition = ScheduledOutboxContextTransition()
    @State private var loadedContext: ScheduledOutboxContext?
    @State private var loadedGeneration = -1

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
        self.onClose = onClose
    }

    public var body: some View {
        NavigationStack {
            Group {
                if !isLoadedForCurrentContext {
                    ProgressView()
                } else if visibleMutations.isEmpty && visibleScheduled.isEmpty && retryError == nil {
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
                    if !visibleMutations.isEmpty {
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
                    if !visibleMutations.isEmpty {
                        ToolbarItem(placement: .primaryAction) {
                            retryButton
                        }
                    }
                    #endif
                }
        }
        .onChange(of: requestedContext) { _, _ in
            _ = transitionContext(to: requestedContext)
        }
        .task(id: requestedContext) {
            let context = requestedContext
            let generation = transitionContext(to: context)
            await loadMutations(context: context, generation: generation)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                await loadMutations(context: context, generation: generation)
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
            if let retryError, isLoadedForCurrentContext {
                Section {
                    Text(retryError)
                        .brevFont(.footnote)
                        .foregroundStyle(theme.danger.color)
                }
                .brevSheetRow()
            }
            if !visibleScheduled.isEmpty {
                Section(String(localized: "Scheduled", bundle: .module)) {
                    ForEach(visibleScheduled) { entry in
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
            ForEach(visibleMutations) { mutation in
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
            if !visibleMutations.isEmpty { Section {
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
        .refreshable { await loadMutations(context: requestedContext, generation: contextGeneration) }
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
        .disabled(isRetrying || !isLoadedForCurrentContext)
    }

    private func loadMutations() async {
        await loadMutations(context: requestedContext, generation: contextGeneration)
    }

    private var requestedContext: ScheduledOutboxContext {
        ScheduledOutboxContext(backendID: ObjectIdentifier(backend), sourceID: sourceID)
    }

    private var contextGeneration: Int {
        contextTransition.generation
    }

    private func transitionContext(to context: ScheduledOutboxContext) -> Int {
        var transition = contextTransition
        guard transition.transition(to: context) else { return transition.generation }
        contextTransition = transition
        clearLoadedContext()
        return transition.generation
    }

    private var isLoadedForCurrentContext: Bool {
        ScheduledOutboxSourcePolicy.isLoaded(
            loaded: loadedContext,
            requested: requestedContext,
            loadedGeneration: loadedGeneration,
            currentGeneration: contextGeneration
        )
    }

    private var visibleMutations: [PendingMutation] {
        isLoadedForCurrentContext ? mutations : []
    }

    private var visibleScheduled: [PendingScheduledSend] {
        isLoadedForCurrentContext ? scheduled : []
    }

    private func isCurrentContext(_ context: ScheduledOutboxContext, generation: Int) -> Bool {
        ScheduledOutboxSourcePolicy.isCurrent(
            requested: context,
            current: requestedContext,
            generation: generation,
            currentGeneration: contextGeneration,
            isCancelled: Task.isCancelled
        )
    }

    private func clearLoadedContext() {
        loadedContext = nil
        loadedGeneration = -1
        mutations = []
        scheduled = []
        retryError = nil
        changingSchedule = nil
        reviewAction = nil
        isRetrying = false
    }

    private func loadMutations(context: ScheduledOutboxContext, generation: Int) async {
        let owner = backend
        guard isCurrentContext(context, generation: generation) else { return }
        let values = await owner.extensionService(OutboxManaging.self)?.pendingMutations() ?? []
        guard isCurrentContext(context, generation: generation) else { return }
        let scheduledValues = owner.extensionService(ScheduledSendManaging.self)?.pendingScheduledSends() ?? []
        guard isCurrentContext(context, generation: generation),
              ObjectIdentifier(owner) == context.backendID else { return }
        mutations = values
        scheduled = ScheduledOutboxSourcePolicy.visibleEntries(
            scheduledValues,
            selectedSourceID: context.sourceID
        )
        loadedContext = context
        loadedGeneration = generation
    }

    private func changeSchedule(_ entry: PendingScheduledSend, to date: Date) async {
        let context = requestedContext
        let generation = contextGeneration
        guard isLoadedForCurrentContext,
              isCurrentContext(context, generation: generation),
              ScheduledOutboxSourcePolicy.visibleEntries([entry], selectedSourceID: context.sourceID)
              .contains(where: { $0.id == entry.id }) else { return }
        guard !isRetrying, let editor = backend.extensionService(ScheduledSendEditing.self) else { return }
        isRetrying = true
        retryError = nil
        defer { if generation == contextGeneration { isRetrying = false } }
        var actionError: String?
        do {
            if entry.state == .needsReview {
                try await editor.retryReviewedScheduledSend(id: entry.id, for: date)
            } else {
                try await editor.rescheduleSend(id: entry.id, for: date)
            }
            guard isCurrentContext(context, generation: generation) else { return }
            if date <= Date() {
                await editor.deliverDueScheduledSends()
                guard isCurrentContext(context, generation: generation) else { return }
            }
        } catch { actionError = error.localizedDescription }
        guard isCurrentContext(context, generation: generation) else { return }
        retryError = actionError
        await loadMutations(context: context, generation: generation)
    }

    private func cancelSchedule(_ entry: PendingScheduledSend) async {
        let context = requestedContext
        let generation = contextGeneration
        guard isLoadedForCurrentContext,
              isCurrentContext(context, generation: generation),
              ScheduledOutboxSourcePolicy.visibleEntries([entry], selectedSourceID: context.sourceID)
              .contains(where: { $0.id == entry.id }) else { return }
        guard !isRetrying, let editor = backend.extensionService(ScheduledSendEditing.self) else { return }
        isRetrying = true
        retryError = nil
        defer { if generation == contextGeneration { isRetrying = false } }
        var actionError: String?
        do {
            _ = try await editor.cancelScheduledSend(id: entry.id)
        } catch {
            actionError = error.localizedDescription
        }
        guard isCurrentContext(context, generation: generation) else { return }
        retryError = actionError
        await loadMutations(context: context, generation: generation)
    }

    private func retryAll() async {
        let owner = backend
        let context = requestedContext
        let generation = contextGeneration
        guard isLoadedForCurrentContext, isCurrentContext(context, generation: generation), !isRetrying else { return }
        isRetrying = true
        retryError = nil
        defer { if generation == contextGeneration { isRetrying = false } }
        await owner.replayOfflineMutations()
        guard isCurrentContext(context, generation: generation) else { return }
        await loadMutations(context: context, generation: generation)
        guard isCurrentContext(context, generation: generation) else { return }
        if visibleMutations.isEmpty && visibleScheduled.isEmpty { onClose?() }
    }

    private func discard(_ mutation: PendingMutation) async {
        let owner = backend
        let context = requestedContext
        let generation = contextGeneration
        guard isLoadedForCurrentContext, isCurrentContext(context, generation: generation),
              let manager = owner.extensionService(OutboxManaging.self) else { return }
        await manager.discardMutation(id: mutation.id)
        guard isCurrentContext(context, generation: generation) else { return }
        await loadMutations(context: context, generation: generation)
    }

    private func discardAll() async {
        let owner = backend
        let context = requestedContext
        let generation = contextGeneration
        guard isLoadedForCurrentContext, isCurrentContext(context, generation: generation),
              let manager = owner.extensionService(OutboxManaging.self) else { return }
        await manager.discardAllMutations()
        guard isCurrentContext(context, generation: generation) else { return }
        await loadMutations(context: context, generation: generation)
        guard isCurrentContext(context, generation: generation) else { return }
        if visibleScheduled.isEmpty { onClose?() }
    }
}
