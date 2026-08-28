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

/// Sheet showing pending offline mutations queued while the device was offline.
///
/// Lets the user retry all pending changes at once or discard individual ones.
/// Backed by `OutboxManaging`; if the backend does not conform the sheet shows
/// an empty state.
public struct OutboxView: View {
    @Environment(\.brevTheme) private var theme
    @State private var mutations: [PendingMutation] = []
    @State private var isRetrying = false
    @State private var retryError: String?

    private let backend: any MailBackend
    private let onClose: (() -> Void)?

    public init(backend: any MailBackend, onClose: (() -> Void)? = nil) {
        self.backend = backend
        self.onClose = onClose
    }

    public var body: some View {
        NavigationStack {
            Group {
                if mutations.isEmpty {
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
        .task { await loadMutations() }
    }

    private var emptyState: some View {
        VStack(spacing: BrevSpacing.md) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(theme.textTertiary.color)
            Text("No Pending Changes", bundle: .module)
                .brevFont(.headline)
                .foregroundStyle(theme.textPrimary.color)
            Text("Changes you make while offline will appear here and sync automatically when you reconnect.", bundle: .module)
                .brevFont(.subheadline)
                .foregroundStyle(theme.textSecondary.color)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrevSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mutationList: some View {
        List {
            if let retryError {
                Section {
                    Text(retryError)
                        .brevFont(.footnote)
                        .foregroundStyle(theme.danger.color)
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
            Section {
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
            }
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
                Text("Retry All", bundle: .module)
            }
        }
        .disabled(isRetrying)
    }

    private func loadMutations() async {
        guard let manager = backend.extensionService(OutboxManaging.self) else { return }
        mutations = await manager.pendingMutations()
    }

    private func retryAll() async {
        isRetrying = true
        retryError = nil
        await backend.replayOfflineMutations()
        await loadMutations()
        isRetrying = false
        if mutations.isEmpty { onClose?() }
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
        onClose?()
    }
}
