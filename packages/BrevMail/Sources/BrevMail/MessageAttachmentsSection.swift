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
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

/// Which of a thread message's attachments get their own card. Inline CID
/// images already render in the body and the calendar invite has its own
/// card, so listing them again would double them up.
enum ThreadMessageAttachmentListPolicy {
    /// The attachments to list under an expanded thread message, in order.
    static func listed(_ attachments: [Attachment]) -> [Attachment] {
        let invite = attachments.first(where: ThreadCalendarInvitePresentation.isCalendarInviteAttachment)
        return attachments.filter { attachment in
            if attachment.id == invite?.id { return false }
            // Only images are drawn in the body from a CID; any other inline
            // part would otherwise show nowhere.
            if attachment.isInline, attachment.contentID?.isEmpty == false,
               attachment.mimeType.lowercased().hasPrefix("image/") {
                return false
            }
            return true
        }
    }
}

/// An attachment staged for the save-to-Drive sheet (#14) — bytes are
/// already on disk locally, so the sheet can upload without re-reading
/// the message.
struct PendingDriveSave: Identifiable {
    let id = UUID()
    let payload: GoogleDriveStagedPayload
}

/// Runs the attachment actions (preview, save, open, Save All, drag out,
/// stage for Drive) for one reader surface and holds their state. The
/// single-message reader and each thread message card own one, so both
/// share one download path and one set of rules.
@MainActor
final class MessageAttachmentController: ObservableObject {
    /// What a download needs from the owning view, read when it starts.
    struct Context {
        let messageID: MessageHeader.ID
        let sourceID: MailSourceID?
        let isWorkBlocked: Bool
        /// Fetches the attachment bytes through the backend.
        let download: @Sendable (Attachment) async throws -> Data
        /// The message the owner shows now; a reply for another is dropped.
        let currentSelection: @MainActor () -> (sourceID: MailSourceID?, messageID: MessageHeader.ID?)
    }

    @Published var downloadingAttachmentID: String?
    @Published private(set) var isSavingAll = false
    @Published var error: MessageDetailInlineStatus?
    @Published var saveToast: String?
    @Published var quickLookURL: URL?
    @Published var pendingDriveSave: PendingDriveSave?

    private var activeRequest: MessageAttachmentDownloadRequest?
    private var downloadedURLs: [String: URL] = [:]

    /// Whether any download or Save All is running.
    var isBusy: Bool { downloadingAttachmentID != nil || isSavingAll }

    /// Drops the in-flight download so its reply is ignored (message change).
    func cancelActiveDownload() {
        activeRequest = nil
    }

    /// Runs one card action.
    func run(_ action: MessageAttachmentActionKind, attachment: Attachment, context: Context) async {
        switch action {
        case .preview:
            await preview(attachment, context: context)
        case .save:
            await save(attachment, context: context)
        case .open:
            await openWithSystemApp(attachment, context: context)
        case .saveToDrive:
            await stageForDrive(attachment, context: context)
        }
    }

    /// Stages the attachment bytes and presents the save-to-Drive
    /// sheet (opt-in → folder pick → conflict choice → upload).
    private func stageForDrive(_ attachment: Attachment, context: Context) async {
        do {
            let url = try await downloadFile(attachment, purpose: .savePanelStaging, context: context)
            let data = try Data(contentsOf: url)
            let payload = GoogleDriveStagedPayload()
            payload.stage(
                filename: attachment.name,
                mimeType: attachment.mimeType.isEmpty
                    ? "application/octet-stream"
                    : attachment.mimeType,
                bytes: data
            )
            pendingDriveSave?.payload.clear()
            pendingDriveSave = PendingDriveSave(payload: payload)
        } catch {
            // Error is already surfaced by the helper.
        }
    }

    /// Save the attachment to a user-selected destination.
    private func save(_ attachment: Attachment, context: Context) async {
        do {
            let url = try await downloadFile(attachment, purpose: .savePanelStaging, context: context)
            #if canImport(AppKit)
            guard try Self.saveAs(url: url, suggestedName: attachment.name) != nil else {
                return
            }
            #endif
            saveToast = "Saved \"\(MessageDetailPresentation.attachmentDisplayName(attachment.name))\""
        } catch {
            // Error is already surfaced by the helper.
        }
    }

    /// Open the attachment inline using QuickLook / system preview.
    private func preview(_ attachment: Attachment, context: Context) async {
        do {
            quickLookURL = try await downloadedURL(for: attachment, context: context)
        } catch {
            // Error is already surfaced by the helper.
        }
    }

    /// Open the attachment with the system-default application.
    ///
    /// On macOS this calls `NSWorkspace.shared.open(_:)` after writing
    /// the file to a temporary directory. On iOS the URL is surfaced
    /// through QuickLook (a proper share-sheet is a follow-up task).
    private func openWithSystemApp(_ attachment: Attachment, context: Context) async {
        do {
            let url = try await downloadedURL(for: attachment, context: context)
            #if canImport(AppKit)
            _ = NSWorkspace.shared.open(url)
            #else
            quickLookURL = url
            #endif
        } catch {
            // Error is already surfaced by the helper.
        }
    }

    private func downloadedURL(for attachment: Attachment, context: Context) async throws -> URL {
        if let url = MessageAttachmentDownloadedFilePolicy.reusableCachedURL(
            downloadedURLs[attachment.id],
            fileExists: { FileManager.default.fileExists(atPath: $0.path) }
        ) {
            return url
        }
        return try await downloadFile(attachment, purpose: .previewOrOpen, context: context)
    }

    private func downloadFile(
        _ attachment: Attachment,
        purpose: MessageAttachmentDownloadStoragePurpose,
        context: Context
    ) async throws -> URL {
        guard MessageAttachmentDownloadStartPolicy.canStartDownload(
            activeRequest: activeRequest,
            isBlocked: context.isWorkBlocked
        ),
            attachment.resource != nil
        else {
            throw CancellationError()
        }
        let request = MessageAttachmentDownloadRequest(
            messageID: context.messageID,
            sourceID: context.sourceID,
            attachmentID: attachment.id
        )
        activeRequest = request
        downloadingAttachmentID = attachment.id
        error = nil
        do {
            let data = try await context.download(attachment)
            guard canApply(request, context: context) else {
                throw CancellationError()
            }
            let url = try Self.stage(data: data, suggestedName: attachment.name, purpose: purpose)
            guard canApply(request, context: context) else {
                throw CancellationError()
            }
            downloadedURLs[attachment.id] = url
            finish(request)
            return url
        } catch is CancellationError {
            if canApply(request, context: context) {
                finish(request)
            }
        } catch {
            if canApply(request, context: context) {
                self.error = MessageDetailPresentation.attachmentDownloadErrorStatus(
                    filename: attachment.name,
                    error: error
                )
                finish(request)
            }
        }
        throw CancellationError()
    }

    private func canApply(_ request: MessageAttachmentDownloadRequest, context: Context) -> Bool {
        let current = context.currentSelection()
        return MessageAttachmentDownloadResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: activeRequest,
            currentSourceID: current.sourceID,
            currentMessageID: current.messageID
        )
    }

    private func finish(_ request: MessageAttachmentDownloadRequest) {
        guard activeRequest == request else { return }
        activeRequest = nil
        downloadingAttachmentID = nil
    }

    /// Stage attachment bytes in app-owned temporary storage. Explicit
    /// Save on macOS copies from this staging file through `NSSavePanel`,
    /// which grants the sandbox permission for the user-selected destination.
    private static func stage(
        data: Data,
        suggestedName: String,
        purpose: MessageAttachmentDownloadStoragePurpose
    ) throws -> URL {
        let sanitized = MessageAttachmentDownloadFilenamePolicy.safeFilename(
            suggestedName: suggestedName
        )
        let directory = MessageAttachmentDownloadStoragePolicy.directory(
            purpose: purpose,
            temporaryDirectory: FileManager.default.temporaryDirectory
        )
        let filename = MessageAttachmentDownloadFilenamePolicy.uniqueFilename(
            baseName: sanitized
        ) { candidate in
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(candidate).path
            )
        }
        let destination = directory.appendingPathComponent(filename)
        try data.write(to: destination, options: .atomic)
        return destination
    }

    #if os(macOS)
    /// Builds the drag payload for an attachment card. The bytes are fetched
    /// lazily through the same backend download path as Save and Open, only
    /// when a drop target asks for the file, and written off the main actor to
    /// a per-drag folder so the receiver sees the original filename.
    func dragProvider(for attachment: Attachment, context: Context) -> NSItemProvider {
        let filename = MessageAttachmentDownloadFilenamePolicy.safeFilename(
            suggestedName: attachment.name
        )
        let pathExtension = (filename as NSString).pathExtension
        let contentType = UTType(filenameExtension: pathExtension)
            ?? UTType(mimeType: attachment.mimeType)
            ?? .data
        let provider = NSItemProvider()
        provider.suggestedName = (filename as NSString).deletingPathExtension
        let download = context.download
        provider.registerFileRepresentation(
            forTypeIdentifier: contentType.identifier,
            fileOptions: [],
            visibility: .all
        ) { [weak self] completion in
            Task.detached(priority: .userInitiated) {
                do {
                    let data = try await download(attachment)
                    MessageAttachmentExportPolicy.pruneStaleDragStaging()
                    let url = try MessageAttachmentExportPolicy.stageForDrag(
                        data: data,
                        filename: filename
                    )
                    completion(url, false, nil)
                } catch {
                    completion(nil, false, error)
                    await MainActor.run {
                        self?.error = MessageDetailPresentation.attachmentDownloadErrorStatus(
                            filename: attachment.name,
                            error: error
                        )
                    }
                }
            }
            return nil
        }
        return provider
    }

    /// Saves every downloadable attachment into a folder the user picks.
    /// Each file goes through the same download-and-stage path as a single
    /// Save, then is copied under a sanitized, non-colliding name so nothing
    /// in the folder is overwritten.
    func saveAll(_ attachments: [Attachment], context: Context) async {
        let items = MessageAttachmentExportPolicy.exportable(attachments)
        guard items.count >= 2, !isSavingAll, let folder = Self.chooseSaveAllFolder() else {
            return
        }
        isSavingAll = true
        defer { isSavingAll = false }
        let names = MessageAttachmentExportPolicy.destinationNames(for: items) { candidate in
            FileManager.default.fileExists(atPath: folder.appendingPathComponent(candidate).path)
        }
        var savedCount = 0
        for (attachment, name) in zip(items, names) {
            do {
                let staged = try await downloadedURL(for: attachment, context: context)
                let destination = folder.appendingPathComponent(name)
                try await Task.detached(priority: .userInitiated) {
                    try FileManager.default.copyItem(at: staged, to: destination)
                }.value
                savedCount += 1
            } catch is CancellationError {
                // The download helper already surfaced any error; stop the batch.
                break
            } catch {
                self.error = MessageDetailPresentation.attachmentDownloadErrorStatus(
                    filename: attachment.name,
                    error: error
                )
                break
            }
        }
        if savedCount == items.count {
            saveToast = String(
                localized: "Saved \(savedCount) attachments",
                bundle: .module
            )
        } else if savedCount > 0 {
            saveToast = String(
                localized: "Saved \(savedCount) of \(items.count) attachments",
                bundle: .module
            )
        }
    }

    /// Asks the user for the destination folder of Save All.
    private static func chooseSaveAllFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Save", bundle: .module)
        panel.message = String(localized: "Choose a folder for the attachments", bundle: .module)
        panel.directoryURL = FileManager.default.urls(
            for: .downloadsDirectory,
            in: .userDomainMask
        ).first
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
    #endif

    #if canImport(AppKit)
    private static func saveAs(url: URL, suggestedName: String) throws -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = MessageAttachmentDownloadFilenamePolicy.safeFilename(
            suggestedName: suggestedName
        )
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(
            for: .downloadsDirectory,
            in: .userDomainMask
        ).first
        guard panel.runModal() == .OK, let destination = panel.url else {
            return nil
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }
    #endif
}

/// The attachments block of one message: the count with Save All, the
/// attachments as cards in an adaptive grid (macOS) or rows (iOS), and the
/// inline error and save toast. Used by the single-message reader and by
/// each expanded thread message card.
struct MessageAttachmentsSection: View {
    let attachments: [Attachment]
    @ObservedObject var controller: MessageAttachmentController
    let context: MessageAttachmentController.Context
    /// Whether the Save-to-Drive action is offered (opt-in feature, #14).
    let driveAvailable: Bool

    @Environment(\.brevTheme) private var theme
    /// The attachment card under the pointer (macOS hover highlight).
    @State private var hoveredAttachmentID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            HStack(spacing: BrevSpacing.sm) {
                Text(MessageAttachmentCountLabel.title(count: attachments.count))
                    .brevFont(.caption)
                    .foregroundStyle(theme.textTertiary.color)
                #if os(macOS)
                if MessageAttachmentExportPolicy.showsSaveAll(for: attachments) {
                    Spacer(minLength: BrevSpacing.sm)
                    Button {
                        Task { await controller.saveAll(attachments, context: context) }
                    } label: {
                        Text("Save All…", bundle: .module)
                            .brevFont(.caption)
                    }
                    .buttonStyle(.borderless)
                    .disabled(MessageAttachmentExportPolicy.isSaveAllDisabled(
                        isDownloading: controller.isBusy,
                        isWorkBlocked: context.isWorkBlocked
                    ))
                    .accessibilityLabel(String(localized: "Save all attachments", bundle: .module))
                }
                #endif
            }
            #if os(macOS)
            // #306 slice 4: attachments as cards in an adaptive grid.
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: BrevSpacing.sm)],
                alignment: .leading,
                spacing: BrevSpacing.sm
            ) {
                ForEach(attachments) { attachment in
                    let actions = actions(for: attachment)
                    let displayName = MessageDetailPresentation.attachmentDisplayName(attachment.name)
                    rowInteractions(
                        MessageAttachmentCard(
                            name: displayName,
                            systemImage: Self.fileTypeSymbol(for: attachment.name),
                            subtitle: MessageAttachmentCardPresentation.subtitle(
                                filename: displayName,
                                sizeText: Self.formatSize(attachment.sizeBytes)
                            ),
                            isHovered: hoveredAttachmentID == attachment.id,
                            isDownloading: controller.downloadingAttachmentID == attachment.id,
                            primaryAction: MessageAttachmentActionPresentation.primaryAction(in: actions),
                            overflowActions: MessageAttachmentActionPresentation.overflowActions(in: actions),
                            onAction: { kind in run(kind, attachment) }
                        ),
                        attachment: attachment,
                        actions: actions
                    )
                }
            }
            #else
            ForEach(attachments) { attachment in
                let actions = actions(for: attachment)
                HStack(spacing: BrevSpacing.sm) {
                    Image(systemName: Self.fileTypeSymbol(for: attachment.name))
                        .foregroundStyle(theme.textSecondary.color)
                    Text(MessageDetailPresentation.attachmentDisplayName(attachment.name))
                        .brevFont(.footnote)
                        .foregroundStyle(theme.textPrimary.color)
                        .lineLimit(1)
                    Text(Self.formatSize(attachment.sizeBytes))
                        .brevFont(.caption)
                        .foregroundStyle(theme.textTertiary.color)
                    Spacer(minLength: BrevSpacing.sm)
                    if controller.downloadingAttachmentID == attachment.id {
                        ProgressView()
                            .controlSize(.small)
                    } else if let primaryAction = MessageAttachmentActionPresentation.primaryAction(in: actions) {
                        Button {
                            run(primaryAction.kind, attachment)
                        } label: {
                            Image(systemName: primaryAction.systemImage)
                        }
                        .buttonStyle(.borderless)
                        .disabled(primaryAction.isDisabled)
                        .accessibilityLabel(primaryAction.title)
                    }
                    Menu {
                        ForEach(MessageAttachmentActionPresentation.overflowActions(in: actions)) { action in
                            Button {
                                run(action.kind, attachment)
                            } label: {
                                Label(action.title, systemImage: action.systemImage)
                            }
                            .disabled(action.isDisabled)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .accessibilityLabel(String(localized: "More attachment actions", bundle: .module))
                }
                .padding(.vertical, BrevSpacing.xxs)
                if attachment.id != attachments.last?.id {
                    BrevDivider()
                }
            }
            #endif
            if let error = controller.error {
                BrevInlineStatus(
                    message: error.message,
                    tone: error.tone.inlineStatusTone,
                    onDismiss: error.isDismissible ? { controller.error = nil } : nil,
                    lineLimit: error.lineLimit
                )
            }
            if let saveToast = controller.saveToast {
                BrevToast(
                    message: saveToast,
                    tone: .success,
                    actionTitle: nil,
                    onAction: nil
                ) {
                    controller.saveToast = nil
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func run(_ kind: MessageAttachmentActionKind, _ attachment: Attachment) {
        Task { await controller.run(kind, attachment: attachment, context: context) }
    }

    /// The capability-gated actions for one attachment.
    private func actions(for attachment: Attachment) -> [MessageAttachmentActionPresentation] {
        MessageAttachmentActionPresentation.actions(
            resourceAvailable: attachment.resource != nil,
            isDownloading: controller.downloadingAttachmentID != nil,
            isWorkBlocked: context.isWorkBlocked,
            driveAvailable: driveAvailable
        )
    }

    #if os(macOS)
    /// Wraps an attachment card with the macOS pointer interactions: hover
    /// tracking (the card draws the highlight), filename + size tooltip,
    /// double-click to open, and drag-out to Finder or another app.
    @ViewBuilder
    private func rowInteractions(
        _ row: some View,
        attachment: Attachment,
        actions: [MessageAttachmentActionPresentation]
    ) -> some View {
        let openAction = actions.first { $0.kind == .open }
        let interactive = row
            .contentShape(RoundedRectangle(cornerRadius: BrevRadius.md, style: .continuous))
            .onHover { hovering in
                if hovering {
                    hoveredAttachmentID = attachment.id
                } else if hoveredAttachmentID == attachment.id {
                    hoveredAttachmentID = nil
                }
            }
            .help(MessageAttachmentExportPolicy.helpText(for: attachment))
            .onTapGesture(count: 2) {
                guard let openAction, !openAction.isDisabled else { return }
                run(.open, attachment)
            }
        if MessageAttachmentExportPolicy.canDrag(attachment, isWorkBlocked: context.isWorkBlocked) {
            interactive.onDrag { controller.dragProvider(for: attachment, context: context) }
        } else {
            interactive
        }
    }
    #endif

    static func formatSize(_ bytes: Int) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(bytes),
            countStyle: .file
        )
    }

    /// Returns an SF Symbol name appropriate for the attachment's file
    /// type, using `UTType` when available and falling back to `paperclip`.
    static func fileTypeSymbol(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return "paperclip" }
        if let utType = UTType(filenameExtension: ext) {
            if utType.conforms(to: .image) { return "photo" }
            if utType.conforms(to: .movie) { return "film" }
            if utType.conforms(to: .audio) { return "music.note" }
            if utType.conforms(to: .pdf) { return "doc.richtext" }
            if utType.conforms(to: .spreadsheet) { return "tablecells" }
            if utType.conforms(to: .presentation) { return "rectangle.on.rectangle" }
            if utType.conforms(to: .zip) || utType.conforms(to: .archive) { return "archivebox" }
            if utType.conforms(to: .sourceCode) { return "chevron.left.forwardslash.chevron.right" }
            if utType.conforms(to: .plainText) { return "doc.plaintext" }
        }
        return "paperclip"
    }
}
