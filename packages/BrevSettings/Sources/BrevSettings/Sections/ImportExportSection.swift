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
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
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

    @State private var allFolders: [Folder]
    @State private var isLoadingFolders = false
    @State private var folderLoadErrorMessage: String?
    @State private var importState: ImportState = .idle
    @State private var exportState: ExportState = .idle
    @State private var selectedFolderID: Folder.ID?
    @State private var importDestination: ImportDestination = .newFolder

    enum ImportState: Equatable {
        case idle
        case parsing
        case importing(current: Int, total: Int?)
        case completed(count: Int, errors: [String])
        case failed(String)
    }

    enum ExportState: Equatable {
        case idle
        case exporting(current: Int, total: Int)
        case completed(count: Int)
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
        allFolders: [Folder] = []
    ) {
        self.backendProvider = backendProvider
        self.accounts = accounts
        self.currentAccountID = currentAccountID
        _allFolders = State(initialValue: allFolders)
    }

    var body: some View {
        SectionScaffold(
            title: String(localized: "Import / Export", bundle: .module),
            subtitle: String(localized: "Move mail in and out of Brev. All processing stays on your Mac.", bundle: .module)
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
        .task(id: currentAccountID) { await loadFolders() }
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
        do {
            let mailbox = try await backend.currentMailbox()
            allFolders = try await backend.folders(in: backend.sourceID(for: mailbox))
        } catch {
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
            subtitle: String(localized: "Export messages to MBOX or individual EML files.", bundle: .module),
            symbolName: "tray.and.arrow.up"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                Picker(String(localized: "Source folder", bundle: .module), selection: $selectedFolderID) {
                    Text("Select folder…", bundle: .module).tag(Folder.ID?.none)
                    ForEach(allFolders) { folder in
                        Text(folder.name).tag(Folder.ID?.some(folder.id))
                    }
                }
                .disabled(allFolders.isEmpty)

                folderStatusView

                HStack(spacing: BrevSpacing.sm) {
                    Button(String(localized: "Export as MBOX…", bundle: .module)) {
                        startExportMBOX()
                    }
                    .disabled(!canExport)

                    Button(String(localized: "Export as EML…", bundle: .module)) {
                        startExportEML()
                    }
                    .disabled(!canExport)
                }

                exportProgressView
            }
        }
    }

    @ViewBuilder
    private var exportProgressView: some View {
        switch exportState {
        case .idle:
            EmptyView()
        case .exporting(let current, let total):
            VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                ProgressView(value: Double(current), total: Double(total))
                    .tint(theme.accent.color)
                Text("Exporting \(current) of \(total)…", bundle: .module)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
            }
        case .completed(let count):
            SettingsInfoCallout(
                symbolName: "checkmark.circle",
                message: String(localized: "Exported \(count) message\(count == 1 ? "" : "s").", bundle: .module),
                tone: .success
            )
        case .failed(let reason):
            SettingsInfoCallout(
                symbolName: "xmark.circle",
                message: String(localized: "Export failed: \(reason)", bundle: .module),
                tone: .warning
            )
        }
    }

    private var privacyNote: some View {
        SettingsInfoCallout(
            symbolName: "lock.shield",
            message: String(
                localized: "Import and export run entirely on your Mac. No data leaves your device, and no network calls are made.",
                bundle: .module
            ),
            tone: .success
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

    private var canImport: Bool {
        guard case .idle = importState else { return false }
        guard case .exporting = exportState else { return true }
        return false
    }

    private var canExport: Bool {
        guard selectedFolderID != nil else { return false }
        guard case .idle = exportState else { return false }
        guard case .importing = importState else { return true }
        return false
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
        let panel = NSSavePanel()
        panel.title = String(localized: "Export as MBOX", bundle: .module)
        panel.nameFieldStringValue = "export.mbox"
        panel.allowedContentTypes = [UTType.data]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await performMBOXExport(to: url)
        }
        #endif
    }

    private func startExportEML() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title = String(localized: "Select Destination Folder for EML Files", bundle: .module)
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await performEMLEXport(to: url)
        }
        #endif
    }

    private func performMBOXExport(to url: URL) async {
        guard let folderID = selectedFolderID,
              let folder = allFolders.first(where: { $0.id == folderID }) else {
            exportState = .failed(String(localized: "Select a folder to export.", bundle: .module))
            return
        }

        guard let backend = currentBackend else {
            exportState = .failed(String(localized: "No account is signed in.", bundle: .module))
            return
        }

        do {
            // Exporting enumerates a folder in bulk; don't move the IDLE target.
            // enumerateMessages is paginated, so loop until the folder is
            // exhausted — otherwise a large mailbox exports only its first page
            // and silently drops the rest (the count would still report success).
            let headers = try await allHeaders(in: folder, from: backend)
            let total = headers.count
            exportState = .exporting(current: 0, total: total)

            let exporter = MBOXExporter()
            _ = FileManager.default.createFile(atPath: url.path, contents: nil)
            guard let handle = try? FileHandle(forWritingTo: url) else {
                throw MailExportError.cannotOpenFile(url.lastPathComponent)
            }
            defer { try? handle.close() }

            for (index, header) in headers.enumerated() {
                let body = try await backend.body(for: header.id)
                let raw = buildRawMessage(header: header, body: body)
                let msg = ImportedMessage(
                    headers: headerToTuples(header),
                    bodyData: raw
                )
                try exporter.append(message: msg, to: handle)
                exportState = .exporting(current: index + 1, total: total)
            }

            exportState = .completed(count: total)
        } catch {
            exportState = .failed(error.localizedDescription)
        }
    }

    private func performEMLEXport(to directoryURL: URL) async {
        guard let folderID = selectedFolderID,
              let folder = allFolders.first(where: { $0.id == folderID }) else {
            exportState = .failed(String(localized: "Select a folder to export.", bundle: .module))
            return
        }

        guard let backend = currentBackend else {
            exportState = .failed(String(localized: "No account is signed in.", bundle: .module))
            return
        }

        do {
            // Exporting enumerates a folder in bulk; don't move the IDLE target.
            // Paginate to completion (see performMBOXExport) so a large mailbox
            // isn't silently truncated to its first page.
            let headers = try await allHeaders(in: folder, from: backend)
            let total = headers.count
            exportState = .exporting(current: 0, total: total)

            let exporter = MBOXExporter()
            // Two messages whose subjects sanitize to the same string would write
            // to the same path and overwrite each other (silent data loss). Track
            // used names and uniquify, case-insensitively for case-folding volumes.
            var usedFilenames: Set<String> = []
            for (index, header) in headers.enumerated() {
                let body = try await backend.body(for: header.id)
                // `exportToEML` writes the headers itself (from `headers`), then a
                // blank line, then `bodyData`. Pass the BODY ONLY here — passing a
                // full raw message (headers+body) would emit the header block twice
                // and produce a malformed .eml.
                let msg = ImportedMessage(
                    headers: headerToTuples(header),
                    bodyData: Data((body.plainText ?? body.html ?? "").utf8)
                )
                let base = MailExportFilename.sanitize(header.subject.isEmpty ? "message-\(index + 1)" : header.subject)
                let filename = MailExportFilename.unique(base, ext: "eml", used: &usedFilenames)
                let fileURL = directoryURL.appendingPathComponent(filename)
                try exporter.exportToEML(message: msg, to: fileURL)
                exportState = .exporting(current: index + 1, total: total)
            }

            exportState = .completed(count: total)
        } catch {
            exportState = .failed(error.localizedDescription)
        }
    }

    /// Enumerates every header in `folder`, following `enumerateMessages`'
    /// pagination to the end. The export feature is a backup/migration surface,
    /// so it must never silently stop at the first page.
    private func allHeaders(
        in folder: Folder,
        from backend: any MailBackend
    ) async throws -> [MessageHeader] {
        var headers: [MessageHeader] = []
        var pageToken: String?
        while true {
            let (page, next) = try await backend.enumerateMessages(in: folder, pageToken: pageToken)
            headers += page
            guard let next, !page.isEmpty else { break }
            pageToken = next
        }
        return headers
    }

    /// Returns `base.ext`, appending a ` (n)` counter before the extension until
    private func buildRawMessage(header: MessageHeader, body: MessageBody) -> Data {
        var result = Data()
        for (name, value) in headerToTuples(header) {
            if let line = "\(name): \(value)\n".data(using: .utf8) {
                result.append(line)
            }
        }
        result.append("\n".data(using: .utf8)!)
        if let textBody = body.plainText {
            result.append(Data(textBody.utf8))
        } else if let htmlBody = body.html {
            result.append(Data(htmlBody.utf8))
        }
        return result
    }

    private func headerToTuples(_ header: MessageHeader) -> [(name: String, value: String)] {
        var tuples: [(String, String)] = []
        tuples.append(("From", correspondentString(header.from)))
        tuples.append(("To", header.to.map(correspondentString).joined(separator: ", ")))
        tuples.append(("Subject", header.subject))
        tuples.append(("Date", formatDate(header.date)))
        if !header.cc.isEmpty {
            tuples.append(("Cc", header.cc.map(correspondentString).joined(separator: ", ")))
        }
        tuples.append(("Message-ID", header.id))
        return tuples
    }

    private func correspondentString(_ c: Correspondent) -> String {
        if let name = c.name, !name.isEmpty {
            return "\(name) <\(c.email)>"
        }
        return c.email
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}

/// Filename derivation for the per-message `.eml` export. Extracted so the
/// sanitize + collision-uniquify rules can be unit-tested without the View.
enum MailExportFilename {
    /// Replaces filesystem-significant characters with `_`. Note this maps `/`
    /// and `\` away, so a crafted subject can't introduce path separators.
    static func sanitize(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return name.components(separatedBy: invalid).joined(separator: "_")
    }

    /// Returns `base.ext`, appending a ` (n)` counter before the extension until
    /// the name is unique within `used` (compared case-insensitively so a
    /// case-folding filesystem can't still collide). Falls back to a safe stem
    /// when `base` is empty/blank or a dot-only name, so two same-subject
    /// messages never overwrite each other.
    static func unique(_ base: String, ext: String, used: inout Set<String>) -> String {
        let stem = base.trimmingCharacters(in: .whitespaces).isEmpty || base.allSatisfy { $0 == "." }
            ? "message"
            : base
        var candidate = "\(stem).\(ext)"
        var counter = 2
        while used.contains(candidate.lowercased()) {
            candidate = "\(stem) (\(counter)).\(ext)"
            counter += 1
        }
        used.insert(candidate.lowercased())
        return candidate
    }
}

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
