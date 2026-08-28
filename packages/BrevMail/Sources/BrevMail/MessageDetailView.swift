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

import BrevAvatars
import BrevBackend
import BrevCalendar
import BrevDesign
import BrevThemes
import OSLog
import QuickLook
import SwiftUI
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Reading pane for the currently selected message.
///
/// Loads the message header from the in-memory list when available
/// and the body asynchronously from the backend. Prefers HTML when the
/// rich renderer is enabled (Settings → Reading); otherwise falls back
/// to plain text or an attributed HTML import. Theme tokens and mailbox
/// font prefs drive typography via `MessageBodyStyle`.
public struct MessageDetailView: View {
    private static let bodyLoadTimeoutNanoseconds: UInt64 = 15_000_000_000
    private static let bodyLoadLogger = Logger(
        subsystem: "eu.brevmail.brev",
        category: "MessageBodyLoad"
    )

    @Environment(\.brevTheme) private var theme
    private let backend: any MailBackend
    private let sourceID: MailSourceID?
    private let header: MessageHeader?
    private let navigation: MailNavigationState?
    private let allFolders: [Folder]
    private let isWorkBlocked: Bool
    /// When present, the view is shown in a standalone window and renders an
    /// in-content action bar; destructive actions invoke this to close the window.
    private let closeWindow: (() -> Void)?
    private let readReceiptNotificationStore = MessageReadReceiptNotificationStore.shared
    private let bodyRenderer = BodyRenderer()

    @StateObject private var htmlWebViewStore = HTMLBodyWebViewStore()

    @State private var messageBody: MessageBody?
    @State private var messageSecurityState: MessageSecurityState = .none
    @State private var renderedHTML: AttributedString?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var bodyLoadFallbackNotice: String?
    @State private var needsReloadAfterWorkUnblocks = false
    @State private var activeLoadRequest: MessageDetailLoadRequest?
    @State private var activeOpenReadRequest: MessageOpenReadRequest?
    @State private var activeAttachmentDownloadRequest: MessageAttachmentDownloadRequest?
    @State private var activeInviteResponseRequest: CalendarInviteResponseRequest?
    @State private var postVisibleEnrichmentTask: Task<Void, Never>?
    @State private var readStatus: MessageDetailStatus?
    @State private var downloadingAttachmentID: String?
    @State private var attachmentError: MessageDetailInlineStatus?
    @State private var attachmentSaveToast: String?
    @State private var isRecipientsExpanded = false
    @State private var parsedInvite: ICSParser.ParsedEvent?
    @State private var calendarInviteEvent: CalendarEvent?
    @State private var inviteLoadStatus: MessageDetailStatus?
    @State private var showRemoteContent = false
    @State private var remoteContentPolicy = RemoteContentPolicy.load()
    @State private var calendarResponse: CalendarInviteLocalResponse?
    @State private var inviteResponseConfirmation: MailRootStatus?
    @State private var inviteResponseStatus: MessageDetailStatus?
    @State private var failedInviteResponse: AttendeeState?
    @State private var isRespondingToInvite = false
    @State private var pendingListUnsubscribeAction: MessageListUnsubscribeActionPresentation?
    @State private var isShowingListUnsubscribeConfirmation = false
    @State private var handledReadReceiptMessageIDs: Set<MessageHeader.ID> = []
    @State private var isSendingReadReceipt = false
    @State private var readReceiptStatusMessage: String?
    @State private var readReceiptErrorMessage: String?
    @State private var pendingSuspiciousLink: MessageSecurityLinkWarning?
    @State private var quickLookURL: URL?
    @State private var downloadedAttachmentURLs: [String: URL] = [:]
    @State private var htmlRenderingModeOverride: HTMLBodyRenderingMode?
    @State private var htmlRenderingModeOverrideMessageID: MessageHeader.ID?
    @State private var messageOpenInterval: MailUIPerformanceDiagnostics.Interval?
    @State private var messageOpenMessageID: MessageHeader.ID?
    #if os(iOS)
    @State private var pdfShareURL: URL?
    #endif

    @AppStorage(MailboxViewPreferenceKey.useRichRenderer) private var useRichRenderer = true
    @AppStorage(MailboxViewPreferenceKey.allowRemoteContent) private var allowRemoteContentDefault = false
    @AppStorage(MailboxViewPreferenceKey.showSenderAvatars) private var showSenderAvatars = true
    @AppStorage(MailboxViewPreferenceKey.fontFamily) private var fontFamilyRaw = MailboxFontFamily.system.rawValue
    @AppStorage(MailboxViewPreferenceKey.textSize) private var textSizeRaw = MailboxTextSize.medium.rawValue
    @AppStorage(MailboxViewPreferenceKey.listDensity) private var listDensityRaw = MailboxListDensity.comfortable.rawValue

    #if os(iOS)
    @Environment(\.openWindow) private var openWindow
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    public init(
        backend: any MailBackend,
        sourceID: MailSourceID? = nil,
        header: MessageHeader?,
        navigation: MailNavigationState? = nil,
        allFolders: [Folder] = [],
        isWorkBlocked: Bool = false,
        closeWindow: (() -> Void)? = nil
    ) {
        self.backend = backend
        self.sourceID = sourceID
        self.header = header
        self.navigation = navigation
        self.allFolders = allFolders
        self.isWorkBlocked = isWorkBlocked
        self.closeWindow = closeWindow
    }

    public var body: some View {
        Group {
            if let header {
                if showsWindowActionBar {
                    VStack(spacing: 0) {
                        windowActionBar(for: header)
                        content(for: header)
                    }
                } else {
                    content(for: header)
                }
            } else {
                placeholder
            }
        }
        .task(id: reloadKey) { await reload() }
        .focusedSceneValue(\.mailPrintExportActions, printExportActions)
        .confirmationDialog(
            pendingListUnsubscribeAction?.confirmationTitle ?? "Confirm unsubscribe",
            isPresented: $isShowingListUnsubscribeConfirmation,
            titleVisibility: .visible
        ) {
            if let action = pendingListUnsubscribeAction {
                Button(action.confirmButtonTitle) {
                    confirmListUnsubscribeAction()
                }
            }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) {
                clearPendingListUnsubscribeAction()
            }
        } message: {
            if let action = pendingListUnsubscribeAction {
                Text(action.confirmationMessage)
            }
        }
        .alert(
            pendingSuspiciousLink?.confirmationTitle ?? "Open suspicious link?",
            isPresented: suspiciousLinkAlertBinding,
            presenting: pendingSuspiciousLink
        ) { warning in
            Button(warning.openButtonTitle) {
                openConfirmedSuspiciousLink(warning)
            }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) {
                clearPendingSuspiciousLink()
            }
        } message: { warning in
            Text(warning.confirmationMessage)
        }
        .onChange(of: isWorkBlocked) { oldValue, newValue in
            guard MessageDetailWorkResumePolicy.shouldReloadMessage(
                wasBlocked: oldValue,
                isBlocked: newValue,
                hasPendingReload: needsReloadAfterWorkUnblocks
            ) else { return }
            needsReloadAfterWorkUnblocks = false
            Task { await reload() }
        }
        .onChange(of: header?.id) { _, _ in
            resetHTMLRenderingModeOverride()
        }
        .quickLookPreview($quickLookURL)
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
    }

    private var printExportActions: MailPrintExportActions? {
        guard header != nil else { return nil }
        return MailPrintExportActions(
            isAvailable: !isLoading && errorMessage == nil,
            print: { printCurrentMessage() },
            exportPDF: { exportCurrentMessagePDF() }
        )
    }

    private var suspiciousLinkAlertBinding: Binding<Bool> {
        Binding {
            pendingSuspiciousLink != nil
        } set: { isPresented in
            if !isPresented {
                pendingSuspiciousLink = nil
            }
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        VStack(spacing: BrevSpacing.md) {
            Image(systemName: "envelope.open")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(theme.textTertiary.color)
            VStack(spacing: BrevSpacing.xs) {
                Text("No message selected", bundle: .module)
                    .brevFont(.headline)
                    .foregroundStyle(theme.textSecondary.color)
                Text("Choose a conversation from the list to read it here.", bundle: .module)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textTertiary.color)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 320)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(BrevSpacing.xl)
    }

    private var mailboxFontFamily: MailboxFontFamily {
        MailboxFontFamily(rawValue: fontFamilyRaw) ?? .system
    }

    private var mailboxTextSize: MailboxTextSize {
        MailboxTextSize(rawValue: textSizeRaw) ?? .medium
    }

    private var mailboxListDensity: MailboxListDensity {
        MailboxListDensity(rawValue: listDensityRaw) ?? .comfortable
    }

    private var readerLayout: MessageReaderLayout {
        #if os(macOS)
        MessageReaderLayoutPolicy.layout(platform: .macOS, density: mailboxListDensity)
        #else
        let usesRegularPadLayout = UIDevice.current.userInterfaceIdiom == .pad
            && horizontalSizeClass == .regular
        return MessageReaderLayoutPolicy.layout(
            platform: usesRegularPadLayout ? .iPad : .iPhone,
            density: mailboxListDensity
        )
        #endif
    }

    private func folder(for header: MessageHeader) -> Folder? {
        allFolders.first { $0.id == header.folderID }
    }

    private func htmlRenderingMode(for header: MessageHeader?) -> HTMLBodyRenderingMode {
        guard let header else {
            cancelMessageOpenTiming()
            return HTMLBodyRenderingMode.default(for: theme)
        }
        if htmlRenderingModeOverrideMessageID == header.id,
           let htmlRenderingModeOverride {
            return htmlRenderingModeOverride
        }
        return HTMLBodyRenderingMode.default(for: theme)
    }

    private func toggleHTMLRenderingMode(for header: MessageHeader) {
        let currentMode = htmlRenderingMode(for: header)
        htmlRenderingModeOverrideMessageID = header.id
        htmlRenderingModeOverride = currentMode.toggled
    }

    private func resetHTMLRenderingModeOverride() {
        htmlRenderingModeOverride = nil
        htmlRenderingModeOverrideMessageID = nil
    }

    @MainActor
    private func printCurrentMessage() {
        guard let header else { return }
        #if os(macOS)
        MessagePrintExportRenderer.presentPrintPanel(header: header, body: messageBody)
        #elseif os(iOS)
        MailPrintController.presentPrint(
            messages: [(header, messageBody)],
            jobName: header.subject
        )
        #endif
    }

    @MainActor
    private func exportCurrentMessagePDF() {
        #if os(macOS)
        guard let header else { return }
        let panel = NSSavePanel()
        panel.title = String(localized: "Export Message as PDF", bundle: .module)
        panel.nameFieldStringValue = pdfFilename(for: header)
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try MessagePrintExportRenderer.exportPDF(header: header, body: messageBody, to: url)
            attachmentSaveToast = "Exported PDF"
        } catch {
            attachmentError = MessageDetailInlineStatus(
                message: "PDF export failed: \(error.localizedDescription)",
                tone: .danger,
                isDismissible: true,
                lineLimit: nil
            )
        }
        #elseif os(iOS)
        guard let header else { return }
        do {
            let url = try MailPrintController.exportPDF(
                messages: [(header, messageBody)],
                fileName: pdfBaseName(for: header)
            )
            pdfShareURL = url
        } catch {
            attachmentError = MessageDetailInlineStatus(
                message: "PDF export failed: \(error.localizedDescription)",
                tone: .danger,
                isDismissible: true,
                lineLimit: nil
            )
        }
        #endif
    }

    private func pdfFilename(for header: MessageHeader) -> String {
        pdfBaseName(for: header) + ".pdf"
    }

    private func pdfBaseName(for header: MessageHeader) -> String {
        let fallback = header.subject.isEmpty ? "message" : header.subject
        let invalid = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return fallback.components(separatedBy: invalid).joined(separator: "_")
    }

    private var reloadKey: String {
        "\(sourceKey):\(header?.id ?? "none")"
    }

    private var sourceKey: String {
        guard let sourceID else { return "none" }
        return "\(sourceID.accountID):\(sourceID.mailboxID)"
    }

    private var messageBodyFont: Font {
        mailboxFontFamily.font(size: mailboxTextSize.bodyPointSize)
    }

    private var usesRichHTMLBodyRenderer: Bool {
        // iOS now uses the same sandboxed WKWebView + WKContentRuleList path as
        // macOS, so remote content and trackers are actually blocked (#8/#9).
        // The previous iOS-only NSAttributedString importer fetched remote
        // subresources that the pre-render detector could not fully strip, so it
        // could not honor the remote-content promise in PRIVACY.md.
        useRichRenderer
    }

    @ViewBuilder
    private func content(for header: MessageHeader) -> some View {
        let securityAnalysis = messageSecurityAnalysis(for: header)
        ScrollView {
            readerCanvas {
                VStack(alignment: .leading, spacing: BrevSpacing.md) {
                    VStack(alignment: .leading, spacing: mailboxListDensity.metadataSpacing) {
                        Text(header.subject)
                            .font(mailboxFontFamily.font(
                                size: mailboxTextSize.bodyPointSize + 5,
                                weight: .semibold
                            ))
                            .foregroundStyle(theme.textPrimary.color)
                        HStack(spacing: BrevSpacing.sm) {
                            if showSenderAvatars {
                                BrevAvatarView(
                                    email: header.from.email,
                                    displayName: header.from.name,
                                    size: mailboxListDensity.avatarSize + BrevSpacing.xs
                                )
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: BrevSpacing.xs) {
                                    Text(header.from.displayName)
                                        .font(mailboxFontFamily.font(
                                            size: mailboxTextSize.listTitlePointSize,
                                            weight: .medium
                                        ))
                                        .foregroundStyle(theme.textPrimary.color)
                                    Text(verbatim: "<\(header.from.email)>")
                                        .font(mailboxFontFamily.font(size: mailboxTextSize.captionPointSize))
                                        .foregroundStyle(theme.textTertiary.color)
                                        .lineLimit(1)
                                }
                                if !header.to.isEmpty || !header.cc.isEmpty {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            isRecipientsExpanded.toggle()
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text(recipientLine(header.to))
                                                .lineLimit(1)
                                            Image(systemName: isRecipientsExpanded
                                                ? "chevron.up" : "chevron.down")
                                                .font(.system(size: 9))
                                        }
                                        .font(mailboxFontFamily.font(size: mailboxTextSize.captionPointSize))
                                        .foregroundStyle(theme.textTertiary.color)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            Spacer()
                            Text(dateLabel)
                                .font(mailboxFontFamily.font(size: mailboxTextSize.captionPointSize))
                                .foregroundStyle(theme.textTertiary.color)
                        }
                        if isRecipientsExpanded {
                            recipientDetail(header: header)
                        }
                        labelChipRow(header: header)
                    }
                    .dynamicTypeSize(MailDenseChromeDynamicType.compactRange)

                    // No rule between the header and what follows it. The reader's
                    // content column is capped at `maximumContentWidth` while the
                    // window action bar's rule is full-bleed, so the two could
                    // never share an edge — in a detached window they read as two
                    // hairlines that almost line up. Spacing and the subject's own
                    // weight already separate the header.

                    if !messageSecurityState.summary.isEmpty {
                        securityStatusRow
                        BrevDivider()
                    }

                    if securityAnalysis.hasWarnings {
                        messageSecurityWarningSection(securityAnalysis)
                        BrevDivider()
                    }

                    if let readStatus {
                        MessageDetailStatusView(
                            status: readStatus
                        ) {
                            applyOpenReadPolicy(to: header)
                        }
                        BrevDivider()
                    }

                    if let readReceiptErrorMessage {
                        BrevInlineStatus(message: readReceiptErrorMessage, tone: .danger, lineLimit: nil)
                        BrevDivider()
                    } else if let readReceiptStatusMessage {
                        BrevInlineStatus(message: readReceiptStatusMessage, tone: .success, lineLimit: nil)
                        BrevDivider()
                    }

                    if let readReceiptRequest = visibleReadReceiptRequest(for: header) {
                        readReceiptSection(
                            request: readReceiptRequest,
                            header: header
                        )
                        BrevDivider()
                    }

                    if let readReceiptNotification = messageBody?.readReceiptNotification {
                        readReceiptNotificationSection(readReceiptNotification)
                        BrevDivider()
                    }

                    let sentReadReceiptNotifications = sentReadReceiptNotifications(for: header)
                    if messageBody?.readReceiptNotification == nil,
                       !sentReadReceiptNotifications.isEmpty {
                        sentReadReceiptNotificationSection(sentReadReceiptNotifications)
                        BrevDivider()
                    }

                    if let listUnsubscribe = MessageListUnsubscribePresentation.resolve(
                        options: messageBody?.listUnsubscribe
                    ) {
                        listUnsubscribeSection(listUnsubscribe)
                        BrevDivider()
                    }

                    if let event = calendarInviteEvent {
                        inviteSection(event, header: header)
                        BrevDivider()
                    } else if let inviteLoadStatus {
                        MessageDetailStatusView(
                            status: inviteLoadStatus
                        ) {
                            Task { await retryInviteLoad(for: header) }
                        }
                        BrevDivider()
                    }

                    senderAuthWarningBanner(for: header)

                    bodyLoadFallbackNoticeBanner

                    bodyContent(for: header)

                    if let attachments = messageBody?.attachments, !attachments.isEmpty {
                        BrevDivider()
                        attachmentsSection(attachments)
                    }
                }
            }
        }
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if navigation != nil {
                        Button {
                            presentCreateTask(for: header)
                        } label: {
                            Label(String(localized: "Create Task", bundle: .module), systemImage: "checklist")
                        }
                        .disabled(isCreateTaskDisabled)
                        Button {
                            presentFollowUp(for: header)
                        } label: {
                            Label(String(localized: "Follow Up", bundle: .module), systemImage: "flag")
                        }
                        .disabled(isFollowUpDisabled)
                    }
                    if navigation != nil, !allFolders.isEmpty {
                        Button {
                            presentMoveToFolder(for: header)
                        } label: {
                            Label(String(localized: "Move", bundle: .module), systemImage: "folder")
                        }
                        .disabled(isWorkBlocked)
                    }
                    Button {
                        printCurrentMessage()
                    } label: {
                        Label(String(localized: "Print", bundle: .module), systemImage: "printer")
                    }
                    .disabled(isLoading || errorMessage != nil)
                    Button {
                        exportCurrentMessagePDF()
                    } label: {
                        Label(String(localized: "Export PDF", bundle: .module), systemImage: "doc.richtext")
                    }
                    .disabled(isLoading || errorMessage != nil)
                    if MailDetachWindowPolicy.shouldDetach(
                        idiom: UIDevice.current.userInterfaceIdiom,
                        horizontalSizeClass: horizontalSizeClass
                    ) {
                        Button {
                            openWindow(value: DetachedReaderWindowPayload(
                                sourceID: sourceID,
                                messageID: header.id
                            ))
                        } label: {
                            Label(String(localized: "Open in New Window", bundle: .module), systemImage: "macwindow.on.rectangle")
                        }
                    }
                } label: {
                    Label(String(localized: "Message Tools", bundle: .module), systemImage: "slider.horizontal.3")
                }
            }
            #endif
            // macOS: Create Task and Move live in the root's reader cluster
            // (`BrevMailRootView.toolbarDetail`), not here — this view's
            // items append after the root's, which put them to the right of
            // the AI Sidebar toggle and outside the cluster's width-based
            // condensation. The context menu below still carries both.
        }
        .contextMenu {
            messageDetailContextMenu(for: header)
        }
        .modifier(MessageDetailLinkOpenURLModifier(
            analysis: securityAnalysis,
            onSuspiciousLink: { pendingSuspiciousLink = $0 }
        ))
    }

    @ViewBuilder
    private func readerCanvas<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        let layout = readerLayout
        if layout.usesCardSurface {
            content()
                .padding(layout.contentPadding)
                .frame(maxWidth: layout.maximumContentWidth, alignment: .leading)
                .background(
                    BrevWindowSurfaceBackground(role: .messageContent)
                        .clipShape(RoundedRectangle(cornerRadius: BrevRadius.lg, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: BrevRadius.lg, style: .continuous)
                        .stroke(theme.border.color, lineWidth: 0.5)
                )
                .padding(.horizontal, layout.outerHorizontalPadding)
                .padding(.vertical, layout.outerVerticalPadding)
                .frame(maxWidth: .infinity, alignment: .top)
        } else {
            content()
                .padding(layout.contentPadding)
                .frame(maxWidth: layout.maximumContentWidth, alignment: .leading)
                .padding(.horizontal, layout.outerHorizontalPadding)
                .padding(.vertical, layout.outerVerticalPadding)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func messageDetailContextMenu(for header: MessageHeader) -> some View {
        ForEach(MessageCommandPresentation.detailContextActions(
            canPresentSheets: navigation != nil,
            hasMoveTargets: !allFolders.isEmpty
        ), id: \.self) { action in
            switch action {
            case .createTask:
                Button {
                    presentCreateTask(for: header)
                } label: {
                    Label(String(localized: "Create Task", bundle: .module), systemImage: "checklist")
                }
                .disabled(isCreateTaskDisabled)
            case .addNote:
                Button {
                    presentMessageNote(for: header)
                } label: {
                    Label(String(localized: "Add Note", bundle: .module), systemImage: "note.text.badge.plus")
                }
                .disabled(isAddNoteDisabled)
            case .followUp:
                Button {
                    presentFollowUp(for: header)
                } label: {
                    Label(String(localized: "Follow Up", bundle: .module), systemImage: "flag")
                }
                .disabled(isFollowUpDisabled)
            case .move:
                Button {
                    presentMoveToFolder(for: header)
                } label: {
                    Label(String(localized: "Move to Folder", bundle: .module), systemImage: "folder")
                }
                .disabled(isWorkBlocked)
            }
        }
        if let junkTitle = MessageCommandPresentation.junkActionTitle(
            currentFolder: folder(for: header),
            capabilities: backend.capabilities,
            folders: allFolders
        ) {
            Button {
                DetachedMessageCommandBus.post(.setJunk, header: header, sourceID: sourceID)
            } label: {
                Label(junkTitle, systemImage: "exclamationmark.octagon")
            }
            .disabled(isWorkBlocked)
        }
    }

    private var isCreateTaskDisabled: Bool {
        guard let navigation else { return true }
        return isWorkBlocked || navigation.presentedSheet != nil
    }

    /// Notes are local-only (no backend mutation), so the only gate is whether
    /// another sheet is already presented. This matches the predicate used by the
    /// list and unified-inbox context menus and avoids a stale `isWorkBlocked`
    /// gate that would grey out the action during unrelated backend ops.
    private var isAddNoteDisabled: Bool {
        navigation?.presentedSheet != nil
    }

    private var isFollowUpDisabled: Bool {
        navigation?.presentedSheet != nil
    }

    private func presentCreateTask(for header: MessageHeader) {
        guard let navigation, !isCreateTaskDisabled else { return }
        navigation.presentedSheet = .createTask(header: header, sourceID: sourceID)
    }

    private func presentMessageNote(for header: MessageHeader) {
        guard let navigation, !isAddNoteDisabled else { return }
        navigation.presentedSheet = .messageNote(header: header, sourceID: sourceID)
    }

    private func presentFollowUp(for header: MessageHeader) {
        guard let navigation, !isFollowUpDisabled else { return }
        navigation.presentedSheet = .followUp(header: header, sourceID: sourceID)
    }

    private func presentMoveToFolder(for header: MessageHeader) {
        guard let navigation, !isWorkBlocked else { return }
        navigation.presentedSheet = .moveTo(
            messageIDs: [header.id],
            sourceID: sourceID,
            currentFolderID: header.folderID
        )
    }

    /// Whether to render the in-content action bar — true only for the standalone
    /// (detached) message window, which has no surrounding navigation toolbar.
    private var showsWindowActionBar: Bool { closeWindow != nil }

    @ViewBuilder
    private func windowActionBar(for header: MessageHeader) -> some View {
        HStack(spacing: BrevSpacing.xs) {
            windowActionButton("Reply", systemImage: "arrowshape.turn.up.left", command: .reply, header: header)
            windowActionButton("Reply All", systemImage: "arrowshape.turn.up.left.2", command: .replyAll, header: header)
            windowActionButton("Forward", systemImage: "arrowshape.turn.up.right", command: .forward, header: header)

            Rectangle()
                .fill(BrevSeparator.color(for: theme))
                .frame(width: 1, height: 18)
                .padding(.horizontal, BrevSpacing.xs)
                .accessibilityHidden(true)

            windowActionButton("Archive", systemImage: "archivebox", command: .archive, header: header)
            windowActionButton("Delete", systemImage: "trash", command: .delete, header: header)
            if !allFolders.isEmpty {
                windowActionButton("Move", systemImage: "folder", command: .move, header: header)
            }
            if let junkTitle = MessageCommandPresentation.junkActionTitle(
                currentFolder: folder(for: header),
                capabilities: backend.capabilities,
                folders: allFolders
            ) {
                windowActionButton(
                    junkTitle,
                    systemImage: "exclamationmark.octagon",
                    command: .setJunk,
                    header: header
                )
            }

            Spacer(minLength: BrevSpacing.sm)

            windowActionButton(
                MessageCommandPresentation.flagToggleTitle(for: header),
                systemImage: MessageCommandPresentation.flagToggleSymbolName(for: header),
                command: .toggleFlag,
                header: header
            )
        }
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, mailboxListDensity.chromeVerticalPadding)
        .overlay(alignment: .bottom) { BrevDivider() }
    }

    private func windowActionButton(
        _ title: String,
        systemImage: String,
        command: DetachedMessageCommand,
        header: MessageHeader
    ) -> some View {
        Button {
            DetachedMessageCommandBus.post(command, header: header, sourceID: sourceID)
            if command.dismissesWindow { closeWindow?() }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 14))
                .foregroundStyle(theme.textSecondary.color)
                .frame(width: 30, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .disabled(isWorkBlocked)
    }

    private func messageSecurityAnalysis(for header: MessageHeader) -> MessageSecurityAnalysis {
        MessageSecurityWarningPolicy.analyze(
            header: header,
            bodyHTML: messageBody?.html,
            replyTo: header.replyTo
        )
    }

    private var securityStatusRow: some View {
        HStack(spacing: BrevSpacing.xs) {
            Image(systemName: messageSecurityState.hasWarning ? "exclamationmark.shield" : "checkmark.shield")
                .foregroundStyle(
                    messageSecurityState.hasWarning
                        ? theme.warning.color
                        : theme.success.color
                )
            Text(messageSecurityState.summary)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
            Spacer(minLength: BrevSpacing.sm)
        }
        .padding(.horizontal, BrevSpacing.sm)
        .padding(.vertical, BrevSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(theme.bgSecondary.color)
        )
    }

    @ViewBuilder
    private func messageSecurityWarningSection(_ analysis: MessageSecurityAnalysis) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            BrevInlineStatus(
                message: analysis.summary ?? "Check this message before trusting it.",
                tone: .warning,
                lineLimit: nil
            )

            VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                ForEach(analysis.warnings, id: \.kind) { warning in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(warning.title)
                            .font(mailboxFontFamily.font(
                                size: mailboxTextSize.captionPointSize,
                                weight: .semibold
                            ))
                            .foregroundStyle(theme.textPrimary.color)
                        Text(warning.message)
                            .font(mailboxFontFamily.font(size: mailboxTextSize.captionPointSize))
                            .foregroundStyle(theme.textSecondary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func recipientLine(_ recipients: [Correspondent]) -> String {
        if recipients.isEmpty { return "" }
        let lead = recipients.prefix(3).map { $0.displayName }.joined(separator: ", ")
        let extra = recipients.count - 3
        return extra > 0 ? "to \(lead) + \(extra) more" : "to \(lead)"
    }

    @ViewBuilder
    private func recipientDetail(header: MessageHeader) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            if !header.to.isEmpty {
                recipientRow(label: "To", recipients: header.to)
            }
            if !header.cc.isEmpty {
                recipientRow(label: "Cc", recipients: header.cc)
            }
            if !header.bcc.isEmpty {
                recipientRow(label: "Bcc", recipients: header.bcc)
            }
        }
        .padding(.top, BrevSpacing.xs)
        .padding(.leading, showSenderAvatars ? 44 : 0) // align under the avatar's right edge
    }

    @ViewBuilder
    private func recipientRow(label: String, recipients: [Correspondent]) -> some View {
        HStack(alignment: .top, spacing: BrevSpacing.sm) {
            Text(label)
                .brevFont(.caption)
                .foregroundStyle(theme.textTertiary.color)
                .frame(width: 24, alignment: .leading)
            FlowLayout(spacing: BrevSpacing.xs) {
                ForEach(recipients, id: \.email) { recipient in
                    recipientChip(recipient)
                }
            }
        }
    }

    /// Provider label chips (Gmail labels). Only user labels are shown; the
    /// list is empty for folder-only backends, so nothing renders there.
    @ViewBuilder
    private func labelChipRow(header: MessageHeader) -> some View {
        let labels = MessageLabelPresentation.displayLabels(from: header.labels)
        if !labels.isEmpty {
            HStack(alignment: .top, spacing: BrevSpacing.sm) {
                Image(systemName: "tag")
                    .brevFont(.caption)
                    .foregroundStyle(theme.textTertiary.color)
                    .frame(width: 24, alignment: .leading)
                    .accessibilityHidden(true)
                FlowLayout(spacing: BrevSpacing.xs) {
                    ForEach(labels, id: \.self) { label in
                        Text(label)
                            .brevFont(.caption)
                            .foregroundStyle(theme.textSecondary.color)
                            .padding(.horizontal, BrevSpacing.sm)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(theme.bgSecondary.color))
                            .overlay(Capsule().stroke(theme.border.color, lineWidth: 0.5))
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "Labels: \(labels.joined(separator: ", "))", bundle: .module))
        }
    }

    @ViewBuilder
    private func recipientChip(_ recipient: Correspondent) -> some View {
        HStack(spacing: 4) {
            Text(recipient.displayName)
                .brevFont(.caption)
                .foregroundStyle(theme.textPrimary.color)
            if !(recipient.name?.isEmpty ?? true) {
                Text(recipient.email)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textTertiary.color)
            }
        }
        .padding(.horizontal, BrevSpacing.xs)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(theme.bgSecondary.color)
        )
    }

    private func visibleReadReceiptRequest(for header: MessageHeader) -> ReadReceiptRequest? {
        guard !handledReadReceiptMessageIDs.contains(header.id) else { return nil }
        return messageBody?.readReceiptRequest
    }

    @ViewBuilder
    private func readReceiptSection(request: ReadReceiptRequest, header: MessageHeader) -> some View {
        let prompt = MessageDetailPresentation.readReceiptPrompt(for: request)
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            HStack(spacing: BrevSpacing.xs) {
                Image(systemName: "envelope.badge")
                    .foregroundStyle(theme.accent.color)
                Text(prompt.title)
                    .brevFont(.headline)
                    .foregroundStyle(theme.textPrimary.color)
                Spacer()
            }
            Text(prompt.subtitle)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
            HStack(spacing: BrevSpacing.sm) {
                BrevButton(
                    isSendingReadReceipt ? "Sending..." : prompt.sendTitle,
                    style: .primary
                ) {
                    Task { await sendReadReceipt(request, for: header) }
                }
                .disabled(isSendingReadReceipt || isWorkBlocked)

                BrevButton(prompt.declineTitle, style: .secondary) {
                    declineReadReceipt(for: header)
                }
                .disabled(isSendingReadReceipt)
            }
        }
        .padding(BrevSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.bgSecondary.color)
        )
    }

    @ViewBuilder
    private func readReceiptNotificationSection(_ notification: ReadReceiptNotification) -> some View {
        let presentation = MessageDetailPresentation.readReceiptNotification(notification)
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            HStack(spacing: BrevSpacing.xs) {
                Image(systemName: presentation.icon)
                    .foregroundStyle(theme.success.color)
                Text(presentation.title)
                    .brevFont(.headline)
                    .foregroundStyle(theme.textPrimary.color)
                Spacer()
            }
            Text(presentation.subtitle)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
        }
        .padding(BrevSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.bgSecondary.color)
        )
    }

    @ViewBuilder
    private func sentReadReceiptNotificationSection(
        _ records: [MessageReadReceiptNotificationRecord]
    ) -> some View {
        let presentation = MessageDetailPresentation.sentReadReceiptNotification(records)
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            HStack(spacing: BrevSpacing.xs) {
                Image(systemName: presentation.icon)
                    .foregroundStyle(theme.success.color)
                Text(presentation.title)
                    .brevFont(.headline)
                    .foregroundStyle(theme.textPrimary.color)
                Spacer()
            }
            Text(presentation.subtitle)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
        }
        .padding(BrevSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.bgSecondary.color)
        )
    }

    private func sentReadReceiptNotifications(
        for header: MessageHeader
    ) -> [MessageReadReceiptNotificationRecord] {
        guard let originalMessageID = header.rfcMessageID else { return [] }
        return readReceiptNotificationStore.notifications(
            forOriginalMessageID: originalMessageID,
            accountID: backend.account.id
        )
    }

    private func declineReadReceipt(for header: MessageHeader) {
        handledReadReceiptMessageIDs.insert(header.id)
        readReceiptErrorMessage = nil
        readReceiptStatusMessage = "Read receipt declined."
    }

    private func sendReadReceipt(_ request: ReadReceiptRequest, for header: MessageHeader) async {
        guard !isSendingReadReceipt else { return }
        isSendingReadReceipt = true
        readReceiptErrorMessage = nil
        readReceiptStatusMessage = nil
        defer { isSendingReadReceipt = false }

        do {
            let draft = MessageReadReceiptDraftBuilder.draft(
                for: request,
                header: header,
                accountEmail: backend.account.emailAddress
            )
            if let sourceID {
                _ = try await backend.send(draft: draft, sourceID: sourceID)
            } else {
                _ = try await backend.send(draft: draft)
            }
            handledReadReceiptMessageIDs.insert(header.id)
            readReceiptStatusMessage = "Read receipt sent."
        } catch {
            readReceiptErrorMessage = "Couldn't send read receipt: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private func listUnsubscribeSection(_ presentation: MessageListUnsubscribePresentation) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            HStack(spacing: BrevSpacing.xs) {
                Image(systemName: "envelope.badge.shield.half.filled")
                    .foregroundStyle(theme.accent.color)
                Text(presentation.title)
                    .brevFont(.headline)
                    .foregroundStyle(theme.textPrimary.color)
                Spacer()
            }
            Text(presentation.subtitle)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
            if let warning = presentation.warning {
                BrevInlineStatus(message: warning, tone: .info)
            }
            HStack(spacing: BrevSpacing.sm) {
                ForEach(Array(presentation.actions.enumerated()), id: \.offset) { _, action in
                    BrevButton(action.title, style: .secondary) {
                        presentListUnsubscribeConfirmation(action)
                    }
                }
            }
        }
        .padding(BrevSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.bgSecondary.color)
        )
    }

    private func presentListUnsubscribeConfirmation(_ action: MessageListUnsubscribeActionPresentation) {
        pendingListUnsubscribeAction = action
        isShowingListUnsubscribeConfirmation = true
    }

    private func confirmListUnsubscribeAction() {
        guard let action = pendingListUnsubscribeAction else { return }
        clearPendingListUnsubscribeAction()
        openListUnsubscribeMethod(action.method)
    }

    private func clearPendingListUnsubscribeAction() {
        pendingListUnsubscribeAction = nil
        isShowingListUnsubscribeConfirmation = false
    }

    private func openListUnsubscribeMethod(_ method: ListUnsubscribeMethod) {
        switch method {
        case .https(let url, _), .mailto(let url):
            openExternalURL(url)
        }
    }

    @ViewBuilder
    private func inviteSection(_ event: CalendarEvent, header: MessageHeader) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            inviteBanner(event, header: header)

            if let inviteResponseConfirmation {
                BrevInlineStatus(
                    message: inviteResponseConfirmation.message,
                    tone: Self.inlineStatusTone(for: inviteResponseConfirmation.tone)
                ) {
                    self.inviteResponseConfirmation = nil
                }
            }
        }
    }

    @ViewBuilder
    private func inviteBanner(_ event: CalendarEvent, header: MessageHeader) -> some View {
        let responsePresentation = CalendarInviteResponsePresentation.resolve(
            header: header,
            localResponse: calendarResponse
        )
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            HStack(spacing: BrevSpacing.xs) {
                Image(systemName: "calendar")
                    .foregroundStyle(theme.accent.color)
                Text("Calendar invite", bundle: .module)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textTertiary.color)
                    .textCase(.uppercase)
                Spacer()
                if let responseLabel = responsePresentation?.label {
                    Text(responseLabel)
                        .brevFont(.caption)
                        .foregroundStyle(theme.success.color)
                }
            }
            if !event.title.isEmpty {
                Text(event.title)
                    .brevFont(.headline)
                    .foregroundStyle(theme.textPrimary.color)
            }
            HStack(spacing: BrevSpacing.xxs) {
                Image(systemName: "clock")
                    .font(.system(size: 11))
                Text(Self.formatEventRange(start: event.start, end: event.end, isAllDay: event.isAllDay))
            }
            .brevFont(.footnote)
            .foregroundStyle(theme.textSecondary.color)
            if let location = event.location, !location.isEmpty {
                HStack(spacing: BrevSpacing.xxs) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 11))
                    Text(location)
                }
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
            }
            if let organizer = event.organizer {
                Text("Organizer: \(organizer.name ?? organizer.email)", bundle: .module)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textTertiary.color)
            }

            if let inviteResponseStatus {
                BrevDivider()
                MessageDetailStatusView(
                    status: inviteResponseStatus
                ) {
                    guard let failedInviteResponse else { return }
                    Task { await respondToInvite(failedInviteResponse) }
                }
            }

            if CalendarInviteReplyRouting.supportsActions(capabilities: backend.capabilities),
               responsePresentation?.showsActions == true {
                BrevDivider()
                HStack(spacing: BrevSpacing.sm) {
                    BrevButton("Accept", style: .primary) {
                        Task { await respondToInvite(.accepted) }
                    }
                    .disabled(isInviteResponseActionBlocked)
                    BrevButton("Maybe", style: .secondary) {
                        Task { await respondToInvite(.tentative) }
                    }
                    .disabled(isInviteResponseActionBlocked)
                    BrevButton("Decline", style: .tertiary) {
                        Task { await respondToInvite(.declined) }
                    }
                    .disabled(isInviteResponseActionBlocked)
                    if isRespondingToInvite {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
        }
        .padding(BrevSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.bgSecondary.color)
        )
    }

    private func respondToInvite(_ response: AttendeeState) async {
        guard canStartInviteResponse(),
              let header else { return }
        let request = CalendarInviteResponseRequest(
            messageID: header.id,
            sourceID: sourceID,
            response: response
        )
        activeInviteResponseRequest = request
        isRespondingToInvite = true
        inviteResponseConfirmation = nil
        inviteResponseStatus = nil
        failedInviteResponse = nil
        attachmentError = nil
        do {
            let sendResult = try await sendInviteResponse(messageID: header.id, response: response)
            guard canApplyInviteResponse(request) else { return }
            calendarResponse = CalendarInviteLocalResponse(messageID: header.id, response: response)
            inviteResponseConfirmation = CalendarInviteResponsePresentation.confirmationStatus(
                for: response,
                sendResult: sendResult
            )
            finishInviteResponse(request)
        } catch is CancellationError {
            guard canApplyInviteResponse(request) else { return }
            finishInviteResponse(request)
        } catch {
            guard canApplyInviteResponse(request) else { return }
            failedInviteResponse = response
            inviteResponseConfirmation = nil
            inviteResponseStatus = MessageDetailPresentation.inviteResponseErrorStatus(for: error)
            finishInviteResponse(request)
        }
    }

    private func canStartInviteResponse() -> Bool {
        CalendarInviteResponseStartPolicy.canStartResponse(
            activeRequest: activeInviteResponseRequest,
            isBlocked: isWorkBlocked
        )
    }

    private var isInviteResponseActionBlocked: Bool {
        isRespondingToInvite || isWorkBlocked
    }

    private var dateLabel: String {
        guard let header,
              MessageListDatePresentation.isKnown(header.date)
        else {
            return MessageListDatePresentation.unknownDateLabel
        }
        return header.date.formatted(date: .abbreviated, time: .shortened)
    }

    private func canApplyInviteResponse(_ request: CalendarInviteResponseRequest) -> Bool {
        CalendarInviteResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: activeInviteResponseRequest,
            currentSourceID: navigation?.selectedSourceID ?? sourceID,
            currentMessageID: navigation?.selectedMessageID ?? header?.id
        )
    }

    private func finishInviteResponse(_ request: CalendarInviteResponseRequest) {
        guard activeInviteResponseRequest == request else { return }
        activeInviteResponseRequest = nil
        isRespondingToInvite = false
    }

    private static func formatEventRange(start: Date, end: Date?, isAllDay: Bool) -> String {
        CalendarEventRangeFormatter.string(start: start, end: end, isAllDay: isAllDay, separator: "–")
    }

    private static func inlineStatusTone(for tone: MailRootStatus.Tone) -> BrevInlineStatusTone {
        switch tone {
        case .info:
            return .info
        case .success:
            return .success
        case .warning:
            return .warning
        case .danger:
            return .danger
        }
    }

    @ViewBuilder
    private func attachmentsSection(_ attachments: [Attachment]) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            Text("\(attachments.count) attachment\(attachments.count == 1 ? "" : "s")", bundle: .module)
                .brevFont(.caption)
                .foregroundStyle(theme.textTertiary.color)
            ForEach(attachments) { attachment in
                let actions = MessageAttachmentActionPresentation.actions(
                    resourceAvailable: attachment.resource != nil,
                    isDownloading: downloadingAttachmentID != nil,
                    isWorkBlocked: isWorkBlocked
                )
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
                    if downloadingAttachmentID == attachment.id {
                        ProgressView()
                            .controlSize(.small)
                    } else if let primaryAction = MessageAttachmentActionPresentation.primaryAction(in: actions) {
                        Button {
                            Task { await runAttachmentAction(primaryAction.kind, attachment: attachment) }
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
                                Task { await runAttachmentAction(action.kind, attachment: attachment) }
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
            if let attachmentError {
                BrevInlineStatus(
                    message: attachmentError.message,
                    tone: attachmentError.tone.inlineStatusTone,
                    onDismiss: attachmentError.isDismissible ? { self.attachmentError = nil } : nil,
                    lineLimit: attachmentError.lineLimit
                )
            }
            if let saveToast = attachmentSaveToast {
                BrevToast(
                    message: saveToast,
                    tone: .success,
                    actionTitle: nil,
                    onAction: nil
                ) {
                    attachmentSaveToast = nil
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func runAttachmentAction(
        _ action: MessageAttachmentActionKind,
        attachment: Attachment
    ) async {
        switch action {
        case .preview:
            await open(attachment)
        case .save:
            await save(attachment)
        case .open:
            await openWithSystemApp(attachment)
        }
    }

    /// Save the attachment to a user-selected destination.
    private func save(_ attachment: Attachment) async {
        do {
            let url = try await downloadAttachmentFile(attachment, purpose: .savePanelStaging)
            #if canImport(AppKit)
            guard try saveAttachmentAs(url: url, suggestedName: attachment.name) != nil else {
                return
            }
            #endif
            attachmentSaveToast = "Saved \"\(MessageDetailPresentation.attachmentDisplayName(attachment.name))\""
        } catch {
            // Error is already surfaced by the helper.
        }
    }

    /// Open the attachment inline using QuickLook / system preview.
    private func open(_ attachment: Attachment) async {
        do {
            let url = try await downloadedAttachmentURL(for: attachment)
            quickLookURL = url
        } catch {
            // Error is already surfaced by the helper.
        }
    }

    /// Open the attachment with the system-default application.
    ///
    /// On macOS this calls `NSWorkspace.shared.open(_:)` after writing
    /// the file to a temporary directory. On iOS the URL is surfaced
    /// through QuickLook (a proper share-sheet is a follow-up task).
    private func openWithSystemApp(_ attachment: Attachment) async {
        do {
            let url = try await downloadedAttachmentURL(for: attachment)
            #if canImport(AppKit)
            await MainActor.run {
                _ = NSWorkspace.shared.open(url)
            }
            #else
            quickLookURL = url
            #endif
        } catch {
            // Error is already surfaced by the helper.
        }
    }

    private func downloadedAttachmentURL(for attachment: Attachment) async throws -> URL {
        if let url = MessageAttachmentDownloadedFilePolicy.reusableCachedURL(
            downloadedAttachmentURLs[attachment.id],
            fileExists: { FileManager.default.fileExists(atPath: $0.path) }
        ) {
            return url
        }
        return try await downloadAttachmentFile(attachment, purpose: .previewOrOpen)
    }

    private func downloadAttachmentFile(
        _ attachment: Attachment,
        purpose: MessageAttachmentDownloadStoragePurpose
    ) async throws -> URL {
        guard canStartAttachmentDownload(),
              attachment.resource != nil,
              let messageID = header?.id
        else {
            throw CancellationError()
        }
        let request = MessageAttachmentDownloadRequest(
            messageID: messageID,
            sourceID: sourceID,
            attachmentID: attachment.id
        )
        activeAttachmentDownloadRequest = request
        downloadingAttachmentID = attachment.id
        attachmentError = nil
        do {
            let data = try await downloadAttachment(attachment)
            guard canApplyAttachmentDownloadResponse(request) else {
                throw CancellationError()
            }
            let url = try Self.save(
                data: data,
                suggestedName: attachment.name,
                purpose: purpose
            )
            guard canApplyAttachmentDownloadResponse(request) else {
                throw CancellationError()
            }
            downloadedAttachmentURLs[attachment.id] = url
            finishAttachmentDownload(request)
            return url
        } catch is CancellationError {
            if canApplyAttachmentDownloadResponse(request) {
                finishAttachmentDownload(request)
            }
        } catch {
            if canApplyAttachmentDownloadResponse(request) {
                attachmentError = MessageDetailPresentation.attachmentDownloadErrorStatus(
                    filename: attachment.name,
                    error: error
                )
                finishAttachmentDownload(request)
            }
        }
        throw CancellationError()
    }

    private func canStartAttachmentDownload() -> Bool {
        MessageAttachmentDownloadStartPolicy.canStartDownload(
            activeRequest: activeAttachmentDownloadRequest,
            isBlocked: isWorkBlocked
        )
    }

    private func canApplyAttachmentDownloadResponse(
        _ request: MessageAttachmentDownloadRequest
    ) -> Bool {
        MessageAttachmentDownloadResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: activeAttachmentDownloadRequest,
            currentSourceID: navigation?.selectedSourceID ?? sourceID,
            currentMessageID: navigation?.selectedMessageID ?? header?.id
        )
    }

    private func finishAttachmentDownload(_ request: MessageAttachmentDownloadRequest) {
        guard activeAttachmentDownloadRequest == request else { return }
        activeAttachmentDownloadRequest = nil
        downloadingAttachmentID = nil
    }

    #if canImport(AppKit)
    @MainActor
    private func saveAttachmentAs(url: URL, suggestedName: String) throws -> URL? {
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

    /// Stage attachment bytes in app-owned temporary storage. Explicit
    /// Save on macOS copies from this staging file through `NSSavePanel`,
    /// which grants the sandbox permission for the user-selected destination.
    @discardableResult
    private static func save(
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
        let destination = Self.uniqueURL(in: directory, name: sanitized)
        try data.write(to: destination, options: .atomic)
        return destination
    }

    private static func uniqueURL(in directory: URL, name: String) -> URL {
        let filename = MessageAttachmentDownloadFilenamePolicy.uniqueFilename(
            baseName: name
        ) { candidate in
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(candidate).path
            )
        }
        return directory.appendingPathComponent(filename)
    }

    private static func formatSize(_ bytes: Int) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(bytes),
            countStyle: .file
        )
    }

    /// Returns an SF Symbol name appropriate for the attachment's file
    /// type, using `UTType` when available and falling back to `paperclip`.
    private static func fileTypeSymbol(for filename: String) -> String {
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

    /// Warns that only the cached snippet is on screen after the full body
    /// load failed. Without this the reader is indistinguishable from a
    /// genuinely short message; the underlying error goes to `bodyLoadLogger`.
    @ViewBuilder
    private var bodyLoadFallbackNoticeBanner: some View {
        if bodyLoadFallbackNotice != nil {
            BrevStatusBanner(
                style: .warning,
                title: "Showing a preview only",
                message: "The full message couldn't be downloaded.",
                action: (label: "Try Again", handler: { Task { await reload() } })
            )
        }
    }

    @ViewBuilder
    private func senderAuthWarningBanner(for header: MessageHeader) -> some View {
        let warning = MessageHeaderAnalyzer.warning(
            for: header,
            authenticationResults: messageBody?.authenticationResults
        )
        if let warning {
            switch warning {
            case .dmarcFail, .dmarcFailAndDisplayNameMismatch:
                BrevStatusBanner(
                    style: .error,
                    title: "This message failed DMARC — it may be spoofed",
                    message: "The sender's domain could not be verified. Be cautious before clicking links or acting on requests."
                )
            case .displayNameMismatch:
                BrevStatusBanner(
                    style: .warning,
                    title: "Sender name doesn't match address domain",
                    message: "The display name contains a domain that differs from the actual sender address."
                )
            }
        }
    }

    @ViewBuilder
    private func bodyContent(for header: MessageHeader) -> some View {
        let html = messageBody?.html
        let remoteContentState = html.map {
            messageRemoteContentState(for: $0, header: header)
        }
        let presentation = MessageDetailBodyPresentation.resolve(
            MessageDetailBodyPresentation.Context(
                isLoading: isLoading,
                errorMessage: errorMessage,
                html: html,
                plainText: messageBody?.plainText,
                renderedHTML: renderedHTML,
                useRichRenderer: usesRichHTMLBodyRenderer,
                isRemoteContentBlocked: remoteContentState?.isBlocked == true
            )
        )

        Group {
            switch presentation {
            case .error(let errorMessage):
                MessageDetailStatusView(
                    status: MessageDetailPresentation.bodyLoadErrorStatus(errorMessage)
                ) {
                    Task { await reload() }
                }
            case .loading:
                BrevSkeletonText(lineCount: 8)
                    .padding(.vertical, BrevSpacing.sm)
            case .richHTML(let html):
                richHTMLBody(html, header: header)
            case .remoteBlocked(let html, let plainText):
                VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                    remoteContentControls(
                        senderEmail: header.from.email,
                        state: remoteContentState ?? messageRemoteContentState(for: html, header: header)
                    )
                    if let plainText {
                        Text(plainText)
                            .font(messageBodyFont)
                            .foregroundStyle(theme.textPrimary.color)
                            .textSelection(.enabled)
                    } else {
                        Text(htmlFallback(html))
                            .font(messageBodyFont)
                            .foregroundStyle(theme.textSecondary.color)
                            .textSelection(.enabled)
                    }
                }
            case .attributedHTML:
                if let renderedHTML {
                    Text(renderedHTML)
                        .font(messageBodyFont)
                        .foregroundStyle(theme.textPrimary.color)
                        .textSelection(.enabled)
                        .tint(theme.accent.color)
                } else if let html {
                    Text(htmlFallback(html))
                        .font(messageBodyFont)
                        .foregroundStyle(theme.textSecondary.color)
                        .textSelection(.enabled)
                }
            case .plainText(let text):
                Text(text)
                    .font(messageBodyFont)
                    .foregroundStyle(theme.textPrimary.color)
                    .textSelection(.enabled)
            case .htmlFallback(let html):
                Text(htmlFallback(html))
                    .font(messageBodyFont)
                    .foregroundStyle(theme.textSecondary.color)
                    .textSelection(.enabled)
            case .empty:
                Text("No body content.", bundle: .module)
                    .font(messageBodyFont)
                    .foregroundStyle(theme.textTertiary.color)
            }
        }
    }

    @ViewBuilder
    private func richHTMLBody(_ html: String, header: MessageHeader) -> some View {
        let senderEmail = header.from.email
        let remoteContentState = messageRemoteContentState(for: html, header: header)
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            HStack {
                Spacer(minLength: BrevSpacing.sm)
                HTMLBodyRenderingModeToggleButton(
                    mode: htmlRenderingMode(for: header)
                ) {
                    toggleHTMLRenderingMode(for: header)
                }
            }

            if remoteContentState.isBlocked {
                remoteContentControls(
                    senderEmail: senderEmail,
                    state: remoteContentState
                )
            }
            HTMLBodyWebView(
                store: htmlWebViewStore,
                html: html,
                allowRemoteContent: remoteContentState.allowsRemoteContent,
                fontFamily: mailboxFontFamily,
                textSize: mailboxTextSize,
                renderingMode: htmlRenderingMode(for: header),
                onOpenURL: {
                    handleMessageLink($0, analysis: messageSecurityAnalysis(for: header))
                },
                onDidFinishRendering: {
                    finishMessageOpenTiming(messageID: header.id, renderer: .webView)
                }
            )
        }
    }

    private func messageRemoteContentState(
        for html: String,
        header: MessageHeader
    ) -> MessageRemoteContentRenderState {
        MessageRemoteContentRenderPolicy.state(
            html: html,
            senderEmail: header.from.email,
            allowRemoteContentDefault: allowRemoteContentDefault,
            loadOnce: showRemoteContent,
            policy: remoteContentPolicy
        )
    }

    private func allowsRemoteContent(html: String?, senderEmail: String) -> Bool {
        guard let html else { return allowRemoteContentDefault }
        return MessageRemoteContentRenderPolicy.state(
            html: html,
            senderEmail: senderEmail,
            allowRemoteContentDefault: allowRemoteContentDefault,
            loadOnce: showRemoteContent,
            policy: remoteContentPolicy
        ).allowsRemoteContent
    }

    private func handleMessageLink(_ url: URL, analysis: MessageSecurityAnalysis) {
        guard MessageLinkSchemePolicy.isDirectlyOpenable(url) else { return }
        guard let warning = analysis.warning(for: url) else {
            openExternalURL(url)
            return
        }
        pendingSuspiciousLink = warning
    }

    private func openExternalURL(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }

    private func openConfirmedSuspiciousLink(_ warning: MessageSecurityLinkWarning) {
        clearPendingSuspiciousLink()
        guard MessageLinkSchemePolicy.isDirectlyOpenable(warning.url) else { return }
        openExternalURL(warning.url)
    }

    private func clearPendingSuspiciousLink() {
        pendingSuspiciousLink = nil
    }

    @ViewBuilder
    private func remoteContentControls(
        senderEmail: String,
        state: MessageRemoteContentRenderState
    ) -> some View {
        let presentation = MessageRemoteContentPrivacyPresentation.resolve(state)
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: BrevSpacing.xs) {
                Image(systemName: "eye.slash")
                Text(presentation.title)
                    .brevFont(.headline)
                Spacer()
            }
            .foregroundStyle(theme.textPrimary.color)

            Text(presentation.explanation)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: BrevSpacing.xs) {
                    remoteContentActionButtons(
                        primaryActionTitle: presentation.primaryActionTitle,
                        senderEmail: senderEmail,
                        senderDomain: state.senderDomain
                    )
                }
                VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                    remoteContentActionButtons(
                        primaryActionTitle: presentation.primaryActionTitle,
                        senderEmail: senderEmail,
                        senderDomain: state.senderDomain
                    )
                }
            }
        }
        .padding(.horizontal, BrevSpacing.sm)
        .padding(.vertical, BrevSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(theme.bgSecondary.color)
        )
    }

    @ViewBuilder
    private func remoteContentActionButtons(
        primaryActionTitle: String,
        senderEmail: String,
        senderDomain: String?
    ) -> some View {
        BrevButton(primaryActionTitle, style: .primary) {
            loadRemoteContentOnce()
        }
        BrevButton("Always allow sender", style: .secondary) {
            allowRemoteContentSender(senderEmail)
        }
        if let senderDomain {
            BrevButton("Always allow \(senderDomain)", style: .tertiary) {
                allowRemoteContentDomain(senderDomain)
            }
        }
        BrevButton("Keep blocked", style: .tertiary) {
            showRemoteContent = false
        }
    }

    private func loadRemoteContentOnce() {
        showRemoteContent = true
        refreshRenderedHTMLForCurrentRemoteContentDecision()
    }

    private func allowRemoteContentSender(_ senderEmail: String) {
        var policy = remoteContentPolicy
        policy.allow(senderEmail: senderEmail)
        persistRemoteContentPolicy(policy)
    }

    private func allowRemoteContentDomain(_ domain: String) {
        var policy = remoteContentPolicy
        policy.allow(domain: domain)
        persistRemoteContentPolicy(policy)
    }

    private func persistRemoteContentPolicy(_ policy: RemoteContentPolicy) {
        remoteContentPolicy = policy
        policy.save()
        showRemoteContent = true
        refreshRenderedHTMLForCurrentRemoteContentDecision()
    }

    private func refreshRenderedHTMLForCurrentRemoteContentDecision() {
        guard !usesRichHTMLBodyRenderer else { return }
        Task {
            renderedHTML = await Self.renderHTML(
                messageBody?.html,
                useRichRenderer: usesRichHTMLBodyRenderer,
                allowRemoteContent: true
            )
        }
    }

    private func htmlFallback(_ html: String) -> String {
        // Trivial tag strip; used only when NSAttributedString HTML
        // import fails (malformed payload, unexpected encoding, etc.).
        let stripped = html.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        return stripped
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func reload() async {
        guard let header else {
            postVisibleEnrichmentTask?.cancel()
            postVisibleEnrichmentTask = nil
            activeLoadRequest = nil
            activeOpenReadRequest = nil
            activeAttachmentDownloadRequest = nil
            activeInviteResponseRequest = nil
            needsReloadAfterWorkUnblocks = false
            resetState(for: .messageUnavailable)
            return
        }
        let request = MessageDetailLoadRequest(messageID: header.id, sourceID: sourceID)
        guard canStartLoad(request) else {
            rememberReloadAfterWorkUnblocks()
            return
        }
        needsReloadAfterWorkUnblocks = false
        postVisibleEnrichmentTask?.cancel()
        postVisibleEnrichmentTask = nil
        activeLoadRequest = request
        activeOpenReadRequest = nil
        activeAttachmentDownloadRequest = nil
        activeInviteResponseRequest = nil
        beginMessageOpenTiming(messageID: header.id)
        resetState(for: .messageLoadStarted)
        if let previewText = MessageDetailPresentation.previewFallbackPlainText(header.snippet) {
            messageBody = MessageBody(messageID: header.id, plainText: previewText)
        }
        isLoading = true
        do {
            let loaded = try await bodyWithReaderTimeout(for: header.id)
            recordReadReceiptNotificationIfNeeded(loaded, header: header)
            let rendered = await bodyRenderer.render(loaded)
            guard canApplyOrFinishLoad(request) else { return }
            messageBody = MessageDetailPresentation.displayBody(
                loaded: loaded,
                rendered: rendered,
                fallbackSnippet: header.snippet
            )
            messageSecurityState = rendered.securityState
            isLoading = false
            renderedHTML = await Self.renderHTML(
                rendered.html,
                useRichRenderer: usesRichHTMLBodyRenderer,
                allowRemoteContent: allowsRemoteContent(
                    html: rendered.html,
                    senderEmail: header.from.email
                )
            )
            guard canApplyOrFinishLoad(request) else { return }
            if MessageOpenRenderCompletionPolicy.stage(
                hasHTML: rendered.html != nil,
                usesRichRenderer: usesRichHTMLBodyRenderer
            ) == .bodyState {
                await Task.yield()
                finishMessageOpenTiming(messageID: header.id, renderer: .bodyState)
            }
            applyOpenReadPolicy(to: header)
            finishLoad(request)
            schedulePostVisibleEnrichment(
                loaded: loaded,
                rendered: rendered,
                header: header,
                request: request
            )
        } catch is CancellationError {
            guard canApplyOrFinishLoad(request) else { return }
            cancelMessageOpenTiming(messageID: header.id)
            finishLoad(request)
        } catch {
            guard canApplyOrFinishLoad(request) else { return }
            failMessageOpenTiming(messageID: header.id, error: error)
            switch MessageDetailPresentation.bodyLoadFailureOutcome(
                error: error,
                hasDisplayedFallbackBody: messageBody != nil
            ) {
            case .surfaceError(let message):
                resetState(for: .bodyLoadFailed)
                errorMessage = message
            case .surfaceFallbackNotice(let reason):
                errorMessage = nil
                bodyLoadFallbackNotice = reason
                Self.bodyLoadLogger.error(
                    "Body load failed; keeping snippet fallback: \(reason, privacy: .private)"
                )
            }
            finishLoad(request)
        }
    }

    private func canApplyLoadResponse(_ request: MessageDetailLoadRequest) -> Bool {
        MessageDetailLoadResponsePolicy.canApplyLoadResponse(
            request: request,
            activeRequest: activeLoadRequest,
            currentSourceID: navigation?.selectedSourceID ?? sourceID,
            currentMessageID: navigation?.selectedMessageID ?? header?.id
        )
    }

    private func canApplyOrFinishLoad(_ request: MessageDetailLoadRequest) -> Bool {
        guard canApplyLoadResponse(request) else {
            finishLoad(request)
            return false
        }
        return true
    }

    private func canApplyPostVisibleResponse(_ request: MessageDetailLoadRequest) -> Bool {
        MessageDetailLoadResponsePolicy.canApplyLoadResponse(
            request: request,
            activeRequest: request,
            currentSourceID: navigation?.selectedSourceID ?? sourceID,
            currentMessageID: navigation?.selectedMessageID ?? header?.id
        )
    }

    private func schedulePostVisibleEnrichment(
        loaded: MessageBody,
        rendered: RenderedBody,
        header: MessageHeader,
        request: MessageDetailLoadRequest
    ) {
        postVisibleEnrichmentTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            let resolvedHTML = await MessageInlineCIDRenderPolicy.rewriteCIDImageSources(
                in: rendered.html,
                attachments: rendered.attachments
            ) { attachment in
                try await downloadAttachment(attachment)
            }
            guard !Task.isCancelled, canApplyPostVisibleResponse(request) else { return }
            if resolvedHTML != rendered.html {
                messageBody = MessageDetailPresentation.displayBody(
                    loaded: loaded,
                    rendered: RenderedBody(
                        html: resolvedHTML,
                        plainText: rendered.plainText,
                        attachments: rendered.attachments,
                        securityState: rendered.securityState
                    ),
                    fallbackSnippet: header.snippet
                )
                renderedHTML = await Self.renderHTML(
                    resolvedHTML,
                    useRichRenderer: usesRichHTMLBodyRenderer,
                    allowRemoteContent: allowsRemoteContent(
                        html: resolvedHTML,
                        senderEmail: header.from.email
                    )
                )
            }
            guard !Task.isCancelled, canApplyPostVisibleResponse(request) else { return }
            await loadInviteIfPresent(
                in: rendered.attachments,
                request: request,
                allowsPostVisibleUpdates: true
            )
        }
    }

    private func canStartLoad(_ request: MessageDetailLoadRequest) -> Bool {
        MessageDetailLoadStartPolicy.canStartLoad(
            request: request,
            activeRequest: activeLoadRequest,
            isBlocked: isWorkBlocked
        )
    }

    private func finishLoad(_ request: MessageDetailLoadRequest) {
        guard activeLoadRequest == request else { return }
        activeLoadRequest = nil
        isLoading = false
    }

    private func beginMessageOpenTiming(messageID: MessageHeader.ID) {
        cancelMessageOpenTiming()
        messageOpenInterval = MailUIPerformanceDiagnostics.beginInterval("Message Open")
        messageOpenMessageID = messageID
    }

    private func finishMessageOpenTiming(
        messageID: MessageHeader.ID,
        renderer: MailUIPerformanceDiagnostics.BodyVisibilityRenderer
    ) {
        guard messageOpenMessageID == messageID, let interval = messageOpenInterval else { return }
        messageOpenInterval = nil
        messageOpenMessageID = nil
        MailUIPerformanceDiagnostics.logBodyVisible(interval: interval, renderer: renderer)
    }

    private func failMessageOpenTiming(messageID: MessageHeader.ID, error: any Error) {
        guard messageOpenMessageID == messageID, let interval = messageOpenInterval else { return }
        messageOpenInterval = nil
        messageOpenMessageID = nil
        MailUIPerformanceDiagnostics.logBodyOpenFailed(interval: interval, error: error)
    }

    private func cancelMessageOpenTiming(messageID: MessageHeader.ID? = nil) {
        guard messageID == nil || messageOpenMessageID == messageID else { return }
        if let interval = messageOpenInterval {
            MailUIPerformanceDiagnostics.endInterval(interval)
        }
        messageOpenInterval = nil
        messageOpenMessageID = nil
    }

    private func resetState(for reason: MessageDetailStateResetReason) {
        for field in MessageDetailStateResetPolicy.clearedFields(for: reason) {
            switch field {
            case .messageBody:
                messageBody = nil
                messageSecurityState = .none
            case .renderedHTML:
                renderedHTML = nil
            case .bodyLoadError:
                errorMessage = nil
            case .bodyLoadFallbackNotice:
                bodyLoadFallbackNotice = nil
            case .loading:
                isLoading = false
            case .readStatus:
                readStatus = nil
            case .downloadingAttachment:
                downloadingAttachmentID = nil
            case .attachmentError:
                attachmentError = nil
            case .recipientsExpansion:
                isRecipientsExpanded = false
            case .parsedInvite:
                parsedInvite = nil
                calendarInviteEvent = nil
            case .inviteLoadStatus:
                inviteLoadStatus = nil
            case .remoteContentOverride:
                showRemoteContent = false
            case .calendarResponse:
                calendarResponse = nil
            case .inviteResponseConfirmation:
                inviteResponseConfirmation = nil
            case .inviteResponseStatus:
                inviteResponseStatus = nil
            case .failedInviteResponse:
                failedInviteResponse = nil
            case .inviteResponseProgress:
                isRespondingToInvite = false
            case .listUnsubscribeConfirmation:
                clearPendingListUnsubscribeAction()
            case .quickLookPreview:
                quickLookURL = nil
            }
        }
    }

    private func applyOpenReadPolicy(to header: MessageHeader) {
        switch MessageOpenReadPolicy.operation(for: header) {
        case .none:
            activeOpenReadRequest = nil
            readStatus = nil
        case .markRead(let messageID, let folderID):
            let request = MessageOpenReadRequest(
                messageID: messageID,
                sourceID: sourceID,
                folderID: folderID
            )
            guard canStartOpenRead(request) else { return }
            let rollback = MessageOpenReadRollback(header: header)
            activeOpenReadRequest = request
            readStatus = nil
            navigation?.updateHeader(id: messageID) { $0.isRead = true }
            Task { @MainActor [backend, sourceID, navigation, rollback, request] in
                do {
                    if let sourceID {
                        try await backend.setRead(true, for: [messageID], sourceID: sourceID)
                    } else {
                        try await backend.setRead(true, for: [messageID])
                    }
                    guard canApplyOpenReadResponse(request) else { return }
                    readStatus = nil
                    navigation?.requestReloadIfVisibleFolderChanged(
                        .messagesUpdated(folderID: folderID, messageIDs: [messageID])
                    )
                    finishOpenRead(request)
                } catch is CancellationError {
                    guard canApplyOpenReadResponse(request) else { return }
                    finishOpenRead(request)
                } catch {
                    guard canApplyOpenReadResponse(request) else { return }
                    rollback.restore(navigation: navigation)
                    readStatus = MessageDetailPresentation.markReadErrorStatus(for: error)
                    finishOpenRead(request)
                }
            }
        }
    }

    private func canStartOpenRead(_ request: MessageOpenReadRequest) -> Bool {
        MessageOpenReadStartPolicy.canStartOpenRead(
            request: request,
            activeRequest: activeOpenReadRequest,
            isBlocked: isWorkBlocked
        )
    }

    private func canApplyOpenReadResponse(_ request: MessageOpenReadRequest) -> Bool {
        MessageOpenReadResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: activeOpenReadRequest,
            currentSourceID: navigation?.selectedSourceID ?? sourceID,
            currentMessageID: navigation?.selectedMessageID ?? header?.id
        )
    }

    private func finishOpenRead(_ request: MessageOpenReadRequest) {
        guard activeOpenReadRequest == request else { return }
        activeOpenReadRequest = nil
    }

    private func retryInviteLoad(for header: MessageHeader) async {
        let request = MessageDetailLoadRequest(messageID: header.id, sourceID: sourceID)
        guard canStartLoad(request) else {
            rememberReloadAfterWorkUnblocks()
            return
        }
        needsReloadAfterWorkUnblocks = false
        activeLoadRequest = request
        await loadInviteIfPresent(in: messageBody?.attachments ?? [], request: request)
        finishLoad(request)
    }

    private func rememberReloadAfterWorkUnblocks() {
        if isWorkBlocked {
            needsReloadAfterWorkUnblocks = true
        }
    }

    private func loadInviteIfPresent(
        in attachments: [Attachment],
        request: MessageDetailLoadRequest,
        allowsPostVisibleUpdates: Bool = false
    ) async {
        func canApplyInviteResponse() -> Bool {
            allowsPostVisibleUpdates
                ? canApplyPostVisibleResponse(request)
                : canApplyLoadResponse(request)
        }
        guard let invite = attachments.first(where: {
            $0.mimeType.lowercased().hasPrefix("text/calendar") && $0.resource != nil
        }) else { return }
        do {
            let data = try await downloadAttachment(invite)
            guard canApplyInviteResponse() else { return }
            guard let raw = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1),
                let parsed = ICSParser.parseFirstEvent(from: raw)
            else {
                await MainActor.run {
                    guard canApplyInviteResponse() else { return }
                    parsedInvite = nil
                    calendarInviteEvent = nil
                    inviteLoadStatus = MessageDetailPresentation.inviteParseErrorStatus(
                        filename: invite.name
                    )
                }
                return
            }
            await MainActor.run {
                guard canApplyInviteResponse() else { return }
                guard let displayEvent = CalendarInviteDisplayEvent.makeCalendarEvent(from: parsed) else {
                    parsedInvite = nil
                    calendarInviteEvent = nil
                    inviteLoadStatus = MessageDetailPresentation.inviteParseErrorStatus(
                        filename: invite.name
                    )
                    return
                }
                parsedInvite = parsed
                calendarInviteEvent = displayEvent
                inviteLoadStatus = nil
            }
        } catch is CancellationError {
            guard canApplyInviteResponse() else { return }
        } catch {
            await MainActor.run {
                guard canApplyInviteResponse() else { return }
                parsedInvite = nil
                calendarInviteEvent = nil
                inviteLoadStatus = MessageDetailPresentation.inviteLoadErrorStatus(for: error)
            }
        }
    }

    private func recordReadReceiptNotificationIfNeeded(
        _ body: MessageBody,
        header: MessageHeader
    ) {
        guard let notification = body.readReceiptNotification else { return }
        readReceiptNotificationStore.record(
            notification,
            receiptMessageID: body.messageID,
            receivedAt: header.date,
            accountID: backend.account.id
        )
    }

    private func body(for messageID: String) async throws -> MessageBody {
        if let sourceID {
            return try await backend.body(for: messageID, sourceID: sourceID)
        }
        return try await backend.body(for: messageID)
    }

    private func bodyWithReaderTimeout(for messageID: String) async throws -> MessageBody {
        try await MessageBodyLoadTimeoutRace.load(
            messageID: messageID,
            sourceID: sourceID,
            backend: backend,
            timeoutNanoseconds: Self.bodyLoadTimeoutNanoseconds,
            timeoutError: { MessageDetailBodyLoadTimeoutError() }
        )
    }

    private func downloadAttachment(_ attachment: Attachment) async throws -> Data {
        if let sourceID {
            return try await backend.downloadAttachment(attachment, sourceID: sourceID)
        }
        return try await backend.downloadAttachment(attachment)
    }

    private func replyToCalendarInvite(
        messageID: String,
        response: AttendeeState
    ) async throws {
        if let sourceID {
            try await backend.replyToCalendarInvite(
                messageID: messageID,
                response: response,
                sourceID: sourceID
            )
        } else {
            try await backend.replyToCalendarInvite(messageID: messageID, response: response)
        }
    }

    private func sendInviteResponse(messageID: String, response: AttendeeState) async throws -> SendResult? {
        switch CalendarInviteReplyRouting.route(for: backend.capabilities) {
        case .serverSide:
            try await replyToCalendarInvite(messageID: messageID, response: response)
            return nil
        case .clientSideIMIP:
            guard let parsedInvite else {
                throw MailBackendError.backendSpecific(message: "Calendar invite is not loaded.")
            }
            let payload = try CalendarInviteClientReplyComposer.compose(
                event: parsedInvite,
                response: response,
                account: backend.account,
                messageID: messageID
            )
            let attachmentID: String
            if let sourceID {
                attachmentID = try await backend.uploadAttachment(
                    draftID: payload.draft.id,
                    data: payload.attachmentData,
                    filename: payload.filename,
                    mimeType: payload.mimeType,
                    sourceID: sourceID
                )
            } else {
                attachmentID = try await backend.uploadAttachment(
                    draftID: payload.draft.id,
                    data: payload.attachmentData,
                    filename: payload.filename,
                    mimeType: payload.mimeType
                )
            }
            var draft = payload.draft
            draft.attachmentIDs = [attachmentID]
            if let sourceID {
                return try await backend.send(draft: draft, sourceID: sourceID)
            } else {
                return try await backend.send(draft: draft)
            }
        case .unsupported:
            throw MailBackendError.notSupported(backend.capabilities)
        }
    }

    /// Imports an HTML payload through `NSAttributedString` and
    /// returns it as a SwiftUI `AttributedString` with inline
    /// foreground colors stripped (the theme owns text color).
    ///
    /// Returns `nil` when there is no HTML, when the importer fails
    /// (rare but possible with malformed payloads), or when the
    /// payload is implausibly large (>1 MiB) — at that point the
    /// importer cost dwarfs any reading benefit.
    @MainActor
    private static func renderHTML(
        _ html: String?,
        useRichRenderer: Bool,
        allowRemoteContent: Bool
    ) async -> AttributedString? {
        guard MessageHTMLRenderPolicy.shouldImportAttributedHTML(
            html,
            useRichRenderer: useRichRenderer,
            allowRemoteContent: allowRemoteContent
        ) else { return nil }
        return await MessageHTMLImporter.importAttributedHTML(html)
    }
}

private struct MessageDetailLinkOpenURLModifier: ViewModifier {
    @Environment(\.openURL) private var openURL

    let analysis: MessageSecurityAnalysis
    let onSuspiciousLink: (MessageSecurityLinkWarning) -> Void

    func body(content: Content) -> some View {
        content.environment(\.openURL, OpenURLAction { url in
            guard MessageLinkSchemePolicy.isDirectlyOpenable(url) else { return .handled }
            if let warning = analysis.warning(for: url) {
                onSuspiciousLink(warning)
            } else {
                openURL(url)
            }
            return .handled
        })
    }
}

private struct MessageDetailBodyLoadTimeoutError: LocalizedError {
    var errorDescription: String? {
        String(localized: "Message content is taking too long to load. Check the connection and try again.", bundle: .module)
    }
}

struct MessageDetailStatusView: View {
    @Environment(\.brevTheme) private var theme
    let status: MessageDetailStatus
    let onAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            Image(systemName: status.icon)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(theme.danger.color)
            Text(status.title)
                .brevFont(.headline)
                .foregroundStyle(theme.textPrimary.color)
            Text(status.subtitle)
                .brevFont(.body)
                .foregroundStyle(theme.textTertiary.color)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle = status.actionTitle,
               let onAction {
                Button(actionTitle, action: onAction)
                    .buttonStyle(.borderless)
                    .foregroundStyle(theme.accent.color)
            }
        }
        .padding(.vertical, BrevSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension MessageDetailInlineStatus.Tone {
    var inlineStatusTone: BrevInlineStatusTone {
        switch self {
        case .danger:
            return .danger
        }
    }
}
