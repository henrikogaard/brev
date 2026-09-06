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

    private enum ScheduleReviewAction {
        case change(PendingScheduledSend), cancel(PendingScheduledSend)
    }

    private let backend: any MailBackend
    private let onClose: (() -> Void)?

    public init(backend: any MailBackend, onClose: (() -> Void)? = nil) {
        self.backend = backend
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
                    ToolbarItem(placement: .automatic) {
                        Button(String(localized: "Refresh", bundle: .module)) { Task { await loadMutations() } }
                            .disabled(isRetrying)
                    }
                    #if os(iOS)
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Close", bundle: .module)) { onClose?() }
                    }
                    if !mutations.isEmpty {
                        ToolbarItem(placement: .primaryAction) {
                            retryButton
                        }
                    }
                    #else
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
        .task {
            await loadMutations()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                await loadMutations()
            }
        }
        .sheet(item: $changingSchedule) { entry in
            ScheduleSendSheet(initiallyScheduledDate: entry.scheduledFor) { date in
                changingSchedule = nil
                Task { await changeSchedule(entry, to: date ?? Date()) }
            }
            .brevTheme(theme)
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
        VStack(spacing: BrevSpacing.md) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(theme.textTertiary.color)
            Text("No Pending Changes", bundle: .module)
                .brevFont(.headline)
                .foregroundStyle(theme.textPrimary.color)
            Text("Scheduled messages and changes waiting to sync appear here.", bundle: .module)
                .brevFont(.subheadline)
                .foregroundStyle(theme.textSecondary.color)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrevSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mutationList: some View {
        List {
            Section {
                Text(backend.account.emailAddress).brevFont(.caption).foregroundStyle(theme.textSecondary.color)
            }
            if let retryError {
                Section {
                    Text(retryError)
                        .brevFont(.footnote)
                        .foregroundStyle(theme.danger.color)
                }
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
            } }
        }
    }

    private func mutationRow(_ mutation: PendingMutation) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
            Text(mutation.kind.operationDescription)
                .brevFont(.subheadline)
                .foregroundStyle(theme.textPrimary.color)
            if !mutation.messageIDs.isEmpty {
                let noun = mutation.messageIDs.count == 1 ? "message" : "messages"
                Text(verbatim: "\(mutation.messageIDs.count) \(noun)")
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
        let values = await backend.extensionService(OutboxManaging.self)?.pendingMutations() ?? []
        guard !Task.isCancelled else { return }
        mutations = values
        scheduled = backend.extensionService(ScheduledSendManaging.self)?.pendingScheduledSends() ?? []
    }

    private func changeSchedule(_ entry: PendingScheduledSend, to date: Date) async {
        guard !isRetrying, let editor = backend.extensionService(ScheduledSendEditing.self) else { return }
        isRetrying = true
        retryError = nil
        defer { isRetrying = false }
        do {
            if entry.state == .needsReview {
                try await editor.retryReviewedScheduledSend(id: entry.id, for: date)
            } else {
                try await editor.rescheduleSend(id: entry.id, for: date)
            }
            if date <= Date() { await editor.deliverDueScheduledSends() }
        } catch { retryError = error.localizedDescription }
        await loadMutations()
    }

    private func cancelSchedule(_ entry: PendingScheduledSend) async {
        guard !isRetrying, let editor = backend.extensionService(ScheduledSendEditing.self) else { return }
        isRetrying = true
        retryError = nil
        defer { isRetrying = false }
        do {
            _ = try await editor.cancelScheduledSend(id: entry.id)
        } catch {
            retryError = error.localizedDescription
        }
        await loadMutations()
    }

    private func retryAll() async {
        isRetrying = true
        retryError = nil
        await backend.replayOfflineMutations()
        await loadMutations()
        isRetrying = false
        if mutations.isEmpty && scheduled.isEmpty { onClose?() }
    }

    private func discard(_ mutation: PendingMutation) async {
        guard let manager = backend.extensionService(OutboxManaging.self) else { return }
        await manager.discardMutation(id: mutation.id)
        await loadMutations()
    }

    private func discardAll() async {
        guard let manager = backend.extensionService(OutboxManaging.self) else { return }
        await manager.discardAllMutations()
        mutations = []
        if scheduled.isEmpty { onClose?() }
    }
}
