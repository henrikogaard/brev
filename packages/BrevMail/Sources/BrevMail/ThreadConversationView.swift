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
    private let bodyRenderer = BodyRenderer()

    @State private var expandedMessageIDs: Set<MessageHeader.ID> = []
    /// One pool per conversation: cards check out shared WebView stores and
    /// stage body/CID fetches through its permit budget instead of every
    /// expanded card owning a renderer and fetching in parallel.
    @State private var renderPool = ThreadConversationRenderPool()
    @State private var showUnreadOnly = false
    @State private var printExportErrorMessage: String?
    #if os(iOS)
    @State private var pdfShareURL: URL?
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
        dateTextProvider: ((MessageHeader) -> String)? = nil
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

                    Text(verbatim: mailboxLabel ?? backend.account.emailAddress)
                        .brevFont(.footnote)
                        .foregroundStyle(theme.textSecondary.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, BrevSpacing.md)
                        .padding(.bottom, BrevSpacing.sm)

                    conversationControlsRow
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
                                renderPool: renderPool
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
                            // command bus so undo/optimistic UI stay in the
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
                    in: threadHeaders
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
                    in: threadHeaders
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
            .onChange(of: navigation.selectedMessageID) { _, selectedID in
                guard let selectedID,
                      threadHeaders.contains(where: { $0.id == selectedID })
                else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    expandedMessageIDs.insert(selectedID)
                    if shouldAutoScrollToExpandedMessage {
                        proxy.scrollTo(selectedID, anchor: .top)
                    }
                }
            }
            .toolbar {
                #if os(iOS)
                // One consolidated thread-tools menu (matching the reader's
                // ellipsis.circle affordance): print/export plus, at iPad
                // regular width, "Open in New Window". The detached payload
                // addresses a single message, so we open the card the reader
                // is actually showing — the expanded/selected message
                // (falling back to the newest), matching the in-pane
                // expansion. (ADR-0033)
                let detachMessageID = ThreadConversationExpansionPolicy.expandedID(
                    selectedID: navigation.selectedMessageID,
                    in: threadHeaders
                )
                let canDetach = MailDetachWindowPolicy.shouldDetach(
                    idiom: UIDevice.current.userInterfaceIdiom == .pad ? .pad : .phone,
                    isRegularWidth: horizontalSizeClass == .regular
                )
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            printThread()
                        } label: {
                            Label(String(localized: "Print…", bundle: .module), systemImage: "printer")
                        }
                        Button {
                            exportThreadPDF()
                        } label: {
                            Label(String(localized: "Export as PDF…", bundle: .module), systemImage: "doc.richtext")
                        }
                        if canDetach, let detachMessageID {
                            Divider()
                            Button {
                                openWindow(value: DetachedReaderWindowPayload(
                                    sourceID: sourceID,
                                    messageID: detachMessageID
                                ))
                            } label: {
                                Label(
                                    String(localized: "Open in New Window", bundle: .module),
                                    systemImage: "macwindow.on.rectangle"
                                )
                            }
                        }
                    } label: {
                        Label(String(localized: "More thread actions", bundle: .module), systemImage: "ellipsis.circle")
                    }
                    .disabled(threadHeaders.isEmpty)
                    .accessibilityLabel(String(localized: "More thread actions", bundle: .module))
                }
                #endif
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
                get: { pdfShareURL != nil },
                set: { if !$0 { pdfShareURL = nil } }
            )) {
                if let url = pdfShareURL {
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
    private func cardMenuPresentation(for header: MessageHeader) -> MessageContextMenuPresentation {
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
        // Sheet-backed actions route to the main window via the command bus,
        // which drops them when another sheet is up — mirror that here so the
        // menu is honest instead of silently no-op'ing.
        let canPresentSheets = navigation.presentedSheet == nil
        return MessageCommandPresentation.readerMenu(
            for: header,
            isSnoozed: lookup.isSnoozed(workflowID),
            isDone: lookup.isDone(workflowID),
            isKeptOffline: MessageOfflineRetentionOverrideStore().isKeptOffline(workflowID),
            hasNote: lookup.note(for: workflowID) != nil,
            canOpenInNewWindow: canOpenCardInNewWindow,
            canArchive: allFolders.contains { $0.role == .archive },
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
            canReply: true,
            canPrint: true,
            canExportPDF: true,
            canShowProperties: true,
            extendedCapabilities: backend.extendedCapabilities,
            canExportEML: supportsCardEMLExport
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

    private var supportsCardEMLExport: Bool {
        #if os(macOS)
        true
        #else
        false
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

    /// Print/PDF run locally (the card surface owns the print pipeline);
    /// everything else travels the detached-command bus so the main window
    /// performs it through the shared command handlers.
    private func performCardMenuAction(
        _ action: MessageContextMenuAction,
        for header: MessageHeader
    ) {
        switch action {
        case .print:
            printCardMessage(header)
        case .exportPDF:
            exportCardPDF(header)
        default:
            if let command = DetachedMessageCommand(menuAction: action) {
                DetachedMessageCommandBus.post(command, header: header, sourceID: sourceID)
            }
        }
    }

    private func printCardMessage(_ header: MessageHeader) {
        Task { @MainActor in
            let messageBody = try? await body(for: header.id)
            #if os(macOS)
            MessagePrintExportRenderer.presentPrintPanel(header: header, body: messageBody)
            #elseif os(iOS)
            MailPrintController.presentPrint(
                messages: [(header, messageBody)],
                jobName: header.subject
            )
            #endif
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
                let messageBody = try? await body(for: header.id)
                try MessagePrintExportRenderer.exportPDF(header: header, body: messageBody, to: url)
            } catch {
                printExportErrorMessage = "PDF export failed: \(error.localizedDescription)"
            }
        }
        #elseif os(iOS)
        Task { @MainActor in
            do {
                let messageBody = try? await body(for: header.id)
                let url = try MailPrintController.exportPDF(
                    messages: [(header, messageBody)],
                    fileName: cardPDFBaseName(for: header)
                )
                pdfShareURL = url
            } catch {
                printExportErrorMessage = "PDF export failed: \(error.localizedDescription)"
            }
        }
        #endif
    }

    private func cardPDFBaseName(for header: MessageHeader) -> String {
        let fallback = header.subject.isEmpty ? "message" : header.subject
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
                printExportErrorMessage = "PDF export failed: \(error.localizedDescription)"
            }
        }
        #elseif os(iOS)
        Task { @MainActor in
            do {
                let messages = await printableThreadMessages()
                let url = try MailPrintController.exportPDF(messages: messages, fileName: pdfBaseName)
                pdfShareURL = url
            } catch {
                printExportErrorMessage = "PDF export failed: \(error.localizedDescription)"
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

    // MARK: - Conversation controls row

    @ViewBuilder
    private var conversationControlsRow: some View {
        HStack(spacing: BrevSpacing.sm) {
            // Participant summary
            participantSummary

            Spacer(minLength: BrevSpacing.sm)

            if shouldShowAISummaryMenu {
                aiSummaryMenu
            }

            // Show unread only toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showUnreadOnly.toggle()
                }
            } label: {
                Label(
                    showUnreadOnly ? "Show All" : "Unread Only",
                    systemImage: showUnreadOnly ? "envelope.open" : "envelope.badge"
                )
                .brevFont(.footnote)
                .foregroundStyle(showUnreadOnly ? theme.accent.color : theme.textSecondary.color)
            }
            .buttonStyle(.plain)

            // Expand / collapse all
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
                    areAllExpanded ? "Collapse All" : "Expand All",
                    systemImage: areAllExpanded ? "chevron.up.2" : "chevron.down.2"
                )
                .brevFont(.footnote)
                .foregroundStyle(theme.textSecondary.color)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.xs)
        .padding(.bottom, BrevSpacing.sm)
    }

    @ViewBuilder
    private var aiSummaryMenu: some View {
        Menu {
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
                Text(aiBackend.transparencyLabel)
            }
        } label: {
            Label(String(localized: "Summarize", bundle: .module), systemImage: "wand.and.stars")
                .brevFont(.footnote)
                .foregroundStyle(aiSummaryState?.isLoading == true ? theme.accent.color : theme.textSecondary.color)
        }
        .menuStyle(.borderlessButton)
        .disabled(aiSummaryMenuDisabled)
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

private struct ThreadAISummaryPanel: View {
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
