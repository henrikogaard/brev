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

import BrevAI
import BrevDesign
import BrevThemes
import SwiftUI

/// Local open-weights model catalog and download manager group inside **Settings → AI Writer** (#304, Slice 2).
///
/// Network downloads start strictly when the user clicks Download; weights are verified by SHA-256,
/// stored in a backup-excluded Application Support directory, and run offline on-device.
struct LocalModelsSettingsGroup: View {
    @Environment(\.brevTheme) private var theme
    @State private var modelStates: [String: LocalModelDownloadState]
    @State private var totalInstalledBytes: Int64
    @State private var actionErrorMessage: String?

    private let catalog: [LocalModelDescriptor]
    private let downloadManager: LocalModelDownloadManager
    private let activeModelID: String?
    private let isPlatformSupported: Bool
    private let observeLiveUpdates: Bool
    private let onSelectModel: (LocalModelDescriptor) async -> Void
    private let onModelDeleted: (LocalModelDescriptor) async -> Void

    init(
        catalog: [LocalModelDescriptor] = LocalModelCatalog.curatedModels,
        downloadManager: LocalModelDownloadManager = .shared,
        activeModelID: String? = nil,
        isPlatformSupported: Bool = DefaultLocalModelInferenceRuntime.isPlatformSupported,
        initialStates: [String: LocalModelDownloadState]? = nil,
        initialTotalInstalledBytes: Int64? = nil,
        onSelectModel: @escaping (LocalModelDescriptor) async -> Void = { _ in },
        onModelDeleted: @escaping (LocalModelDescriptor) async -> Void = { _ in }
    ) {
        self.catalog = catalog
        self.downloadManager = downloadManager
        self.activeModelID = activeModelID
        self.isPlatformSupported = isPlatformSupported
        observeLiveUpdates = initialStates == nil
        self.onSelectModel = onSelectModel
        self.onModelDeleted = onModelDeleted
        _modelStates = State(initialValue: initialStates ?? [:])
        if let initialTotalInstalledBytes {
            _totalInstalledBytes = State(initialValue: initialTotalInstalledBytes)
        } else if let initialStates {
            let sum = initialStates.values.reduce(into: Int64(0)) { total, state in
                if case .installed(_, let bytes) = state {
                    total += bytes
                }
            }
            _totalInstalledBytes = State(initialValue: sum)
        } else {
            _totalInstalledBytes = State(initialValue: 0)
        }
    }

    var body: some View {
        SettingsGroup(
            title: OnDeviceAIPlatformLabel.downloadedModelDisplayName,
            subtitle: Self.downloadPolicySubtitle,
            symbolName: "arrow.down.circle"
        ) {
            SettingsRowStack(spacing: BrevSpacing.md) {
                if !isPlatformSupported {
                    SettingsInfoCallout(
                        symbolName: "desktopcomputer",
                        message: DefaultLocalModelInferenceRuntime.platformUnsupportedMessage,
                        tone: .info
                    )
                }

                storageSummaryRow

                ForEach(catalog) { model in
                    modelRow(for: model)
                }

                if let actionErrorMessage {
                    SettingsInfoCallout(
                        symbolName: "exclamationmark.triangle",
                        message: actionErrorMessage,
                        tone: .warning
                    )
                }
            }
            .task {
                guard observeLiveUpdates else { return }
                let stream = await downloadManager.stateUpdates()
                for await snapshot in stream {
                    modelStates = snapshot
                    totalInstalledBytes = await downloadManager.totalInstalledBytes()
                }
            }
        }
    }

    private var storageSummaryRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: BrevSpacing.sm) {
            Image(systemName: "internaldrive")
                .foregroundStyle(theme.textSecondary.color)
            Text(
                String(
                    localized: "Local model storage: \(Self.formatBytes(totalInstalledBytes)) · Excluded from backups",
                    bundle: .module
                )
            )
            .brevFont(.footnote)
            .foregroundStyle(theme.textSecondary.color)
            Spacer(minLength: BrevSpacing.sm)
            if activeModelID != nil {
                Text(OnDeviceAIPlatformLabel.transparencyLabel)
                    .brevFont(.caption)
                    .foregroundStyle(theme.accent.color)
            }
        }
    }

    private func modelRow(for model: LocalModelDescriptor) -> some View {
        let state = modelStates[model.id] ?? .notDownloaded
        let isActive = activeModelID == model.id && state.isInstalled

        return VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            HStack(alignment: .top, spacing: BrevSpacing.sm) {
                VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                    Text(verbatim: model.displayName)
                        .brevFont(.headline)
                        .foregroundStyle(theme.textPrimary.color)
                    Text(verbatim: Self.specsLine(for: model))
                        .brevFont(.caption)
                        .foregroundStyle(theme.textSecondary.color)
                    Text(model.summary)
                        .brevFont(.footnote)
                        .foregroundStyle(theme.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(
                        String(
                            localized: "Source: \(model.sourceHost) · SHA-256 verified",
                            bundle: .module
                        )
                    )
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                }

                Spacer(minLength: BrevSpacing.sm)

                modelTrailingAction(for: model, state: state, isActive: isActive)
            }

            modelStateFooter(for: model, state: state, isActive: isActive)
        }
        .padding(BrevSpacing.md)
        .settingsInlineSurface()
    }

    @ViewBuilder
    private func modelTrailingAction(
        for model: LocalModelDescriptor,
        state: LocalModelDownloadState,
        isActive: Bool
    ) -> some View {
        let actions = LocalModelRowActionPolicy(
            state: state,
            isPlatformSupported: isPlatformSupported,
            isActive: isActive
        )
        switch state {
        case .notDownloaded:
            SettingsButton(String(localized: "Download", bundle: .module), style: .secondary) {
                startDownload(for: model)
            }
            .disabled(!actions.canDownload)
        case .downloading:
            SettingsButton(String(localized: "Cancel", bundle: .module), style: .secondary) {
                Task { await downloadManager.cancelDownload(modelID: model.id) }
            }
        case .verifying:
            ProgressView()
                .controlSize(.small)
        case .installed:
            HStack(spacing: BrevSpacing.xs) {
                if isActive {
                    Text(
                        String(
                            localized: "Active · \(OnDeviceAIPlatformLabel.transparencyLabel)",
                            bundle: .module
                        )
                    )
                    .brevFont(.caption)
                    .foregroundStyle(theme.accent.color)
                } else {
                    SettingsButton(String(localized: "Use model", bundle: .module), style: .secondary) {
                        guard actions.canUseModel else { return }
                        Task { await onSelectModel(model) }
                    }
                    .disabled(!actions.canUseModel)
                }
                SettingsButton(
                    String(localized: "Delete", bundle: .module),
                    style: .destructive,
                    confirmationTitle: String(localized: "Delete downloaded model weights?", bundle: .module)
                ) {
                    deleteWeights(for: model)
                }
                .disabled(!actions.canDelete)
            }
        case .failed:
            SettingsButton(String(localized: "Retry", bundle: .module), style: .secondary) {
                startDownload(for: model)
            }
            .disabled(!actions.canDownload)
        }
    }

    @ViewBuilder
    private func modelStateFooter(
        for _: LocalModelDescriptor,
        state: LocalModelDownloadState,
        isActive _: Bool
    ) -> some View {
        switch state {
        case .notDownloaded:
            EmptyView()
        case .downloading(let progress, let bytesWritten, let totalBytes):
            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                ProgressView(value: progress)
                    .tint(theme.accent.color)
                Text(
                    String(
                        localized: "Downloaded \(Self.formatBytes(bytesWritten)) of \(Self.formatBytes(totalBytes))",
                        bundle: .module
                    )
                )
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
            }
        case .verifying:
            Text(String(localized: "Verifying SHA-256…", bundle: .module))
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
        case .installed(_, let fileSizeBytes):
            Text(
                String(
                    localized: "Installed · \(Self.formatBytes(fileSizeBytes))",
                    bundle: .module
                )
            )
            .brevFont(.caption)
            .foregroundStyle(theme.success.color)
        case .failed(let message):
            Text(verbatim: message)
                .brevFont(.caption)
                .foregroundStyle(theme.warning.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func startDownload(for model: LocalModelDescriptor) {
        guard isPlatformSupported else { return }
        actionErrorMessage = nil
        Task {
            do {
                _ = try await downloadManager.download(modelID: model.id)
                totalInstalledBytes = await downloadManager.totalInstalledBytes()
            } catch LocalModelDownloadError.cancelled {
                actionErrorMessage = nil
            } catch {
                actionErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func deleteWeights(for model: LocalModelDescriptor) {
        actionErrorMessage = nil
        Task {
            do {
                try await downloadManager.deleteModel(modelID: model.id)
                totalInstalledBytes = await downloadManager.totalInstalledBytes()
                await onModelDeleted(model)
            } catch {
                actionErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private static var downloadPolicySubtitle: String {
        #if os(macOS)
        return String(
            localized: "Weights are downloaded only when you click Download, verified by SHA-256, stored locally outside backups, and run offline on this Mac.",
            bundle: .module
        )
        #else
        return String(
            localized: "Weights are downloaded only when you tap Download, verified by SHA-256, stored locally outside backups, and run offline on this device.",
            bundle: .module
        )
        #endif
    }

    private static func specsLine(for model: LocalModelDescriptor) -> String {
        let memoryNote = String(localized: "\(model.minimumMemoryGiB) GB RAM", bundle: .module)
        return [
            model.parameterCountLabel,
            model.quantization,
            model.formattedByteCount,
            model.licenseSPDX,
            memoryNote
        ].joined(separator: " · ")
    }

    private static func formatBytes(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, byteCount), countStyle: .file)
    }
}

/// Platform capability and state gating for Local Models row controls (#304).
struct LocalModelRowActionPolicy: Equatable {
    let state: LocalModelDownloadState
    let isPlatformSupported: Bool
    let isActive: Bool

    var canDownload: Bool {
        guard isPlatformSupported else { return false }
        switch state {
        case .notDownloaded, .failed:
            return true
        case .downloading, .verifying, .installed:
            return false
        }
    }

    var canUseModel: Bool {
        isPlatformSupported && state.isInstalled && !isActive
    }

    /// Delete stays enabled whenever verified weights exist on disk so users can reclaim storage
    /// even on platforms without local runtime support.
    var canDelete: Bool {
        state.isInstalled
    }
}
