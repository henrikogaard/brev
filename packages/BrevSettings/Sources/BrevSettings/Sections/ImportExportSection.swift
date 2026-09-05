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
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// Whether the folder pickers can offer anything, and why not when they can't.
enum ImportExportFolderLoadStatus: Equatable {
    case ready
    case loading
    case failed(String)
    case unavailable(String)
}

enum ImportExportFolderLoadPresentation {
    /// Folders present always win: a retry that succeeds must not keep showing
    /// the error that preceded it.
    static func status(
        hasBackend: Bool,
        isLoading: Bool,
        folderCount: Int,
        errorMessage: String?
    ) -> ImportExportFolderLoadStatus {
        if folderCount > 0 { return .ready }
        guard hasBackend else {
            return .unavailable("Sign in to an account to import into or export from a folder.")
        }
        if isLoading { return .loading }
        if let errorMessage { return .failed(String(localized: "Couldn't load folders: \(errorMessage)", bundle: .module)) }
        return .unavailable(String(localized: "No folders found for this account.", bundle: .module))
    }
}

struct ImportExportSection: View {
    @Environment(\.brevTheme) private var theme

    private let backendProvider: @MainActor (BrevAccount.ID) -> (any MailBackend)?
    private let accounts: [BrevAccount]
    private let currentAccountID: BrevAccount.ID?
    private let exportController: MailFolderExportController

    @State private var allFolders: [Folder]
    @State private var isLoadingFolders = false
    @State private var folderLoadErrorMessage: String?
    @State private var importState: ImportState = .idle
    @State private var exportMailboxes: [Mailbox] = []
    @State private var exportMailboxAccountID: BrevAccount.ID?
    @State private var exportMailboxID: Mailbox.ID?
    @State private var exportFolders: [Folder] = []
    @State private var exportFolderID: Folder.ID?
    @State private var loadedExportSourceID: MailSourceID?
    @State private var loadedImportSourceID: MailSourceID?
    @State private var isLoadingExportFolders = false
    @State private var exportFolderError: String?
    @State private var exportReloadRevision = 0
    @State private var selectedFolderID: Folder.ID?
    @State private var importDestination: ImportDestination = .newFolder

    #if os(iOS)
    @State private var isChoosingExportFolder = false
    @State private var mobileExportRequest: MobileExportRequest?

    private struct MobileExportRequest: Sendable {
        let id = UUID()
        let exporter: MailFolderExporter
        let title: String
        let folderName: String
        let format: MailFolderExportFormat
        let sessionToken: MailFolderExportSessionToken
    }
    #endif

    enum ImportState: Equatable {
        case idle
        case parsing
        case importing(current: Int, total: Int?)
        case completed(count: Int, errors: [String])
        case failed(String)
    }

    enum ImportDestination: String, CaseIterable, Identifiable {
        case newFolder
        case mergeExisting

        var id: String { rawValue }
        var title: String {
            switch self {
            case .newFolder: return String(localized: "Create new folder", bundle: .module)
            case .mergeExisting: return String(localized: "Merge into existing folder", bundle: .module)
            }
        }
    }

    init(
        backendProvider: @MainActor @escaping (BrevAccount.ID) -> (any MailBackend)?,
        accounts: [BrevAccount],
        currentAccountID: BrevAccount.ID?,
        exportController: MailFolderExportController,
        allFolders: [Folder] = []
    ) {
        self.backendProvider = backendProvider
        self.accounts = accounts
        self.currentAccountID = currentAccountID
        self.exportController = exportController
        _allFolders = State(initialValue: allFolders)
    }

    var body: some View {
        #if os(iOS)
        let pickerRequest = mobileExportRequest
        #endif
        SectionScaffold(
            title: String(localized: "Import / Export", bundle: .module),
            subtitle: String(localized: "Import mail into a mailbox or save a folder to files.", bundle: .module)
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.xl) {
                importGroup
                exportGroup
                privacyNote
            }
        }
        // The app hands this section no folders — nothing upstream keeps a
        // mailbox-wide folder list — so it loads its own from the selected
        // account, and reloads when that account changes.
        .task(id: ExportLoadKey(backend: exportBackendIdentity, revision: exportReloadRevision)) {
            await loadFolders()
            guard !Task.isCancelled else { return }
            await loadExportMailboxes()
        }
        .task(id: selectedExportSourceID) { await loadExportFolders() }
        .onChange(of: accounts.map(\.id)) { previous, current in
            if !Set(previous).isSubset(of: Set(current)) {
                #if os(iOS)
                mobileExportRequest = nil
                isChoosingExportFolder = false
                #endif
            }
        }
        #if os(iOS)
        .fileImporter(isPresented: $isChoosingExportFolder, allowedContentTypes: [.folder]) { result in
            guard let request = pickerRequest, mobileExportRequest?.id == request.id else { return }
            mobileExportRequest = nil
            let directory: URL
            switch result {
            case .success(let url): directory = url
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled {
                    exportController.reportSelectionFailure(error.localizedDescription, sourceTitle: request.title)
                }
                return
            }
            let target = request.format == .mbox
                ? MailFolderExporter.availableArchiveURL(in: directory, folderName: request.folderName) : directory
            exportController.start(request.exporter, to: target, format: request.format, sourceTitle: request.title,
                                   replacingExistingFile: false, accessing: directory, sessionToken: request.sessionToken)
        }
        #endif
    }

    private var folderLoadStatus: ImportExportFolderLoadStatus {
        ImportExportFolderLoadPresentation.status(
            hasBackend: currentBackend != nil,
            isLoading: isLoadingFolders,
            folderCount: allFolders.count,
            errorMessage: folderLoadErrorMessage
        )
    }

    @ViewBuilder
    private var folderStatusView: some View {
        switch folderLoadStatus {
        case .ready:
            EmptyView()
        case .loading:
            progressRow(symbol: "folder", text: "Loading folders…")
        case .failed(let message):
            SettingsInfoCallout(symbolName: "exclamationmark.triangle", message: message, tone: .warning)
        case .unavailable(let message):
            SettingsInfoCallout(symbolName: "folder", message: message, tone: .info)
        }
    }

    private func loadFolders() async {
        guard let backend = currentBackend else {
            allFolders = []
            return
        }

        isLoadingFolders = true
        folderLoadErrorMessage = nil
        let previousSource = loadedImportSourceID
        loadedImportSourceID = nil
        do {
            let mailbox = try await backend.currentMailbox()
            let source = backend.sourceID(for: mailbox)
            let loaded = try await backend.folders(in: source)
            guard !Task.isCancelled else { return }
            allFolders = loaded
            if previousSource != source { selectedFolderID = nil }
            loadedImportSourceID = source
        } catch {
            guard !Task.isCancelled else { return }
            let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            folderLoadErrorMessage = message.isEmpty ? String(localized: "Unknown error", bundle: .module) : message
            allFolders = []
        }
        isLoadingFolders = false
    }

    private var importGroup: some View {
        SettingsGroup(
            title: String(localized: "Import mail", bundle: .module),
            subtitle: String(localized: "Import MBOX archives or Maildir folders into Brev.", bundle: .module),
            symbolName: "tray.and.arrow.down"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                destinationPicker

                HStack(spacing: BrevSpacing.sm) {
                    Button(String(localized: "Import MBOX File…", bundle: .module)) {
                        startImportMBOX()
                    }
                    .disabled(!canImport)

                    Button(String(localized: "Import Maildir Folder…", bundle: .module)) {
                        startImportMaildir()
                    }
                    .disabled(!canImport)
                }

                if currentBackend != nil && currentBackend?.extensionService(MailImporting.self) == nil {
                    SettingsInfoCallout(symbolName: "info.circle",
                                        message: String(
                                            localized: "Mail import is not supported by this account yet.",
                                            bundle: .module
                                        ), tone: .info)
                }
                #if os(iOS)
                Text("Mail import is currently available on Mac.", bundle: .module)
                    .brevFont(.caption).foregroundStyle(theme.textSecondary.color)
                #endif
                importProgressView
            }
        }
    }

    private var destinationPicker: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            Picker(String(localized: "Destination", bundle: .module), selection: $importDestination) {
                ForEach(ImportDestination.allCases) { dest in
                    Text(dest.title).tag(dest)
                }
            }
            .pickerStyle(.segmented)

            if importDestination == .mergeExisting {
                Picker(String(localized: "Target folder", bundle: .module), selection: $selectedFolderID) {
                    Text("Select folder…", bundle: .module).tag(Folder.ID?.none)
                    ForEach(allFolders) { folder in
                        Text(folder.name).tag(Folder.ID?.some(folder.id))
                    }
                }
                .disabled(allFolders.isEmpty)

                folderStatusView
            }
        }
    }

    @ViewBuilder
    private var importProgressView: some View {
        switch importState {
        case .idle:
            EmptyView()
        case .parsing:
            progressRow(symbol: "doc.text.magnifyingglass", text: "Parsing file…")
        case .importing(let current, let total):
            VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                if let total {
                    ProgressView(value: Double(current), total: Double(total))
                        .tint(theme.accent.color)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(total.map { String(localized: "Importing \(current) of \($0)…", bundle: .module) } ?? String(
                    localized: "Importing \(current) messages…",
                    bundle: .module
                ))
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
            }
        case .completed(let count, let errors):
            VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                SettingsInfoCallout(
                    symbolName: "checkmark.circle",
                    message: String(localized: "Imported \(count) message\(count == 1 ? "" : "s").", bundle: .module),
                    tone: .success
                )
                if !errors.isEmpty {
                    SettingsInfoCallout(
                        symbolName: "exclamationmark.triangle",
                        message: String(
                            localized: "\(errors.count) parse error\(errors.count == 1 ? "" : "s") encountered.",
                            bundle: .module
                        ),
                        tone: .warning
                    )
                }
            }
        case .failed(let reason):
            SettingsInfoCallout(
                symbolName: "xmark.circle",
                message: String(localized: "Import failed: \(reason)", bundle: .module),
                tone: .warning
            )
        }
    }

    private var exportGroup: some View {
        SettingsGroup(
            title: String(localized: "Export mail", bundle: .module),
            subtitle: String(
                localized: "Save the entire folder, including attachments. EML files are grouped in a new folder.",
                bundle: .module
            ),
            symbolName: "tray.and.arrow.up"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                if exportMailboxes.count > 1 {
                    Picker(String(localized: "Mailbox", bundle: .module), selection: $exportMailboxID) {
                        ForEach(exportMailboxes) { mailbox in
                            Text(mailbox.displayName.isEmpty ? mailbox.email : mailbox.displayName)
                                .tag(Mailbox.ID?.some(mailbox.id))
                        }
                    }
                }
                HStack(spacing: BrevSpacing.sm) {
                    Picker(String(localized: "Source folder", bundle: .module), selection: $exportFolderID) {
                        Text("Select folder…", bundle: .module).tag(Folder.ID?.none)
                        ForEach(exportFolders) { folder in
                            Text(folder.name).tag(Folder.ID?.some(folder.id))
                        }
                    }
                    .disabled(exportFolders.isEmpty || isLoadingExportFolders)
                    Button { exportReloadRevision &+= 1 } label: {
                        Image(systemName: "arrow.clockwise").modifier(ExportControlHitTarget())
                    }
                    .help(String(localized: "Refresh folders", bundle: .module))
                    .accessibilityLabel(String(localized: "Refresh export folders", bundle: .module))
                    .disabled(currentBackend == nil || isLoadingExportFolders || isImporting)
                }

                if isLoadingExportFolders {
                    progressRow(symbol: "folder", text: String(localized: "Loading folders…", bundle: .module))
                } else if let error = exportFolderError {
                    SettingsInfoCallout(symbolName: "exclamationmark.triangle", message: error, tone: .warning)
                    Button(String(localized: "Retry", bundle: .module)) { exportReloadRevision &+= 1 }
                } else if let backend = currentBackend, !backend.extendedCapabilities.contains(.rawMessageBytes) {
                    SettingsInfoCallout(symbolName: "info.circle",
                                        message: String(
                                            localized: "This account does not provide original message source for export.",
                                            bundle: .module
                                        ),
                                        tone: .info)
                } else if currentBackend == nil {
                    SettingsInfoCallout(symbolName: "person.crop.circle",
                                        message: String(localized: "Sign in to an account to export mail.", bundle: .module),
                                        tone: .info)
                }

                HStack(spacing: BrevSpacing.sm) {
                    Button { startExportMBOX() } label: {
                        Text("Export as MBOX…", bundle: .module).modifier(ExportControlHitTarget())
                    }
                    Button { startExportEML() } label: {
                        Text("Export as EML…", bundle: .module).modifier(ExportControlHitTarget())
                    }
                }
                .disabled(!canExport)
            }
        }
    }

    private var privacyNote: some View {
        SettingsInfoCallout(
            symbolName: "lock.shield",
            message: String(
                localized: "Files are processed locally. Import adds messages to a mailbox; provider accounts may upload them. Export may download missing originals from your mail provider.",
                bundle: .module
            ),
            tone: .info
        )
    }

    private func progressRow(symbol: String, text: String) -> some View {
        HStack(spacing: BrevSpacing.sm) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
        }
    }

    private var isImporting: Bool {
        switch importState {
        case .parsing, .importing: true
        default: false
        }
    }

    private var canImport: Bool {
        #if os(macOS)
        !isImporting && !exportController.isRunning && !isLoadingFolders
            && currentBackend?.extensionService(MailImporting.self) != nil
        #else
        false
        #endif
    }

    private var canExport: Bool {
        exportRequest != nil && !isImporting && !exportController.isRunning && !isLoadingExportFolders
    }

    private var selectedExportSourceID: MailSourceID? {
        guard let accountID = currentAccountID, let mailboxID = exportMailboxID else { return nil }
        return MailSourceID(accountID: accountID, mailboxID: mailboxID)
    }

    private struct AccountBackendIdentity: Equatable {
        let accountID: BrevAccount.ID
        let objectID: ObjectIdentifier
    }

    private struct ExportLoadKey: Equatable {
        let backend: AccountBackendIdentity?
        let revision: Int
    }

    private var exportBackendIdentity: AccountBackendIdentity? {
        currentBackend.map { AccountBackendIdentity(accountID: $0.account.id, objectID: ObjectIdentifier($0)) }
    }

    private var exportRequest: (exporter: MailFolderExporter, title: String, folder: Folder,
                                sessionToken: MailFolderExportSessionToken)? {
        guard let source = selectedExportSourceID, loadedExportSourceID == source,
              let folder = exportFolders.first(where: { $0.id == exportFolderID }),
              let backend = currentBackend, backend.extendedCapabilities.contains(.rawMessageBytes) else { return nil }
        let mailbox = exportMailboxes.first { $0.id == source.mailboxID }
        let title = "\(folder.name) · \(mailbox?.displayName ?? backend.account.emailAddress)"
        return (
            MailFolderExporter(backend: backend, sourceID: source, folder: folder),
            title,
            folder,
            exportController.sessionToken
        )
    }

    private func loadExportMailboxes() async {
        let preferred = exportMailboxAccountID == currentAccountID ? exportMailboxID : nil
        exportMailboxes = []
        exportMailboxID = nil
        exportFolders = []
        exportFolderID = nil
        loadedExportSourceID = nil
        exportFolderError = nil
        isLoadingExportFolders = true
        guard let backend = currentBackend else {
            isLoadingExportFolders = false
            return
        }
        do {
            let mailboxes = try await backend.mailboxes()
            let current = try await backend.currentMailbox()
            guard !Task.isCancelled else { return }
            exportMailboxes = mailboxes
            exportMailboxAccountID = currentAccountID
            exportMailboxID = mailboxes.first { $0.id == preferred }?.id
                ?? mailboxes.first { $0.id == current.id }?.id ?? mailboxes.first?.id
            if exportMailboxID == nil {
                exportFolderError = String(localized: "No mailboxes are available for this account.", bundle: .module)
            }
        } catch {
            guard !Task.isCancelled else { return }
            exportFolderError = error.localizedDescription
        }
        isLoadingExportFolders = false
    }

    private func loadExportFolders() async {
        guard !Task.isCancelled else { return }
        exportFolders = []
        exportFolderID = nil
        loadedExportSourceID = nil
        guard let source = selectedExportSourceID, let backend = currentBackend else { return }
        isLoadingExportFolders = true
        exportFolderError = nil
        do {
            let loaded: [Folder]
            if loadedImportSourceID == source {
                loaded = allFolders
            } else {
                loaded = try await backend.folders(in: source)
            }
            guard !Task.isCancelled else { return }
            exportFolders = loaded
            loadedExportSourceID = source
            if loaded.isEmpty {
                exportFolderError = String(localized: "No folders are available in this mailbox.", bundle: .module)
            }
        } catch {
            guard !Task.isCancelled else { return }
            exportFolderError = error.localizedDescription
        }
        isLoadingExportFolders = false
    }

    private var currentBackend: (any MailBackend)? {
        guard let accountID = currentAccountID else { return nil }
        return backendProvider(accountID)
    }

    // MARK: - Import actions

    private func startImportMBOX() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title = String(localized: "Select MBOX File", bundle: .module)
        panel.allowedContentTypes = [UTType.data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await performMBOXImport(url: url)
        }
        #endif
    }

    private func startImportMaildir() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title = String(localized: "Select Maildir Folder", bundle: .module)
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await performMaildirImport(url: url)
        }
        #endif
    }

    private func performMBOXImport(url: URL) async {
        importState = .parsing
        let parser = MBOXParser()
        await importStreaming(sourceName: "file") { batchSize, onBatch in
            try await parser.parseBatches(
                contentsOf: url,
                batchSize: batchSize,
                onBatch: onBatch
            )
        }
    }

    private func performMaildirImport(url: URL) async {
        importState = .parsing
        let reader = MaildirReader()
        await importStreaming(sourceName: "Maildir") { batchSize, onBatch in
            try await reader.readBatches(
                contentsOf: url,
                batchSize: batchSize,
                onBatch: onBatch
            )
        }
    }

    private func importStreaming(
        sourceName: String,
        readBatches: (
            _ batchSize: Int,
            _ onBatch: @escaping ([ImportedMessage]) async throws -> Void
        ) async throws -> MailImportStreamSummary
    ) async {
        do {
            var importTarget: (importer: any MailImporting, folder: Folder)?
            var importedCount = 0
            var importErrors: [String] = []

            importState = .importing(current: 0, total: nil)
            let parseSummary = try await readBatches(100) { batch in
                if importTarget == nil {
                    importTarget = try await resolveImportTarget()
                }
                guard let target = importTarget else {
                    throw ImportExportOperationError.noImportTarget
                }

                let summary = try await target.importer.importMessages(batch, into: target.folder)
                importedCount += summary.importedCount
                importErrors.append(contentsOf: summary.errors)
                importState = .importing(current: importedCount, total: nil)
            }

            guard parseSummary.messageCount > 0 else {
                importState = .failed(String(localized: "No messages found in \(sourceName).", bundle: .module))
                return
            }

            importState = .completed(
                count: importedCount,
                errors: parseSummary.parseErrors + importErrors
            )
        } catch {
            importState = .failed(error.localizedDescription)
        }
    }

    private func resolveImportTarget() async throws -> (importer: any MailImporting, folder: Folder) {
        guard let backend = currentBackend else {
            throw ImportExportOperationError.noSignedInAccount
        }
        guard let importer = backend.extensionService(MailImporting.self) else {
            throw ImportExportOperationError.importNotSupported
        }

        if importDestination == .newFolder {
            let timestamp = DateFormatter.localizedString(
                from: Date(),
                dateStyle: .short,
                timeStyle: .short
            )
            let folder = try await backend.createFolder(
                name: String(localized: "Imported \(timestamp)", bundle: .module),
                parentID: nil
            )
            return (importer, folder)
        }

        guard let targetID = selectedFolderID,
              let target = allFolders.first(where: { $0.id == targetID }) else {
            throw ImportExportOperationError.noDestinationFolder
        }
        return (importer, target)
    }

    // MARK: - Export actions

    private func startExportMBOX() {
        #if os(macOS)
        guard canExport, let request = exportRequest else { return }
        let panel = NSSavePanel()
        panel.title = String(localized: "Export as MBOX", bundle: .module)
        panel.message = String(localized: "Export every message from \(request.title).", bundle: .module)
        panel.nameFieldStringValue = MailFolderExporter.suggestedArchiveName(for: request.folder.name)
        panel.allowedContentTypes = [.mboxArchive]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exportController.start(
            request.exporter,
            to: url,
            format: .mbox,
            sourceTitle: request.title,
            sessionToken: request.sessionToken
        )
        #elseif os(iOS)
        chooseMobileExportFolder(format: .mbox)
        #endif
    }

    private func startExportEML() {
        #if os(macOS)
        guard canExport, let request = exportRequest else { return }
        let panel = NSOpenPanel()
        panel.title = String(localized: "Select Destination Folder for EML Files", bundle: .module)
        panel.message = String(
            localized: "A new folder will contain the exported messages from \(request.title).",
            bundle: .module
        )
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exportController.start(
            request.exporter,
            to: url,
            format: .emlDirectory,
            sourceTitle: request.title,
            sessionToken: request.sessionToken
        )
        #elseif os(iOS)
        chooseMobileExportFolder(format: .emlDirectory)
        #endif
    }

    #if os(iOS)
    private func chooseMobileExportFolder(format: MailFolderExportFormat) {
        guard canExport, let request = exportRequest else { return }
        mobileExportRequest = MobileExportRequest(exporter: request.exporter, title: request.title,
                                                  folderName: request.folder.name, format: format,
                                                  sessionToken: request.sessionToken)
        isChoosingExportFolder = true
    }
    #endif
}

#if os(macOS)
private extension UTType {
    static let mboxArchive = UTType(filenameExtension: "mbox") ?? .data
}
#endif

private enum ImportExportOperationError: Error, LocalizedError {
    case noSignedInAccount
    case importNotSupported
    case noDestinationFolder
    case noImportTarget

    var errorDescription: String? {
        switch self {
        case .noSignedInAccount:
            String(localized: "No account is signed in.", bundle: .module)
        case .importNotSupported:
            String(localized: "This account does not support importing messages yet.", bundle: .module)
        case .noDestinationFolder:
            String(localized: "Select a destination folder.", bundle: .module)
        case .noImportTarget:
            String(localized: "Import destination could not be prepared.", bundle: .module)
        }
    }
}
