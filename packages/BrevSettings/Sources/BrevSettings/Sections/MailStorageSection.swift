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
import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct MailStorageBreakdown: Equatable, Sendable {
    let cacheBytes: Int64
    let cacheObjectCount: Int
    let draftStagingBytes: Int64
    let draftStagingObjectCount: Int
    let offlineMetadataBytes: Int64
    let offlineMetadataObjectCount: Int

    var totalBytes: Int64 {
        cacheBytes + draftStagingBytes + offlineMetadataBytes
    }

    var totalObjectCount: Int {
        cacheObjectCount + draftStagingObjectCount + offlineMetadataObjectCount
    }
}

private struct MailStorageDirectoryMetrics: Equatable, Sendable {
    var bytes: Int64 = 0
    var objectCount = 0
}

enum MailStorageInfo {
    static func cacheRoot(fileManager: FileManager = .default) -> URL? {
        fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Brev/Cache", isDirectory: true)
    }

    static func accountDirectory(
        accountID: String,
        fileManager: FileManager = .default
    ) -> URL? {
        cacheRoot(fileManager: fileManager)?
            .appendingPathComponent(hexKey(accountID), isDirectory: true)
    }

    static func draftsRoot(fileManager: FileManager = .default) -> URL? {
        fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Brev/Drafts", isDirectory: true)
    }

    static func draftsDirectory(
        accountID: String,
        fileManager: FileManager = .default
    ) -> URL? {
        draftsRoot(fileManager: fileManager)?
            .appendingPathComponent(hexKey(accountID), isDirectory: true)
    }

    static func storageBreakdown(
        accountID: String,
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard
    ) -> MailStorageBreakdown {
        var cacheMetrics = MailStorageDirectoryMetrics()
        if let cacheURL = accountDirectory(accountID: accountID, fileManager: fileManager) {
            cacheMetrics = directoryMetrics(at: cacheURL, fileManager: fileManager)
            cacheMetrics.objectCount = cacheObjectCount(at: cacheURL, fileManager: fileManager)
        }

        var draftMetrics = MailStorageDirectoryMetrics()
        if let draftsURL = draftsDirectory(accountID: accountID, fileManager: fileManager) {
            draftMetrics = directoryMetrics(at: draftsURL, fileManager: fileManager)
        }

        let offlineMetrics = offlineMetadataMetrics(accountID: accountID, defaults: defaults)
        return MailStorageBreakdown(
            cacheBytes: cacheMetrics.bytes,
            cacheObjectCount: cacheMetrics.objectCount,
            draftStagingBytes: draftMetrics.bytes,
            draftStagingObjectCount: draftMetrics.objectCount,
            offlineMetadataBytes: offlineMetrics.bytes,
            offlineMetadataObjectCount: offlineMetrics.objectCount
        )
    }

    static func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func formattedObjectCount(_ count: Int) -> String {
        count == 1 ? String(localized: "1 object", bundle: .module) : String(localized: "\(count) objects", bundle: .module)
    }

    /// Delegates to the shared `MailCacheKeyNaming` so this and the mailbox
    /// storage helper stay byte-for-byte consistent (parity is relied on for
    /// object counts and path redaction).
    static func displayPath(for url: URL) -> String {
        MailCacheKeyNaming.displayPath(for: url)
    }

    static func hexKey(_ value: String) -> String {
        MailCacheKeyNaming.hexKey(value)
    }

    private static func directoryMetrics(
        at url: URL,
        fileManager: FileManager
    ) -> MailStorageDirectoryMetrics {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey],
            options: [],
            errorHandler: nil
        ) else {
            return MailStorageDirectoryMetrics()
        }

        var metrics = MailStorageDirectoryMetrics()
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]
            )
            guard values?.isRegularFile == true else { continue }
            metrics.bytes += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
            metrics.objectCount += 1
        }
        return metrics
    }

    private static func offlineMetadataMetrics(
        accountID: String,
        defaults: UserDefaults
    ) -> MailStorageDirectoryMetrics {
        [
            OfflineMutationQueueStorage.storageKey(accountID: accountID),
            OfflineMutationQueueStorage.conflictStorageKey(accountID: accountID),
        ].reduce(into: MailStorageDirectoryMetrics()) { metrics, key in
            guard let data = defaults.data(forKey: key) else { return }
            metrics.bytes += Int64(data.count)
            metrics.objectCount += 1
        }
    }

    private static func cacheObjectCount(
        at accountURL: URL,
        fileManager: FileManager
    ) -> Int {
        folderSnapshotObjectCount(
            at: accountURL.appendingPathComponent("folders.json", isDirectory: false),
            fileManager: fileManager
        )
            + headerSnapshotObjectCount(
                at: accountURL.appendingPathComponent("headers", isDirectory: true),
                fileManager: fileManager
            )
            + rootMessageSourceObjectCount(at: accountURL, fileManager: fileManager)
    }

    private static func folderSnapshotObjectCount(
        at url: URL,
        fileManager: FileManager
    ) -> Int {
        guard fileManager.fileExists(atPath: url.path) else { return 0 }
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(IMAPFolderCacheSnapshot.self, from: data)
        else {
            return 1
        }
        return snapshot.folders.count
    }

    private static func headerSnapshotObjectCount(
        at headersURL: URL,
        fileManager: FileManager
    ) -> Int {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: headersURL,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return 0
        }
        return urls.reduce(into: 0) { count, url in
            // Skip non-regular entries (e.g. subdirectories) entirely; only a
            // regular-but-undecodable file counts as one object. Matches
            // MailboxStorageInfo so the two storage views report the same count.
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true
            else {
                return
            }
            guard let data = try? Data(contentsOf: url),
                  let snapshot = try? JSONDecoder().decode(IMAPMailboxHeaderCacheSnapshot.self, from: data)
            else {
                count += 1
                return
            }
            count += snapshot.headers.count
        }
    }

    private static func rootMessageSourceObjectCount(
        at accountURL: URL,
        fileManager: FileManager
    ) -> Int {
        let headersURL = accountURL.appendingPathComponent("headers", isDirectory: true)
        guard let enumerator = fileManager.enumerator(
            at: accountURL,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return 0
        }
        var count = 0
        for case let url as URL in enumerator {
            guard url.lastPathComponent != "folders.json",
                  !isDescendant(url, of: headersURL),
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true
            else {
                continue
            }
            count += 1
        }
        return count
    }

    private static func isDescendant(_ url: URL, of directory: URL) -> Bool {
        let directoryPath = directory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == directoryPath || path.hasPrefix(directoryPath + "/")
    }
}

struct MailStorageRowPresentation: Equatable {
    let title: String
    let value: String
    let detail: String
}

struct MailStorageResetConfirmationPresentation: Equatable {
    let title: String
    let message: String
    let confirmTitle: String
}

enum MailStorageRepairAction: Equatable {
    case downloadAllMail
    case resetAndRedownload
}

enum MailStorageRepairStep: Equatable {
    case resetLocalCacheAndIndex
    case rebuildSearchIndex
    case applyRetentionAfterDownload
}

struct MailStorageRetentionApplication: Equatable {
    let sourceID: MailSourceID
    let folderID: Folder.ID
    let retentionDays: Int?
    let keepsBodies: Bool
}

struct MailStorageRetentionSummary: Equatable {
    let title: String
    let detail: String
}

struct MailStorageSyncHealthLoadFailure: Equatable {
    let sourceID: MailSourceID?
    let syncHealth: AccountSyncHealth?
    let statusMessage: String
}

enum MailStorageSyncHealthLoadPolicy {
    private static let failurePrefix = String(localized: "Could not load storage health:", bundle: .module)

    static func failure(for error: any Error) -> MailStorageSyncHealthLoadFailure {
        MailStorageSyncHealthLoadFailure(
            sourceID: nil,
            syncHealth: nil,
            statusMessage: "\(failurePrefix) \(error.localizedDescription)"
        )
    }

    static func statusMessageAfterSuccessfulLoad(current: String?) -> String? {
        guard current?.hasPrefix(failurePrefix) == true else { return current }
        return nil
    }
}

struct MailStorageReloadKey: Hashable {
    let accountID: BrevAccount.ID?
    let backendID: ObjectIdentifier?

    init(
        accountID: BrevAccount.ID?,
        backend: (any MailBackend)?
    ) {
        self.accountID = accountID
        backendID = backend.map(ObjectIdentifier.init)
    }
}

enum MailStorageRepairPlan {
    static func steps(for action: MailStorageRepairAction) -> [MailStorageRepairStep] {
        switch action {
        case .downloadAllMail:
            return [.rebuildSearchIndex, .applyRetentionAfterDownload]
        case .resetAndRedownload:
            return [.resetLocalCacheAndIndex, .rebuildSearchIndex, .applyRetentionAfterDownload]
        }
    }

    static func pollsSyncHealth(during action: MailStorageRepairAction) -> Bool {
        steps(for: action).contains(.rebuildSearchIndex)
    }
}

enum MailStorageRetentionPlan {
    static func applications(
        for folders: [Folder],
        sourceID: MailSourceID,
        settings: AccountMailboxSyncSettings
    ) -> [MailStorageRetentionApplication] {
        var seenFolderIDs = Set<Folder.ID>()
        return folders.compactMap { folder in
            guard seenFolderIDs.insert(folder.id).inserted else { return nil }
            let policy = settings.policy(for: folder.id)
            return MailStorageRetentionApplication(
                sourceID: sourceID,
                folderID: folder.id,
                retentionDays: policy.retentionDays,
                keepsBodies: policy.keepsBodies
            )
        }
    }
}

struct MailStorageRetentionChangeDecision: Equatable {
    let appliesImmediately: Bool
    let postsChangeNotification: Bool
    let statusMessage: String?
}

enum MailStorageRetentionChangePolicy {
    static func decision(
        hasBackend: Bool,
        hasSourceID: Bool,
        isActionRunning: Bool,
        syncHealthState: SyncHealthState?
    ) -> MailStorageRetentionChangeDecision {
        guard !isActionRunning, syncHealthState != .indexing else {
            return MailStorageRetentionChangeDecision(
                appliesImmediately: false,
                postsChangeNotification: false,
                statusMessage: String(
                    localized: "Saved cache lookback; it will apply after the current storage action finishes.",
                    bundle: .module
                )
            )
        }
        return MailStorageRetentionChangeDecision(
            appliesImmediately: hasBackend && hasSourceID,
            postsChangeNotification: true,
            statusMessage: nil
        )
    }
}

enum MailStorageActionAvailability {
    static func canRun(
        hasRepairService: Bool,
        hasSourceID: Bool,
        isActionRunning: Bool,
        syncHealthState: SyncHealthState?,
        indexStatus: SearchIndexStatus?
    ) -> Bool {
        guard hasRepairService, hasSourceID, !isActionRunning else { return false }
        guard syncHealthState != .indexing else { return false }
        guard case .rebuilding = indexStatus else { return true }
        return false
    }
}

enum MailStoragePresentation {
    static func resetConfirmation(
        breakdown: MailStorageBreakdown?,
        indexMetrics: LocalSearchIndexMetrics?
    ) -> MailStorageResetConfirmationPresentation {
        let target = totalBytes(for: breakdown, indexMetrics: indexMetrics).map {
            MailStorageInfo.formattedSize($0)
        } ?? String(localized: "this account's local mail data", bundle: .module)
        return MailStorageResetConfirmationPresentation(
            title: String(localized: "Reset & re-download local mail?", bundle: .module),
            message: String(
                localized: "Brev will delete \(target), including the local mail cache, search index, draft staging, pending offline retries, and reviewed conflict metadata, then rebuild local mail from the server. Accounts, credentials, settings, and server mail stay untouched.",
                bundle: .module
            ),
            confirmTitle: String(localized: "Reset & re-download", bundle: .module)
        )
    }

    static func rows(
        for breakdown: MailStorageBreakdown,
        indexMetrics: LocalSearchIndexMetrics?
    ) -> [MailStorageRowPresentation] {
        var rows = [
            MailStorageRowPresentation(
                title: String(localized: "Mail cache", bundle: .module),
                value: MailStorageInfo.formattedSize(breakdown.cacheBytes),
                detail: MailStorageInfo.formattedObjectCount(breakdown.cacheObjectCount)
            ),
            MailStorageRowPresentation(
                title: String(localized: "Draft staging", bundle: .module),
                value: MailStorageInfo.formattedSize(breakdown.draftStagingBytes),
                detail: MailStorageInfo.formattedObjectCount(breakdown.draftStagingObjectCount)
            ),
            MailStorageRowPresentation(
                title: String(localized: "Offline sync metadata", bundle: .module),
                value: MailStorageInfo.formattedSize(breakdown.offlineMetadataBytes),
                detail: MailStorageInfo.formattedObjectCount(breakdown.offlineMetadataObjectCount)
            ),
        ]
        if let indexMetrics {
            rows.append(MailStorageRowPresentation(
                title: String(localized: "Search index database", bundle: .module),
                value: MailStorageInfo.formattedSize(indexMetrics.databaseBytes),
                detail: indexDetail(for: indexMetrics)
            ))
        }
        return rows
    }

    static func totalValue(
        for breakdown: MailStorageBreakdown?,
        indexMetrics: LocalSearchIndexMetrics?
    ) -> String {
        guard let breakdown,
              let bytes = totalBytes(for: breakdown, indexMetrics: indexMetrics)
        else { return String(localized: "Calculating...", bundle: .module) }
        let objects = breakdown.totalObjectCount + (indexMetrics.map(indexRecordCount) ?? 0)
        return "\(MailStorageInfo.formattedSize(bytes)) - \(MailStorageInfo.formattedObjectCount(objects))"
    }

    private static func totalBytes(
        for breakdown: MailStorageBreakdown?,
        indexMetrics: LocalSearchIndexMetrics?
    ) -> Int64? {
        guard let breakdown else { return nil }
        return breakdown.totalBytes + (indexMetrics?.databaseBytes ?? 0)
    }

    static func actionTitle(
        for action: MailStorageRepairAction,
        isRunning: Bool
    ) -> String {
        if isRunning {
            switch action {
            case .downloadAllMail:
                return String(localized: "Downloading mail...", bundle: .module)
            case .resetAndRedownload:
                return String(localized: "Resetting and downloading...", bundle: .module)
            }
        }
        switch action {
        case .downloadAllMail:
            return String(localized: "Download all mail", bundle: .module)
        case .resetAndRedownload:
            return String(localized: "Reset & re-download", bundle: .module)
        }
    }

    static func indexSummary(for health: AccountSyncHealth?) -> String {
        guard let health else { return String(localized: "Index status unavailable.", bundle: .module) }
        switch health.indexStatus {
        case .notBuilt:
            return String(localized: "Local search index has not been built.", bundle: .module)
        case .ready(let messageCount):
            if let metrics = health.localSearchIndexMetrics {
                return String(
                    localized: "Local search index ready: \(indexRecordCount(metrics)) index objects, \(metrics.indexedHeaderCount) headers, \(metrics.cachedBodyCount) bodies, \(metrics.searchDocumentCount) search docs, \(metrics.syncedFolderCount) folders.",
                    bundle: .module
                )
            }
            return String(localized: "Local search index ready: \(messageCount) messages.", bundle: .module)
        case .rebuilding(let progress):
            let prefix: String
            if let progress {
                let percent = Int((progress * 100).rounded())
                prefix = String(localized: "Downloading and indexing mail: \(percent)% complete.", bundle: .module)
            } else {
                prefix = String(localized: "Downloading and indexing mail.", bundle: .module)
            }
            if let metrics = health.localSearchIndexMetrics {
                return String(
                    localized: "\(prefix) \(indexRecordCount(metrics)) index objects, \(metrics.indexedHeaderCount) headers, \(metrics.cachedBodyCount) bodies, \(metrics.searchDocumentCount) search docs, \(metrics.syncedFolderCount) folders.",
                    bundle: .module
                )
                    + indexProgressDetail(health.searchIndexProgress)
            }
            return prefix + indexProgressDetail(health.searchIndexProgress)
        case .failed(let message):
            return String(localized: "Local search index failed: \(message)", bundle: .module)
        }
    }

    private static func indexDetail(for metrics: LocalSearchIndexMetrics) -> String {
        String(
            localized: "\(indexRecordCount(metrics)) index objects - \(metrics.indexedHeaderCount) headers - \(metrics.cachedBodyCount) bodies - \(metrics.searchDocumentCount) docs - \(metrics.syncedFolderCount) folders",
            bundle: .module
        )
    }

    private static func indexProgressDetail(_ progress: SearchIndexProgressSnapshot?) -> String {
        guard let progress else { return "" }
        let failureSuffix: String
        if progress.bodyBackfillFailureCount > 0 {
            let noun = progress.bodyBackfillFailureCount == 1 ? String(localized: "body cache failure", bundle: .module) : String(
                localized: "body cache failures",
                bundle: .module
            )
            failureSuffix = ", \(progress.bodyBackfillFailureCount) \(noun)"
        } else {
            failureSuffix = ""
        }
        return String(
            localized: " \(progress.completedFolderCount)/\(progress.totalFolderCount) folders complete, \(progress.indexedMessageCount) messages indexed",
            bundle: .module
        )
            + failureSuffix
            + "."
    }

    private static func indexRecordCount(_ metrics: LocalSearchIndexMetrics) -> Int {
        metrics.indexedHeaderCount
            + metrics.cachedBodyCount
            + metrics.searchDocumentCount
            + metrics.syncedFolderCount
    }

    static func retentionSummary(for settings: AccountMailboxSyncSettings) -> MailStorageRetentionSummary {
        let overrides = settings.folderOverrides.values.filter { $0.retentionPolicy != nil }.count
        let detail = overrides == 0
            ? String(localized: "No folder overrides", bundle: .module)
            : overrides == 1
            ? String(localized: "\(overrides) folder override", bundle: .module)
            : String(localized: "\(overrides) folder overrides", bundle: .module)
        return MailStorageRetentionSummary(
            title: settings.offlineRetentionPolicy.displayName,
            detail: "\(settings.offlineRetentionPolicy.description) \(detail)."
        )
    }

    static var retentionDownloadExplanation: String {
        String(
            localized: "Download all mail applies this policy immediately after indexing. Headers remain searchable; message bodies follow the selected lookback. Choose Everything before downloading to keep full body search for all mail.",
            bundle: .module
        )
    }

    /// Title for the Advanced storage disclosure control.
    static func advancedDisclosureTitle(isExpanded: Bool) -> String {
        isExpanded ? String(localized: "Hide advanced storage", bundle: .module) : String(
            localized: "Advanced storage…",
            bundle: .module
        )
    }

    /// Collapsed summary shows size + location only; power tools stay behind Advanced.
    static func showsAdvancedContent(isExpanded: Bool) -> Bool {
        isExpanded
    }
}

struct MailStorageSection: View {
    @Environment(\.brevTheme) private var theme

    private let account: BrevAccount?
    private let backend: (any MailBackend)?
    private let settingsStore: SettingsPersistenceStore

    @State private var breakdown: MailStorageBreakdown?
    @State private var storageURL: URL?
    @State private var sourceID: MailSourceID?
    @State private var syncHealth: AccountSyncHealth?
    @State private var syncSettings: AccountMailboxSyncSettings
    @State private var isLoading = false
    @State private var activeAction: MailStorageRepairAction?
    @State private var statusMessage: String?
    @State private var isShowingResetConfirmation = false
    @State private var isAdvancedExpanded: Bool
    @State private var syncHealthPollingTask: Task<Void, Never>?

    init(
        account: BrevAccount?,
        backend: (any MailBackend)?,
        settingsStore: SettingsPersistenceStore,
        initiallyAdvancedExpanded: Bool = false
    ) {
        self.account = account
        self.backend = backend
        self.settingsStore = settingsStore
        _syncSettings = State(initialValue: settingsStore.accountMailboxSyncSettings())
        _isAdvancedExpanded = State(initialValue: initiallyAdvancedExpanded)
    }

    var body: some View {
        SectionScaffold(
            title: String(localized: "Mail Storage", bundle: .module),
            subtitle: String(
                localized: "Inspect local mail data, rebuild the search index, and control downloaded mail.",
                bundle: .module
            )
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.xl) {
                if account == nil {
                    SettingsInfoCallout(
                        symbolName: "tray",
                        message: String(localized: "Add or select an account to inspect local mail storage.", bundle: .module),
                        tone: .info
                    )
                } else {
                    storageSummaryGroup
                    advancedDisclosureControl
                    if MailStoragePresentation.showsAdvancedContent(isExpanded: isAdvancedExpanded) {
                        storageBreakdownGroup
                        retentionGroup
                        indexGroup
                        downloadActionGroup
                        resetActionGroup
                    }
                }
            }
        }
        .task(id: reloadKey) {
            await reload()
        }
        .onDisappear {
            stopSyncHealthPolling()
        }
        .alert(storageResetPresentation.title, isPresented: $isShowingResetConfirmation) {
            Button(storageResetPresentation.confirmTitle, role: .destructive) {
                Task { await run(.resetAndRedownload) }
            }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) {}
        } message: {
            Text(storageResetPresentation.message)
        }
    }

    private var indexMetrics: LocalSearchIndexMetrics? {
        syncHealth?.localSearchIndexMetrics
    }

    private var storageResetPresentation: MailStorageResetConfirmationPresentation {
        MailStoragePresentation.resetConfirmation(
            breakdown: breakdown,
            indexMetrics: indexMetrics
        )
    }

    private var reloadKey: MailStorageReloadKey {
        MailStorageReloadKey(accountID: account?.id, backend: backend)
    }

    private var storageSummaryGroup: some View {
        SettingsGroup(
            title: String(localized: "Local data", bundle: .module),
            subtitle: String(localized: "Size on disk and cache location for this account.", bundle: .module),
            symbolName: "internaldrive"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                storageValueRow(
                    title: String(localized: "Size on disk", bundle: .module),
                    value: MailStoragePresentation.totalValue(
                        for: breakdown,
                        indexMetrics: indexMetrics
                    )
                )
                if let storageURL {
                    storageValueRow(
                        title: String(localized: "Cache location", bundle: .module),
                        value: MailStorageInfo.displayPath(for: storageURL)
                    )
                }
                #if os(macOS)
                if let storageURL {
                    BrevButton(String(localized: "Reveal Cache in Finder", bundle: .module), style: .secondary) {
                        NSWorkspace.shared.activateFileViewerSelecting([storageURL])
                    }
                }
                #endif
            }
        }
    }

    private var advancedDisclosureControl: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isAdvancedExpanded.toggle()
            }
        } label: {
            HStack(spacing: BrevSpacing.xs) {
                Text(MailStoragePresentation.advancedDisclosureTitle(isExpanded: isAdvancedExpanded))
                    .brevFont(.subheadline)
                Image(systemName: isAdvancedExpanded ? "chevron.up" : "chevron.down")
                    .brevFont(.caption)
                Spacer(minLength: 0)
            }
            .foregroundStyle(theme.accent.color)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(MailStoragePresentation.advancedDisclosureTitle(isExpanded: isAdvancedExpanded))
    }

    private var storageBreakdownGroup: some View {
        SettingsGroup(
            title: String(localized: "Breakdown", bundle: .module),
            subtitle: String(
                localized: "Brev-owned cache, draft staging, offline metadata, and search index counts.",
                bundle: .module
            ),
            symbolName: "chart.bar"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                if let breakdown {
                    ForEach(MailStoragePresentation.rows(
                        for: breakdown,
                        indexMetrics: indexMetrics
                    ), id: \.title) { row in
                        storageValueRow(title: row.title, value: "\(row.value) - \(row.detail)")
                    }
                } else {
                    storageValueRow(title: String(localized: "Details", bundle: .module), value: "Calculating...")
                }
            }
        }
    }

    private var indexGroup: some View {
        SettingsGroup(
            title: String(localized: "Search index", bundle: .module),
            subtitle: String(localized: "Download mail locally so all-mail search can use the durable index.", bundle: .module),
            symbolName: "magnifyingglass"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                SettingsInfoCallout(
                    symbolName: "doc.text.magnifyingglass",
                    message: MailStoragePresentation.indexSummary(for: syncHealth),
                    tone: indexCalloutTone
                )
                if let statusMessage {
                    SettingsInfoCallout(
                        symbolName: "info.circle",
                        message: statusMessage,
                        tone: .info
                    )
                }
            }
        }
    }

    private var retentionGroup: some View {
        let summary = MailStoragePresentation.retentionSummary(for: syncSettings)
        return SettingsGroup(
            title: String(localized: "Local retention", bundle: .module),
            subtitle: String(localized: "Choose how far back Brev keeps full message bodies in local storage.", bundle: .module),
            symbolName: "calendar.badge.clock"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                SettingsPickerRow(
                    symbolName: "clock.arrow.circlepath",
                    title: String(localized: "Cache lookback", bundle: .module),
                    subtitle: summary.detail,
                    selection: retentionPolicyBinding,
                    selectionTitle: syncSettings.offlineRetentionPolicy.displayName
                ) {
                    ForEach(OfflineRetentionPolicy.allCases) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }

                SettingsInfoCallout(
                    symbolName: "info.circle",
                    message: MailStoragePresentation.retentionDownloadExplanation,
                    tone: .info
                )
            }
        }
    }

    private var downloadActionGroup: some View {
        SettingsGroup(
            title: String(localized: "Download", bundle: .module),
            subtitle: String(
                localized: "Rebuild local mail data without changing server mail, accounts, credentials, or settings.",
                bundle: .module
            ),
            symbolName: "arrow.down.circle"
        ) {
            BrevButton(
                MailStoragePresentation.actionTitle(
                    for: .downloadAllMail,
                    isRunning: activeAction == .downloadAllMail
                ),
                style: .primary
            ) {
                Task { await run(.downloadAllMail) }
            }
            .disabled(!canRunActions)
        }
    }

    private var resetActionGroup: some View {
        SettingsGroup(
            title: String(localized: "Reset", bundle: .module),
            subtitle: String(
                localized: "Delete local mail data for this account, then rebuild from the server.",
                bundle: .module
            ),
            symbolName: "arrow.triangle.2.circlepath"
        ) {
            BrevButton(
                MailStoragePresentation.actionTitle(
                    for: .resetAndRedownload,
                    isRunning: activeAction == .resetAndRedownload
                ),
                style: .destructive
            ) {
                isShowingResetConfirmation = true
            }
            .disabled(!canRunActions)
        }
    }

    private var retentionPolicyBinding: Binding<OfflineRetentionPolicy> {
        Binding(
            get: { syncSettings.offlineRetentionPolicy },
            set: { newValue in
                syncSettings.offlineRetentionPolicy = newValue
                settingsStore.save(syncSettings)
                let decision = MailStorageRetentionChangePolicy.decision(
                    hasBackend: backend != nil,
                    hasSourceID: sourceID != nil,
                    isActionRunning: activeAction != nil,
                    syncHealthState: syncHealth?.state
                )
                if decision.postsChangeNotification {
                    NotificationCenter.default.post(name: .brevMailboxSyncSettingsDidChange, object: nil)
                }
                statusMessage = decision.statusMessage
                if decision.appliesImmediately {
                    Task { await applySavedRetentionForCurrentSource() }
                }
            }
        )
    }

    private var canRunActions: Bool {
        MailStorageActionAvailability.canRun(
            hasRepairService: backend?.extensionService(SyncHealthRepairing.self) != nil,
            hasSourceID: sourceID != nil,
            isActionRunning: activeAction != nil,
            syncHealthState: syncHealth?.state,
            indexStatus: syncHealth?.indexStatus
        )
    }

    private var indexCalloutTone: SettingsCalloutTone {
        switch syncHealth?.indexStatus {
        case .ready:
            return .success
        case .failed:
            return .warning
        case .notBuilt, .rebuilding, .none:
            return .info
        }
    }

    @ViewBuilder
    private func storageValueRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: BrevSpacing.md) {
            Text(title)
                .brevFont(.subheadline)
                .foregroundStyle(theme.textSecondary.color)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: BrevSpacing.md)
            Text(value)
                .brevFont(.subheadline)
                .foregroundStyle(theme.textPrimary.color)
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .layoutPriority(1)
        }
    }

    private func reload() async {
        sourceID = nil
        syncHealth = nil
        guard let account else {
            breakdown = nil
            storageURL = nil
            return
        }
        isLoading = true
        syncSettings = settingsStore.accountMailboxSyncSettings()
        storageURL = MailStorageInfo.accountDirectory(accountID: account.id)
        breakdown = await Task.detached {
            MailStorageInfo.storageBreakdown(accountID: account.id)
        }.value
        await loadSyncHealth()
        isLoading = false
    }

    private func loadSyncHealth() async {
        guard let backend else {
            sourceID = nil
            syncHealth = nil
            return
        }
        do {
            let sourceID = try await resolveSourceID(backend: backend)
            self.sourceID = sourceID
            if let reporter = backend.extensionService(SyncHealthReporting.self) {
                syncHealth = await reporter.syncHealth(for: sourceID)
            } else {
                syncHealth = nil
            }
            statusMessage = MailStorageSyncHealthLoadPolicy.statusMessageAfterSuccessfulLoad(current: statusMessage)
        } catch {
            let failure = MailStorageSyncHealthLoadPolicy.failure(for: error)
            sourceID = failure.sourceID
            syncHealth = failure.syncHealth
            statusMessage = failure.statusMessage
        }
    }

    private func resolveSourceID(backend: any MailBackend) async throws -> MailSourceID {
        let mailbox = try await backend.currentMailbox()
        return backend.sourceID(for: mailbox)
    }

    private func run(_ action: MailStorageRepairAction) async {
        guard let backend,
              let sourceID,
              let repair = backend.extensionService(SyncHealthRepairing.self),
              activeAction == nil
        else { return }
        activeAction = action
        statusMessage = nil
        let shouldPollSyncHealth = MailStorageRepairPlan.pollsSyncHealth(during: action)
        if shouldPollSyncHealth {
            startSyncHealthPolling()
        }
        defer {
            if shouldPollSyncHealth {
                stopSyncHealthPolling()
            }
            activeAction = nil
        }
        do {
            for step in MailStorageRepairPlan.steps(for: action) {
                switch step {
                case .resetLocalCacheAndIndex:
                    try await repair.resetLocalCacheAndIndex(for: sourceID)
                case .rebuildSearchIndex:
                    try await repair.rebuildSearchIndex(for: sourceID)
                case .applyRetentionAfterDownload:
                    try await applySavedRetention(backend: backend, sourceID: sourceID)
                }
            }
            statusMessage = action == .downloadAllMail
                ? String(localized: "Downloaded and indexed local mail.", bundle: .module)
                : String(localized: "Reset and rebuilt local mail data.", bundle: .module)
            await reload()
        } catch {
            statusMessage = String(localized: "Storage action failed: \(error.localizedDescription)", bundle: .module)
            await loadSyncHealth()
        }
    }

    private func startSyncHealthPolling() {
        syncHealthPollingTask?.cancel()
        syncHealthPollingTask = Task {
            while !Task.isCancelled {
                await loadSyncHealth()
                do {
                    try await Task.sleep(nanoseconds: 500_000_000)
                } catch {
                    break
                }
            }
        }
    }

    private func stopSyncHealthPolling() {
        syncHealthPollingTask?.cancel()
        syncHealthPollingTask = nil
    }

    private func applySavedRetentionForCurrentSource() async {
        guard activeAction == nil,
              let backend,
              let sourceID
        else { return }
        statusMessage = String(localized: "Applying local retention...", bundle: .module)
        do {
            try await applySavedRetention(backend: backend, sourceID: sourceID)
            statusMessage = String(localized: "Updated local retention.", bundle: .module)
            await reload()
        } catch {
            statusMessage = String(localized: "Could not apply local retention: \(error.localizedDescription)", bundle: .module)
            await loadSyncHealth()
        }
    }

    private func applySavedRetention(
        backend: any MailBackend,
        sourceID: MailSourceID
    ) async throws {
        let folders = try await backend.folders(in: sourceID)
        let applications = MailStorageRetentionPlan.applications(
            for: folders,
            sourceID: sourceID,
            settings: settingsStore.accountMailboxSyncSettings()
        )
        for application in applications {
            try await backend.applyRetention(
                folderID: application.folderID,
                sourceID: application.sourceID,
                retentionDays: application.retentionDays,
                keepsBodies: application.keepsBodies
            )
        }
    }
}
