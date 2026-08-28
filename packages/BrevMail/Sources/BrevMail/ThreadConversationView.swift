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
    let navigation: MailNavigationState
    let isWorkBlocked: Bool
    let preloadedBodies: [MessageHeader.ID: RenderedBody]
    let showsAvatars: Bool
    let autoScrollsToExpandedMessage: Bool
    let dateTextProvider: ((MessageHeader) -> String)?
    private let aiBackend: (any AIBackend)?
    private let bodyRenderer = BodyRenderer()

    @State private var expandedMessageIDs: Set<MessageHeader.ID> = []
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

    public init(
        threadHeaders: [MessageHeader],
        backend: any MailBackend,
        sourceID: MailSourceID? = nil,
        navigation: MailNavigationState,
        isWorkBlocked: Bool = false,
        aiBackend: (any AIBackend)? = nil,
        preloadedBodies: [MessageHeader.ID: RenderedBody] = [:],
        showsAvatars: Bool = true,
        autoScrollsToExpandedMessage: Bool = true,
        dateTextProvider: ((MessageHeader) -> String)? = nil
    ) {
        self.threadHeaders = threadHeaders
        self.backend = backend
        self.sourceID = sourceID
        self.navigation = navigation
        self.isWorkBlocked = isWorkBlocked
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
                // Thread subject header
                if let subject = threadHeaders.last?.subject {
                    Text(subject)
                        .font(.headline)
                        .foregroundStyle(theme.textPrimary.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, BrevSpacing.md)
                        .padding(.top, BrevSpacing.md)
                        .padding(.bottom, BrevSpacing.xs)
                        .dynamicTypeSize(denseChromeDynamicTypeRange)
                }

                // Conversation controls toolbar
                conversationControlsRow
                    .dynamicTypeSize(denseChromeDynamicTypeRange)

                if let aiSummaryState {
                    ThreadAISummaryPanel(state: aiSummaryState)
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
                            initialRenderedBody: preloadedBodies[header.id]
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
                    }

                    if hiddenReadCount > 0 {
                        hiddenReadMessagesFooter
                    }
                }
                .padding(.bottom, BrevSpacing.lg)
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
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            printThread()
                        } label: {
                            Label(String(localized: "Print", bundle: .module), systemImage: "printer")
                        }
                        Button {
                            exportThreadPDF()
                        } label: {
                            Label(String(localized: "Export PDF", bundle: .module), systemImage: "doc.richtext")
                        }
                    } label: {
                        Label(String(localized: "Print / Export", bundle: .module), systemImage: "printer")
                    }
                    .disabled(threadHeaders.isEmpty)
                }
                // Parity with `MessageDetailView`: at iPad regular width a
                // thread can also be detached into a standalone reader window.
                // The detached payload addresses a single message, so we open the
                // card the reader is actually showing — the expanded/selected
                // message (falling back to the newest), matching the in-pane
                // expansion. (ADR-0033; this action is absent from the
                // single-message path's sibling because that view supplies it
                // itself.)
                if let detachMessageID = ThreadConversationExpansionPolicy.expandedID(
                    selectedID: navigation.selectedMessageID,
                    in: threadHeaders
                ),
                    MailDetachWindowPolicy.shouldDetach(
                        idiom: UIDevice.current.userInterfaceIdiom == .pad ? .pad : .phone,
                        isRegularWidth: horizontalSizeClass == .regular
                    ) {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            openWindow(value: DetachedReaderWindowPayload(
                                sourceID: sourceID,
                                messageID: detachMessageID
                            ))
                        } label: {
                            Label(String(localized: "Open in New Window", bundle: .module), systemImage: "macwindow.on.rectangle")
                        }
                    }
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
                .brevFont(.caption)
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
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.xs)
        .background(theme.bgSecondary.color)
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
                .brevFont(.caption)
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

    // MARK: - Participant summary

    @ViewBuilder
    private var participantSummary: some View {
        HStack(spacing: -6) {
            let previewParticipants = Array(uniqueParticipants.prefix(3))
            ForEach(Array(previewParticipants.enumerated()), id: \.offset) { index, participant in
                BrevAvatarView(
                    email: participant.email,
                    displayName: participant.name,
                    size: 20
                )
                .zIndex(Double(3 - index))
            }
        }
        Text(participantCountLabel)
            .brevFont(.caption)
            .foregroundStyle(theme.textSecondary.color)
    }

    private var participantCountLabel: String {
        let count = uniqueParticipants.count
        return count == 1 ? "1 participant" : "\(count) participants"
    }

    // MARK: - Hidden read messages footer

    @ViewBuilder
    private var hiddenReadMessagesFooter: some View {
        HStack(spacing: BrevSpacing.xs) {
            Image(systemName: "envelope.open")
                .foregroundStyle(theme.textTertiary.color)
                .font(.system(size: 12))
            Text("\(hiddenReadCount) hidden read message\(hiddenReadCount == 1 ? "" : "s")", bundle: .module)
                .brevFont(.caption)
                .foregroundStyle(theme.textTertiary.color)
        }
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.sm)
    }
}

private struct ThreadAISummaryPanel: View {
    @Environment(\.brevTheme) private var theme
    let state: ThreadAISummaryState

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
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
            case .success(let presentation):
                ThreadAISummarySection(title: "Summary", bullets: presentation.summaryBullets)
                if !presentation.nextActions.isEmpty {
                    ThreadAISummarySection(title: "Next actions", bullets: presentation.nextActions)
                }
                if let contextNote = presentation.contextNote {
                    Text(contextNote)
                        .brevFont(.caption)
                        .foregroundStyle(theme.textTertiary.color)
                }
                Text(presentation.providerLabel)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
            case .failure(let message, let providerLabel):
                Text(message)
                    .brevFont(.caption)
                    .foregroundStyle(theme.danger.color)
                Text(providerLabel)
                    .brevFont(.caption)
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
                .brevFont(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(theme.textPrimary.color)
            ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                HStack(alignment: .firstTextBaseline, spacing: BrevSpacing.xs) {
                    Text(verbatim: "•")
                        .foregroundStyle(theme.textTertiary.color)
                    Text(bullet)
                        .brevFont(.caption)
                        .foregroundStyle(theme.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
