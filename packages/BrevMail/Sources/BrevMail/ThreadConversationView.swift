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
import BrevAvatars
import BrevBackend
import BrevDesign
import BrevSettings
import BrevThemes
import SwiftUI
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

/// Reading pane for a multi-message thread.
///
/// Renders all messages in the thread as stacked `ThreadMessageCard`s,
/// oldest first, with the newest card auto-expanded. Each card loads its
/// body lazily on first expansion.
///
/// Use `BrevMailRootView` to switch between this view and `MessageDetailView`
/// based on `backend.groupsMessagesIntoThreads` and thread size.
@MainActor
public struct ThreadConversationView: View {
    @Environment(\.readerCommandAction) private var readerCommandAction
    @Environment(\.brevTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @Environment(\.openWindow) private var openWindow
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    /// All headers in the thread, sorted oldest → newest.
    /// Derived by the caller from all loaded headers in
    /// `MailNavigationState.currentFolderHeaders`.
    let threadHeaders: [MessageHeader]
    let backend: any MailBackend
    let sourceID: MailSourceID?
    let mailboxLabel: String?
    let navigation: MailNavigationState
    let isWorkBlocked: Bool
    /// Folders of the message's account — feeds the per-card context menu's
    /// move/archive/junk gates (ADR-0045 capability honesty).
    let allFolders: [Folder]
    /// True when a local-filing backend exists and the thread's account is not
    /// the local account itself.
    let canFileLocally: Bool
    let preloadedBodies: [MessageHeader.ID: RenderedBody]
    let showsAvatars: Bool
    let autoScrollsToExpandedMessage: Bool
    let dateTextProvider: ((MessageHeader) -> String)?
    private let aiBackend: (any AIBackend)?
    /// Shared-calendar RSVP reconciliation (#10); nil leaves the
    /// mail-only confirmation unchanged.
    let inviteReconciler: CalendarInviteReconciler?
    private let bodyRenderer = BodyRenderer()

    @State private var expandedMessageIDs: Set<MessageHeader.ID> = []
    /// One pool per conversation: cards check out shared WebView stores and
    /// stage body/CID fetches through its permit budget instead of every
    /// expanded card owning a renderer and fetching in parallel.
    @State private var renderPool = ThreadConversationRenderPool()
    @State private var showUnreadOnly = false
    @State private var printExportErrorMessage: String?
    #if os(iOS)
    /// iOS share-sheet target for exported files — PDF export and .eml
    /// Save As both land here (#79).
    @State private var exportShareURL: URL?
    #endif
    @State private var showAISummaryConsent = false
    @State private var activeAISummaryRequest: ThreadAISummaryRequest?
    @State private var aiSummaryState: ThreadAISummaryState?
    @AppStorage(AIWriterSettings.Key.isEnabled) private var aiEnabled = false
    @AppStorage(AIWriterSettings.Key.consentGiven) private var aiConsentGiven = false
    @AppStorage(MailboxViewPreferenceKey.threadMessageOrder)
    private var threadMessageOrderRaw = MailboxThreadOrder.oldestFirst.rawValue
    @AppStorage(LocalMessageWorkflowStateStorage.storageKey)
    private var localWorkflowStateData = Data()

    /// Creates a conversation reader with per-message actions owned by its mailbox.
    /// - Parameters:
    ///   - sourceID: Account/mailbox identity shared by the conversation members.
    ///   - isWorkBlocked: Whether owner work prevents message actions or compose presentation.
    ///   - allFolders: Source-owned folders used to determine available destinations and roles.
    ///   - canFileLocally: Whether the owning workspace has a local-filing backend.
    ///   - preloadedBodies: Optional rendered bodies used for deterministic presentation.
    public init(
        threadHeaders: [MessageHeader],
        backend: any MailBackend,
        sourceID: MailSourceID? = nil,
        mailboxLabel: String? = nil,
        navigation: MailNavigationState,
        isWorkBlocked: Bool = false,
        allFolders: [Folder] = [],
        canFileLocally: Bool = false,
        aiBackend: (any AIBackend)? = nil,
        preloadedBodies: [MessageHeader.ID: RenderedBody] = [:],
        showsAvatars: Bool = true,
        autoScrollsToExpandedMessage: Bool = true,
        dateTextProvider: ((MessageHeader) -> String)? = nil,
        inviteReconciler: CalendarInviteReconciler? = nil
    ) {
        self.threadHeaders = threadHeaders
        self.backend = backend
        self.sourceID = sourceID
        self.mailboxLabel = mailboxLabel
        self.navigation = navigation
        self.isWorkBlocked = isWorkBlocked
        self.allFolders = allFolders
        self.canFileLocally = canFileLocally
        self.aiBackend = aiBackend
        self.preloadedBodies = preloadedBodies
        self.showsAvatars = showsAvatars
        self.autoScrollsToExpandedMessage = autoScrollsToExpandedMessage
        self.dateTextProvider = dateTextProvider
        self.inviteReconciler = inviteReconciler
    }

    // MARK: - Derived state

    private var threadMessageOrder: MailboxThreadOrder {
        MailboxThreadOrder(rawValue: threadMessageOrderRaw) ?? .oldestFirst
    }

    private var visibleHeaders: [MessageHeader] {
        // `threadHeaders` arrives oldest → newest; flip it for "Newest on top".
        let ordered = threadMessageOrder == .newestFirst
            ? Array(threadHeaders.reversed())
            : threadHeaders
        return showUnreadOnly ? ordered.filter { !$0.isRead } : ordered
    }

    private var hiddenReadCount: Int {
        showUnreadOnly ? threadHeaders.filter { $0.isRead }.count : 0
    }

    private var uniqueParticipants: [Correspondent] {
        var seen = Set<String>()
        var result: [Correspondent] = []
        for header in threadHeaders {
            if seen.insert(header.from.email).inserted {
                result.append(header.from)
            }
        }
        return result
    }

    private var areAllExpanded: Bool {
        visibleHeaders.allSatisfy { expandedMessageIDs.contains($0.id) }
    }

    private var shouldAutoScrollToExpandedMessage: Bool {
        ThreadConversationAccessibilityPolicy.shouldAutoScrollToExpandedMessage(
            autoScrollsToExpandedMessage: autoScrollsToExpandedMessage,
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
        )
    }

    private var denseChromeDynamicTypeRange: PartialRangeThrough<DynamicTypeSize> {
        MailDenseChromeDynamicType.compactRange
    }

    // MARK: - Body

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Thread subject header
                    if let subject = threadHeaders.last?.subject {
                        Text(subject)
                            .font(.system(.title2, design: .default, weight: .semibold))
                            .foregroundStyle(theme.textPrimary.color)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, BrevSpacing.md)
                            .padding(.top, BrevSpacing.lg)
                            .padding(.bottom, BrevSpacing.sm)
                            .dynamicTypeSize(denseChromeDynamicTypeRange)
                    }

                    conversationMetadataRow
                        .dynamicTypeSize(denseChromeDynamicTypeRange)

                    if let aiSummaryState {
                        ThreadAISummaryPanel(
                            state: aiSummaryState,
                            onRetry: aiSummaryRetryAction
                        )
                        .padding(.horizontal, BrevSpacing.md)
                        .padding(.bottom, BrevSpacing.sm)
                    }

                    LazyVStack(spacing: 0) {
                        ForEach(visibleHeaders) { header in
                            ThreadMessageCard(
                                header: header,
                                isExpanded: expandedMessageIDs.contains(header.id),
                                isSelected: navigation.selectedMessageID == header.id,
                                backend: backend,
                                sourceID: sourceID,
                                showsAvatar: showsAvatars,
                                isWorkBlocked: isWorkBlocked,
                                dateTextOverride: dateTextProvider?(header),
                                initialRenderedBody: preloadedBodies[header.id],
                                renderPool: renderPool,
                                inviteReconciler: inviteReconciler
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if expandedMessageIDs.contains(header.id) {
                                        expandedMessageIDs.remove(header.id)
                                    } else {
                                        expandedMessageIDs.insert(header.id)
                                    }
                                }
                            }
                            .id(header.id)
                            // Per-card parity with the single-message reader:
                            // the same consolidated, capability-gated
                            // inventory, dispatched through the detached
                            // command owner so undo/optimistic UI stay in the
                            // root view's shared handlers.
                            .contextMenu { cardMenuButtons(for: header) }
                        }

                        if hiddenReadCount > 0 {
                            hiddenReadMessagesFooter
                        }
                    }
                    .padding(.bottom, BrevSpacing.lg)
                }
                .frame(maxWidth: 840)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
            .onAppear {
                let defaultID = ThreadConversationExpansionPolicy.expandedID(
                    selectedID: navigation.selectedMessageID,
                    in: visibleHeaders
                )
                if let defaultID {
                    expandedMessageIDs = [defaultID]
                }
                if shouldAutoScrollToExpandedMessage, let defaultID {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation {
                            proxy.scrollTo(defaultID, anchor: .top)
                        }
                    }
                }
            }
            // Re-initialise when the selected thread changes.
            .onChange(of: threadHeaders.first?.threadID) { _, newThreadID in
                guard newThreadID != nil else { return }
                // Drop the previous thread's pooled renderers — their card
                // identities are gone, so nothing still needs them warm.
                renderPool = ThreadConversationRenderPool()
                let defaultID = ThreadConversationExpansionPolicy.expandedID(
                    selectedID: navigation.selectedMessageID,
                    in: visibleHeaders
                )
                withAnimation(.easeInOut(duration: 0.15)) {
                    expandedMessageIDs = defaultID.map { [$0] } ?? []
                }
                if shouldAutoScrollToExpandedMessage, let defaultID {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation { proxy.scrollTo(defaultID, anchor: .top) }
                    }
                }
            }
            .onChange(of: visibleHeaders.map(\.id)) { _, visibleIDs in
                guard !visibleIDs.isEmpty,
                      expandedMessageIDs.isDisjoint(with: visibleIDs)
                else { return }
                let defaultID = ThreadConversationExpansionPolicy.expandedID(
                    selectedID: navigation.selectedMessageID,
                    in: visibleHeaders
                )
                withAnimation(.easeInOut(duration: 0.15)) {
                    expandedMessageIDs = defaultID.map { [$0] } ?? []
                }
            }
            .onChange(of: navigation.selectedMessageID) { _, selectedID in
                guard let selectedID,
                      visibleHeaders.contains(where: { $0.id == selectedID })
                else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    expandedMessageIDs.insert(selectedID)
                    if shouldAutoScrollToExpandedMessage {
                        proxy.scrollTo(selectedID, anchor: .top)
                    }
                }
            }
            .focusedSceneValue(\.mailPrintExportActions, printExportActions)
            .alert(String(localized: "Print / Export Failed", bundle: .module), isPresented: printExportErrorBinding) {
                Button(String(localized: "OK", bundle: .module), role: .cancel) {
                    printExportErrorMessage = nil
                }
            } message: {
                Text(printExportErrorMessage ?? "")
            }
            #if os(iOS)
            .sheet(isPresented: Binding(
                get: { exportShareURL != nil },
                set: { if !$0 { exportShareURL = nil } }
            )) {
                if let url = exportShareURL {
                    MailShareSheet(activityItems: [url])
                }
            }
            #endif
            .alert(String(localized: "Enable AI Thread Summaries?", bundle: .module), isPresented: $showAISummaryConsent) {
                Button(String(localized: "Enable", bundle: .module)) {
                    aiEnabled = true
                    aiConsentGiven = true
                }
                Button(String(localized: "Cancel", bundle: .module), role: .cancel) {}
            } message: {
                Text(AIWriterDisclosure.defaultProvider.consentMessage)
            }
        }
    }

    private var printExportActions: MailPrintExportActions? {
        guard !threadHeaders.isEmpty else { return nil }
        return MailPrintExportActions(
            print: { printThread() },
            exportPDF: { exportThreadPDF() }
        )
    }

    // MARK: - Per-card context menu

    /// The same capability-gated inventory the single-message reader uses
    /// (`MessageCommandPresentation.readerMenu`), so right-click/long-press on
    /// a thread card exposes identical actions — hidden when unsupported,
    /// disabled only when temporarily unavailable.
    func cardMenuPresentation(for header: MessageHeader) -> MessageContextMenuPresentation {
        let workflowSourceID = sourceID ?? MailSourceID(
            accountID: backend.account.id,
            mailboxID: backend.account.id
        )
        let workflowID = SourceMessageID(sourceID: workflowSourceID, messageID: header.id)
        let lookup = LocalMessageWorkflowLookup(
            state: LocalMessageWorkflowStateStorage.decode(localWorkflowStateData) ?? .defaults
        )
        let moveCandidates = MessageCommandPresentation.moveFolderCandidates(
            from: allFolders,
            currentFolderID: header.folderID
        )
        // Sheet-backed actions use this reader's own root presentation state.
        let canPresentSheets = navigation.presentedSheet == nil
        return MessageCommandPresentation.readerMenu(
            for: header,
            isSnoozed: lookup.isSnoozed(workflowID),
            isDone: lookup.isDone(workflowID),
            isKeptOffline: MessageOfflineRetentionOverrideStore().isKeptOffline(workflowID),
            hasNote: lookup.note(for: workflowID) != nil,
            canOpenInNewWindow: canOpenCardInNewWindow,
            canArchive: allFolders.contains { $0.role == .archive && $0.id != header.folderID },
            canMove: !moveCandidates.isEmpty,
            canFileLocally: canFileLocally
                && backend.account.id != LocalMailBackend.accountID,
            junkActionTitle: MessageCommandPresentation.junkActionTitle(
                currentFolder: allFolders.first { $0.id == header.folderID },
                capabilities: backend.capabilities,
                folders: allFolders
            ),
            canBlockSender: backend.capabilities.contains(.blockSender),
            canDelete: true,
            canCreateTask: canPresentSheets,
            canCreateRule: canPresentSheets,
            canCreateMeeting: canPresentSheets,
            canAddNote: canPresentSheets,
            canFollowUp: canPresentSheets,
            hasFollowUp: FollowUpReminderIndex(settings: FollowUpSettings.load())
                .reminder(for: header.id, sourceID: sourceID) != nil,
            canReply: canPresentSheets && !isWorkBlocked,
            canPrint: true,
            canExportPDF: true,
            canShowProperties: true,
            extendedCapabilities: backend.extendedCapabilities,
            canExportEML: true
        )
    }

    /// "Open in New Window" on a card: never offered on iPhone/compact (the
    /// bus would just re-show the in-place reader); macOS always can, and
    /// iPad only at regular width where a detached scene exists (ADR-0033).
    private var canOpenCardInNewWindow: Bool {
        #if os(iOS)
        return MailDetachWindowPolicy.shouldDetach(
            idiom: UIDevice.current.userInterfaceIdiom,
            horizontalSizeClass: horizontalSizeClass
        )
        #else
        return true
        #endif
    }

    @ViewBuilder
    private func cardMenuButtons(for header: MessageHeader) -> some View {
        let menu = cardMenuPresentation(for: header)
        ForEach(menu.sections.indices, id: \.self) { sectionIndex in
            if sectionIndex > 0 {
                Divider()
            }
            ForEach(menu.sections[sectionIndex].actions, id: \.action) { presentation in
                cardMenuButton(presentation, for: header)
            }
        }
    }

    @ViewBuilder
    private func cardMenuButton(
        _ presentation: MessageContextMenuActionPresentation,
        for header: MessageHeader
    ) -> some View {
        if presentation.role == .destructive {
            Button(role: .destructive) {
                performCardMenuAction(presentation.action, for: header)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled || isCardActionBlocked(presentation.action))
        } else {
            Button {
                performCardMenuAction(presentation.action, for: header)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled || isCardActionBlocked(presentation.action))
        }
    }

    /// Mutation-style commands respect the work blocker; local/presentation
    /// actions (sheets, print, window open) do not — same split as the reader.
    private func isCardActionBlocked(_ action: MessageContextMenuAction) -> Bool {
        switch action {
        case .toggleRead, .toggleFlag, .toggleSnooze, .toggleDone, .archive,
             .move, .copyToFolder, .copyToLocalFolder, .moveToLocalFolder,
             .setJunk, .blockSender, .delete, .downloadOffline:
            return isWorkBlocked
        case .openInNewWindow, .select, .pinToTop, .reply, .replyAll, .forward,
             .print, .exportPDF, .saveAs, .createMeeting, .createTask,
             .createRule, .addNote, .followUp, .properties, .showHeaders,
             .viewSource:
            return false
        }
    }

    /// Print/PDF run locally; other commands use this conversation's owner.
    private func performCardMenuAction(
        _ action: MessageContextMenuAction,
        for header: MessageHeader
    ) {
        switch action {
        case .print:
            printCardMessage(header)
        case .exportPDF:
            exportCardPDF(header)
        case .saveAs:
            // #79: iOS exports the .eml locally through the share sheet;
            // macOS keeps routing to the root save panel.
            #if os(iOS)
            exportCardEML(header)
            #else
            if let command = DetachedMessageCommand(menuAction: action) {
                readerCommandAction?(.init(command: command, header: header, sourceID: sourceID))
            }
            #endif
        default:
            if let command = DetachedMessageCommand(menuAction: action) {
                readerCommandAction?(.init(command: command, header: header, sourceID: sourceID))
            }
        }
    }

    private func printCardMessage(_ header: MessageHeader) {
        Task { @MainActor in
            do {
                let messageBody = try await body(for: header.id)
                #if os(macOS)
                MessagePrintExportRenderer.presentPrintPanel(header: header, body: messageBody)
                #elseif os(iOS)
                MailPrintController.presentPrint(
                    messages: [(header, messageBody)],
                    jobName: header.subject
                )
                #endif
            } catch {
                printExportErrorMessage = String(localized: "Print failed: \(error.localizedDescription)", bundle: .module)
            }
        }
    }

    private func exportCardPDF(_ header: MessageHeader) {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.title = String(localized: "Export Message as PDF", bundle: .module)
        panel.nameFieldStringValue = "\(cardPDFBaseName(for: header)).pdf"
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor in
            do {
                let messageBody = try await body(for: header.id)
                try MessagePrintExportRenderer.exportPDF(header: header, body: messageBody, to: url)
            } catch {
                printExportErrorMessage = String(localized: "PDF export failed: \(error.localizedDescription)", bundle: .module)
            }
        }
        #elseif os(iOS)
        Task { @MainActor in
            do {
                let messageBody = try await body(for: header.id)
                let url = try MailPrintController.exportPDF(
                    messages: [(header, messageBody)],
                    fileName: cardPDFBaseName(for: header)
                )
                exportShareURL = url
            } catch {
                printExportErrorMessage = String(localized: "PDF export failed: \(error.localizedDescription)", bundle: .module)
            }
        }
        #endif
    }

    /// iOS Save As on a card: fetch the raw bytes, write a temp .eml, and
    /// hand it to the share sheet (#79).
    #if os(iOS)
    private func exportCardEML(_ header: MessageHeader) {
        Task { @MainActor in
            do {
                let rawMessageData: Data
                if let sourceID {
                    rawMessageData = try await backend.rawMessageData(
                        for: header.id,
                        sourceID: sourceID
                    )
                } else {
                    rawMessageData = try await backend.rawMessageData(for: header.id)
                }
                exportShareURL = try MessageEMLExport.writeToTemporaryFile(
                    header: header,
                    rawMessageData: rawMessageData
                )
            } catch {
                printExportErrorMessage = String(localized: "EML export failed: \(error.localizedDescription)", bundle: .module)
            }
        }
    }
    #endif

    private func cardPDFBaseName(for header: MessageHeader) -> String {
        let fallback = header.subject.isEmpty ? String(localized: "message", bundle: .module) : header.subject
        let invalid = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return fallback.components(separatedBy: invalid).joined(separator: "_")
    }

    private var printExportErrorBinding: Binding<Bool> {
        Binding(
            get: { printExportErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    printExportErrorMessage = nil
                }
            }
        )
    }

    private func printThread() {
        Task { @MainActor in
            let messages = await printableThreadMessages()
            #if os(macOS)
            MessagePrintExportRenderer.presentPrintPanel(messages: messages)
            #elseif os(iOS)
            MailPrintController.presentPrint(messages: messages, jobName: threadJobName)
            #endif
        }
    }

    private func exportThreadPDF() {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.title = String(localized: "Export Thread as PDF", bundle: .module)
        panel.nameFieldStringValue = pdfFilename
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor in
            do {
                let messages = await printableThreadMessages()
                try MessagePrintExportRenderer.exportPDF(messages: messages, to: url)
            } catch {
                printExportErrorMessage = String(localized: "PDF export failed: \(error.localizedDescription)", bundle: .module)
            }
        }
        #elseif os(iOS)
        Task { @MainActor in
            do {
                let messages = await printableThreadMessages()
                let url = try MailPrintController.exportPDF(messages: messages, fileName: pdfBaseName)
                exportShareURL = url
            } catch {
                printExportErrorMessage = String(localized: "PDF export failed: \(error.localizedDescription)", bundle: .module)
            }
        }
        #endif
    }

    private var threadJobName: String {
        let subject = threadHeaders.last?.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return subject?.isEmpty == false ? subject ?? "Thread" : "Thread"
    }

    /// Sanitized base filename without the `.pdf` extension.
    private var pdfBaseName: String {
        threadJobName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    /// Full filename including `.pdf` extension, used for the macOS save panel.
    private var pdfFilename: String {
        "\(pdfBaseName).pdf"
    }

    private func printableThreadMessages() async -> [(header: MessageHeader, body: MessageBody?)] {
        await MailConcurrentWork.map(threadHeaders) { header in
            let body: MessageBody?
            do {
                if let sourceID {
                    body = try await backend.body(for: header.id, sourceID: sourceID)
                } else {
                    body = try await backend.body(for: header.id)
                }
            } catch {
                body = nil
            }
            return (header: header, body: body)
        }
    }

    private func summarizeThread(with aiBackend: any AIBackend) async {
        guard ThreadAISummaryAvailability.disabledReason(in: aiSummaryAvailabilityState) == nil else {
            return
        }
        let includedHeaders = ThreadAISummaryContextBuilder.includedHeaders(from: threadHeaders)
        let request = ThreadAISummaryRequest(
            threadID: threadHeaders.last?.threadID,
            messageIDs: includedHeaders.map(\.id)
        )
        activeAISummaryRequest = request
        aiSummaryState = .loading(providerLabel: aiBackend.transparencyLabel)

        do {
            var bodies: [MessageHeader.ID: MessageBody] = [:]
            for header in includedHeaders {
                let loaded = try await body(for: header.id)
                let rendered = await bodyRenderer.render(loaded)
                bodies[header.id] = MessageBody(
                    messageID: loaded.messageID,
                    html: rendered.html,
                    plainText: rendered.plainText,
                    attachments: rendered.attachments,
                    listUnsubscribe: loaded.listUnsubscribe
                )
            }
            guard activeAISummaryRequest == request else {
                return
            }
            guard let context = ThreadAISummaryContextBuilder.context(
                headers: threadHeaders,
                bodies: bodies
            ) else {
                aiSummaryState = .failure(
                    message: "Couldn't summarize this thread.",
                    providerLabel: aiBackend.transparencyLabel
                )
                activeAISummaryRequest = nil
                return
            }
            let response = try await aiBackend.generateReply(
                to: context.messages,
                instruction: context.instruction
            )
            guard activeAISummaryRequest == request else { return }
            aiSummaryState = .success(ThreadAISummaryPresentation.make(
                responseText: response.text,
                providerLabel: aiBackend.transparencyLabel,
                wasTruncated: context.wasTruncated
            ))
            activeAISummaryRequest = nil
        } catch is CancellationError {
            guard activeAISummaryRequest == request else { return }
            aiSummaryState = nil
            activeAISummaryRequest = nil
        } catch {
            guard activeAISummaryRequest == request else { return }
            aiSummaryState = .failure(
                message: ThreadAISummaryErrorPresentation.message(for: error),
                providerLabel: aiBackend.transparencyLabel
            )
            activeAISummaryRequest = nil
        }
    }

    private func body(for messageID: String) async throws -> MessageBody {
        if let sourceID {
            return try await backend.body(for: messageID, sourceID: sourceID)
        }
        return try await backend.body(for: messageID)
    }

    // MARK: - Conversation metadata

    private var conversationMetadataRow: some View {
        HStack(spacing: BrevSpacing.xs) {
            Text(verbatim: mailboxLabel ?? backend.account.emailAddress)
                .brevFont(.footnote)
                .foregroundStyle(theme.textSecondary.color)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(verbatim: "·")
                .brevFont(.footnote)
                .foregroundStyle(theme.textTertiary.color)
                .accessibilityHidden(true)

            participantSummary

            Spacer(minLength: BrevSpacing.sm)

            threadActionsMenu
        }
        .padding(.horizontal, BrevSpacing.md)
        .padding(.bottom, BrevSpacing.sm)
    }

    private var threadActionsMenu: some View {
        Menu {
            #if os(iOS)
            // iPhone has no per-card overflow button, so Reply/Snooze/etc.
            // were only reachable by long-press. Surface the same inventory
            // here, acting on the thread's latest message.
            if let latest = visibleHeaders.last {
                cardMenuButtons(for: latest)
                Divider()
            }
            #endif

            if shouldShowAISummaryMenu {
                aiSummaryMenuItems
                Divider()
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showUnreadOnly.toggle()
                }
            } label: {
                Label(
                    showUnreadOnly
                        ? String(localized: "Show All", bundle: .module)
                        : String(localized: "Unread only", bundle: .module),
                    systemImage: showUnreadOnly ? "envelope.open" : "envelope.badge"
                )
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if areAllExpanded {
                        expandedMessageIDs.removeAll()
                    } else {
                        expandedMessageIDs = Set(visibleHeaders.map(\.id))
                    }
                }
            } label: {
                Label(
                    areAllExpanded
                        ? String(localized: "Collapse All", bundle: .module)
                        : String(localized: "Expand All", bundle: .module),
                    systemImage: areAllExpanded ? "chevron.up.2" : "chevron.down.2"
                )
            }
            .disabled(visibleHeaders.isEmpty)

            #if os(iOS)
            Divider()
            threadPrintExportMenuItems
            #endif
        } label: {
            Label(String(localized: "Conversation controls", bundle: .module), systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
                .foregroundStyle(theme.textSecondary.color)
            #if os(iOS)
                .frame(width: 44, height: 44)
            #endif
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel(String(localized: "Conversation controls", bundle: .module))
    }

    #if os(iOS)
    @ViewBuilder
    private var threadPrintExportMenuItems: some View {
        Group {
            Button(action: printThread) {
                Label(String(localized: "Print…", bundle: .module), systemImage: "printer")
            }
            Button(action: exportThreadPDF) {
                Label(String(localized: "Export as PDF…", bundle: .module), systemImage: "doc.richtext")
            }
            // A detached reader addresses the selected/expanded message, not
            // an arbitrary member of the conversation (ADR-0033).
            if canOpenCardInNewWindow,
               let messageID = ThreadConversationExpansionPolicy.expandedID(
                   selectedID: navigation.selectedMessageID, in: threadHeaders
               ),
               let header = threadHeaders.first(where: { $0.id == messageID }) {
                Button {
                    openWindow(value: DetachedReaderWindowPayload(
                        sourceID: sourceID, messageID: messageID, folderID: header.folderID
                    ))
                } label: {
                    Label(String(localized: "Open in New Window", bundle: .module), systemImage: "macwindow.on.rectangle")
                }
            }
        }
        .disabled(threadHeaders.isEmpty)
    }
    #endif

    @ViewBuilder
    private var aiSummaryMenuItems: some View {
        if let reason = ThreadAISummaryAvailability.disabledReason(in: aiSummaryAvailabilityState) {
            if reason == .notEnabled || reason == .consentRequired {
                Button(String(localized: "Enable AI...", bundle: .module)) {
                    showAISummaryConsent = true
                }
                Text(AIWriterDisclosure.defaultProvider.transparencyLabel)
            } else {
                Label(reason.title, systemImage: "exclamationmark.triangle")
            }
        } else if let aiBackend {
            Button {
                Task { await summarizeThread(with: aiBackend) }
            } label: {
                Label(String(localized: "Summarize Thread", bundle: .module), systemImage: "wand.and.stars")
            }
            .disabled(aiSummaryMenuDisabled)
            Text(aiBackend.transparencyLabel)
        }
    }

    private var aiSummaryMenuDisabled: Bool {
        if case .loading = aiSummaryState {
            return true
        }
        return false
    }

    private var shouldShowAISummaryMenu: Bool {
        aiBackend != nil || aiEnabled || aiConsentGiven
    }

    private var aiSummaryAvailabilityState: ThreadAISummaryAvailabilityState {
        ThreadAISummaryAvailabilityState(
            settings: AIWriterSettings(isEnabled: aiEnabled, consentGiven: aiConsentGiven),
            hasProviderBackend: aiBackend != nil,
            isBusy: isWorkBlocked,
            hasActiveRequest: activeAISummaryRequest != nil,
            messageCount: threadHeaders.count
        )
    }

    /// Retry affordance for a failed thread summary: offered only when the
    /// failure is transient and the summary request can actually run again
    /// (provider present, consent/settings OK, no work or request in flight).
    private var aiSummaryRetryAction: (() -> Void)? {
        guard case .failure = aiSummaryState,
              let aiBackend,
              ThreadAISummaryAvailability.disabledReason(in: aiSummaryAvailabilityState) == nil
        else { return nil }
        return { Task { await summarizeThread(with: aiBackend) } }
    }

    // MARK: - Participant summary

    private var participantSummary: some View {
        Text("\(threadHeaders.count) messages", bundle: .module)
            .brevFont(.footnote)
            .foregroundStyle(theme.textSecondary.color)
            .accessibilityLabel(String(
                localized: "\(threadHeaders.count) messages from \(uniqueParticipants.count) participants",
                bundle: .module
            ))
    }

    // MARK: - Hidden read messages footer

    @ViewBuilder
    private var hiddenReadMessagesFooter: some View {
        HStack(spacing: BrevSpacing.xs) {
            Image(systemName: "envelope.open")
                .foregroundStyle(theme.textTertiary.color)
                .font(.system(size: 12))
            Text("\(hiddenReadCount) hidden read message\(hiddenReadCount == 1 ? "" : "s")", bundle: .module)
                .brevFont(.footnote)
                .foregroundStyle(theme.textTertiary.color)
        }
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.sm)
    }
}

struct ThreadAISummaryPanel: View {
    @Environment(\.brevTheme) private var theme
    let state: ThreadAISummaryState
    /// Non-nil when the failure is retryable — shown as a Retry button.
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            HStack(spacing: BrevSpacing.xs) {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(theme.accent.color)
                Text("Thread summary", bundle: .module)
                    .brevFont(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.textPrimary.color)
                Spacer()
                if case .loading = state {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            switch state {
            case .loading(let providerLabel):
                Text(providerLabel)
                    .brevFont(.footnote)
                    .foregroundStyle(theme.textSecondary.color)
            case .success(let presentation):
                ThreadAISummarySection(title: "Summary", bullets: presentation.summaryBullets)
                if !presentation.nextActions.isEmpty {
                    ThreadAISummarySection(title: "Next actions", bullets: presentation.nextActions)
                }
                if let contextNote = presentation.contextNote {
                    Text(contextNote)
                        .brevFont(.footnote)
                        .foregroundStyle(theme.textTertiary.color)
                }
                Text(presentation.providerLabel)
                    .brevFont(.footnote)
                    .foregroundStyle(theme.textSecondary.color)
            case .failure(let message, let providerLabel):
                Text(message)
                    .brevFont(.footnote)
                    .foregroundStyle(theme.danger.color)
                if let onRetry {
                    Button {
                        onRetry()
                    } label: {
                        Label(String(localized: "Retry", bundle: .module), systemImage: "arrow.clockwise")
                        #if os(iOS)
                            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        #endif
                    }
                    .brevFont(.footnote)
                    .foregroundStyle(theme.accent.color)
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Retry thread summary", bundle: .module))
                }
                Text(providerLabel)
                    .brevFont(.footnote)
                    .foregroundStyle(theme.textSecondary.color)
            }
        }
        .padding(BrevSpacing.sm)
        .background(theme.bgSecondary.color)
        .clipShape(RoundedRectangle(cornerRadius: BrevRadius.sm, style: .continuous))
    }
}

private struct ThreadAISummarySection: View {
    @Environment(\.brevTheme) private var theme
    let title: String
    let bullets: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            Text(title)
                .brevFont(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(theme.textPrimary.color)
            ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                HStack(alignment: .firstTextBaseline, spacing: BrevSpacing.xs) {
                    Text(verbatim: "•")
                        .foregroundStyle(theme.textTertiary.color)
                    Text(bullet)
                        .brevFont(.footnote)
                        .foregroundStyle(theme.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
