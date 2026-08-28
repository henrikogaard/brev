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
import SwiftUI

/// One expandable card in a `ThreadConversationView` conversation stack.
///
/// Body is loaded lazily on first expansion and cached for the view's lifetime.
/// Tapping the collapsed header toggles expansion by calling `onToggle`.
struct ThreadMessageCard: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.openURL) private var openURL

    let header: MessageHeader
    let isExpanded: Bool
    let isSelected: Bool
    let backend: any MailBackend
    let sourceID: MailSourceID?
    let showsAvatar: Bool
    let isWorkBlocked: Bool
    let dateTextOverride: String?
    let onToggle: () -> Void

    @State private var renderedBody: RenderedBody?
    @State private var renderedHTML: AttributedString?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var parsedInvite: ICSParser.ParsedEvent?
    @State private var calendarInviteEvent: CalendarEvent?
    @State private var inviteLoadErrorMessage: String?
    @State private var loadedInviteMessageID: MessageHeader.ID?
    @State private var calendarResponse: CalendarInviteLocalResponse?
    @State private var inviteResponseConfirmation: MailRootStatus?
    @State private var inviteResponseErrorMessage: String?
    @State private var failedInviteResponse: AttendeeState?
    @State private var activeInviteResponseRequest: CalendarInviteResponseRequest?
    @State private var isRespondingToInvite = false
    @State private var showRemoteContent = false
    @State private var htmlRenderingModeOverride: HTMLBodyRenderingMode?
    @State private var htmlRenderingModeOverrideMessageID: MessageHeader.ID?
    @State private var inlineCIDResolvedMessageID: MessageHeader.ID?
    @State private var pendingSuspiciousLink: MessageSecurityLinkWarning?
    @StateObject private var htmlWebViewStore = HTMLBodyWebViewStore()

    @AppStorage(MailboxViewPreferenceKey.useRichRenderer) private var useRichRenderer = true
    @AppStorage(MailboxViewPreferenceKey.allowRemoteContent) private var allowRemoteContentDefault = false
    @AppStorage(MailboxViewPreferenceKey.fontFamily) private var fontFamilyRaw = MailboxFontFamily.system.rawValue
    @AppStorage(MailboxViewPreferenceKey.textSize) private var textSizeRaw = MailboxTextSize.medium.rawValue

    private let bodyRenderer = BodyRenderer()
    private static let bodyLoadTimeoutNanoseconds: UInt64 = 15_000_000_000

    private var denseChromeDynamicTypeRange: PartialRangeThrough<DynamicTypeSize> {
        MailDenseChromeDynamicType.compactRange
    }

    init(
        header: MessageHeader,
        isExpanded: Bool,
        isSelected: Bool = false,
        backend: any MailBackend,
        sourceID: MailSourceID?,
        showsAvatar: Bool = true,
        isWorkBlocked: Bool = false,
        dateTextOverride: String? = nil,
        initialRenderedBody: RenderedBody? = nil,
        onToggle: @escaping () -> Void
    ) {
        self.header = header
        self.isExpanded = isExpanded
        self.isSelected = isSelected
        self.backend = backend
        self.sourceID = sourceID
        self.showsAvatar = showsAvatar
        self.isWorkBlocked = isWorkBlocked
        self.dateTextOverride = dateTextOverride
        self.onToggle = onToggle
        _renderedBody = State(initialValue: initialRenderedBody)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Card header — always visible, tappable to toggle
            cardHeader
                .dynamicTypeSize(denseChromeDynamicTypeRange)
                .contentShape(Rectangle())
                .onTapGesture { onToggle() }

            // Card body — shown only when expanded
            if isExpanded {
                Divider()
                cardBody
                    .padding(BrevSpacing.sm)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: BrevRadius.md, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BrevRadius.md, style: .continuous)
                .stroke(
                    isSelected ? theme.accent.color : theme.border.color.opacity(0.45),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
        )
        .padding(.horizontal, BrevSpacing.sm)
        .padding(.vertical, BrevSpacing.xxs)
        .task(id: isExpanded) {
            guard isExpanded, !isLoading else { return }
            if renderedBody == nil {
                await loadBody()
            } else {
                await updateDerivedBodyState()
            }
        }
        .alert(
            pendingSuspiciousLink?.confirmationTitle ?? "Open suspicious link?",
            isPresented: Binding(
                get: { pendingSuspiciousLink != nil },
                set: { if !$0 { pendingSuspiciousLink = nil } }
            ),
            presenting: pendingSuspiciousLink
        ) { warning in
            Button(warning.openButtonTitle) {
                pendingSuspiciousLink = nil
                openURL(warning.url)
            }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) { pendingSuspiciousLink = nil }
        } message: { warning in
            Text(warning.confirmationMessage)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Routes a tapped link through the same phishing/deceptive-link check the
    /// single-message reader uses: a flagged link prompts for confirmation
    /// instead of opening directly.
    private func handleLink(_ url: URL, bodyHTML: String) {
        guard MessageLinkSchemePolicy.isDirectlyOpenable(url) else { return }
        let analysis = MessageSecurityWarningPolicy.analyze(
            header: header,
            bodyHTML: bodyHTML,
            replyTo: header.replyTo
        )
        if let warning = analysis.warning(for: url) {
            pendingSuspiciousLink = warning
        } else {
            openURL(url)
        }
    }

    // MARK: - Subviews

    private var cardHeader: some View {
        HStack(spacing: BrevSpacing.sm) {
            if showsAvatar {
                BrevAvatarView(
                    email: header.from.email,
                    displayName: header.from.name,
                    size: 40
                )
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(header.from.name ?? header.from.email)
                        .font(.subheadline)
                        .fontWeight(header.isRead ? .regular : .semibold)
                        .foregroundStyle(theme.textPrimary.color)
                        .lineLimit(1)

                    Spacer()

                    if let dateTextOverride {
                        Text(dateTextOverride)
                            .font(.caption)
                            .foregroundStyle(theme.textTertiary.color)
                    } else {
                        Text(header.date, style: .relative)
                            .font(.caption)
                            .foregroundStyle(theme.textTertiary.color)
                    }
                }

                if !isExpanded {
                    Text(header.snippet)
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary.color)
                        .lineLimit(1)
                } else {
                    recipientSummary
                }
            }

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption2)
                .foregroundStyle(theme.textTertiary.color)
        }
        .padding(BrevSpacing.sm)
    }

    private var cardBackground: Color {
        if isSelected { return theme.selection.color }
        if isExpanded { return theme.bgSecondary.color.opacity(0.42) }
        return Color.clear
    }

    @ViewBuilder
    private var recipientSummary: some View {
        let toText = header.to.map { $0.name ?? $0.email }.joined(separator: ", ")
        if !toText.isEmpty {
            Text("To: \(toText)", bundle: .module)
                .font(.caption)
                .foregroundStyle(theme.textSecondary.color)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var cardBody: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.md) {
            securitySummary
            inviteContent
            bodyContent
        }
    }

    @ViewBuilder
    private var securitySummary: some View {
        if let renderedBody,
           !renderedBody.securityState.summary.isEmpty {
            HStack(spacing: BrevSpacing.xs) {
                Image(systemName: renderedBody.securityState.hasWarning ? "exclamationmark.shield" : "checkmark.shield")
                    .foregroundStyle(
                        renderedBody.securityState.hasWarning
                            ? theme.warning.color
                            : theme.success.color
                    )
                Text(renderedBody.securityState.summary)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
            }
            .padding(.horizontal, BrevSpacing.sm)
            .padding(.vertical, BrevSpacing.xxs)
            .background(theme.bgSecondary.color.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: BrevRadius.sm))
            .overlay {
                RoundedRectangle(cornerRadius: BrevRadius.sm)
                    .stroke(theme.border.color.opacity(0.45), lineWidth: 0.5)
            }
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch ThreadMessageBodyPresentation.resolve(bodyPresentationContext) {
        case .loading:
            HStack {
                Spacer()
                ProgressView()
                    .tint(theme.accent.color)
                Spacer()
            }
            .padding(BrevSpacing.lg)

        case .error(let errorMessage):
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(theme.textSecondary.color)
                .padding(BrevSpacing.md)

        case .plainText(let text):
            Text(text)
                .font(messageBodyFont)
                .foregroundStyle(theme.textPrimary.color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .attributedHTML(let html):
            if let renderedHTML {
                Text(renderedHTML)
                    .font(messageBodyFont)
                    .foregroundStyle(theme.textPrimary.color)
                    .textSelection(.enabled)
                    .tint(theme.accent.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(ThreadMessageBodyPresentation.htmlFallback(html))
                    .font(messageBodyFont)
                    .foregroundStyle(theme.textSecondary.color)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .richHTML(let html, let allowRemoteContent, let showsRemoteContentBanner):
            VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                HStack {
                    Spacer(minLength: BrevSpacing.sm)
                    HTMLBodyRenderingModeToggleButton(
                        mode: htmlRenderingMode
                    ) {
                        toggleHTMLRenderingMode()
                    }
                }

                if showsRemoteContentBanner {
                    HStack(spacing: BrevSpacing.xs) {
                        Image(systemName: "eye.slash")
                        Text("Remote content blocked", bundle: .module)
                            .brevFont(.caption)
                        Spacer(minLength: BrevSpacing.sm)
                        BrevButton(MessageRemoteContentPrivacyPresentation.downloadImagesActionTitle, style: .secondary) {
                            showRemoteContent = true
                        }
                    }
                    .foregroundStyle(theme.textSecondary.color)
                    .padding(.horizontal, BrevSpacing.sm)
                    .padding(.vertical, BrevSpacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(theme.bgTertiary.color)
                    )
                }
                HTMLBodyWebView(
                    store: htmlWebViewStore,
                    html: html,
                    allowRemoteContent: allowRemoteContent,
                    fontFamily: mailboxFontFamily,
                    textSize: mailboxTextSize,
                    renderingMode: htmlRenderingMode,
                    onOpenURL: { handleLink($0, bodyHTML: html) }
                )
            }

        case .htmlFallback(let text):
            Text(text.isEmpty ? "(No body)" : text)
                .font(messageBodyFont)
                .foregroundStyle(theme.textSecondary.color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .empty:
            Text("(No body)", bundle: .module)
                .font(messageBodyFont)
                .foregroundStyle(theme.textTertiary.color)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .waiting:
            Color.clear.frame(height: 1)
        }
    }

    @ViewBuilder
    private var inviteContent: some View {
        if let presentation = ThreadCalendarInvitePresentation.resolve(
            header: header,
            renderedBody: renderedBody,
            capabilities: backend.capabilities,
            localResponse: calendarResponse
        ) {
            if let calendarInviteEvent {
                ThreadCalendarInviteCard(
                    event: calendarInviteEvent,
                    presentation: presentation,
                    confirmation: inviteResponseConfirmation,
                    errorMessage: inviteResponseErrorMessage,
                    failedResponse: failedInviteResponse,
                    isResponding: isRespondingToInvite,
                    isBlocked: isWorkBlocked
                ) { response in
                    Task { await respondToInvite(response) }
                } onRetry: { response in
                    Task { await respondToInvite(response) }
                } onDismissConfirmation: {
                    inviteResponseConfirmation = nil
                }
            } else if let inviteLoadErrorMessage {
                BrevInlineStatus(
                    message: inviteLoadErrorMessage,
                    tone: .warning
                ) {
                    self.inviteLoadErrorMessage = nil
                }
            }
        }
    }

    private var mailboxFontFamily: MailboxFontFamily {
        MailboxFontFamily(rawValue: fontFamilyRaw) ?? .system
    }

    private var mailboxTextSize: MailboxTextSize {
        MailboxTextSize(rawValue: textSizeRaw) ?? .medium
    }

    private var messageBodyFont: Font {
        MessageBodyStyle.resolve(
            theme: theme,
            fontFamily: mailboxFontFamily,
            textSize: mailboxTextSize,
            renderingMode: .original,
            bodyInsetPoints: 0
        ).swiftUIBodyFont
    }

    private var usesRichHTMLBodyRenderer: Bool {
        // iOS now uses the same sandboxed WKWebView + WKContentRuleList path as
        // macOS, so remote content and trackers are actually blocked (#8/#9).
        // The previous iOS-only NSAttributedString importer fetched remote
        // subresources that the pre-render detector could not fully strip, so it
        // could not honor the remote-content promise in PRIVACY.md. This mirrors
        // MessageDetailView.usesRichHTMLBodyRenderer so the thread card cannot
        // drift back onto the attributed-import path.
        useRichRenderer
    }

    private var htmlRenderingMode: HTMLBodyRenderingMode {
        if htmlRenderingModeOverrideMessageID == header.id,
           let htmlRenderingModeOverride {
            return htmlRenderingModeOverride
        }
        return HTMLBodyRenderingMode.default(for: theme)
    }

    private func toggleHTMLRenderingMode() {
        htmlRenderingModeOverrideMessageID = header.id
        htmlRenderingModeOverride = htmlRenderingMode.toggled
    }

    // MARK: - Body loading

    private func loadBody() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let raw = try await bodyWithReaderTimeout(for: header.id)
            let rendered = await bodyRenderer.render(raw)
            renderedBody = await resolvingInlineCIDImages(in: rendered)
            inlineCIDResolvedMessageID = header.id
            await updateDerivedBodyState()
        } catch is CancellationError {
            // Task cancelled — normal during scroll off-screen.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func bodyWithReaderTimeout(for messageID: String) async throws -> MessageBody {
        try await MessageBodyLoadTimeoutRace.load(
            messageID: messageID,
            sourceID: sourceID,
            backend: backend,
            timeoutNanoseconds: Self.bodyLoadTimeoutNanoseconds,
            timeoutError: { ThreadMessageBodyLoadTimeoutError() }
        )
    }

    private func updateDerivedBodyState() async {
        if inlineCIDResolvedMessageID != header.id,
           let currentBody = renderedBody {
            renderedBody = await resolvingInlineCIDImages(in: currentBody)
            inlineCIDResolvedMessageID = header.id
        }
        switch ThreadMessageBodyPresentation.resolve(
            bodyPresentationContext
        ) {
        case .attributedHTML(let html):
            renderedHTML = await MessageHTMLImporter.importAttributedHTML(html)
        default:
            renderedHTML = nil
        }
        await loadInviteIfNeeded()
    }

    private func resolvingInlineCIDImages(in rendered: RenderedBody) async -> RenderedBody {
        let resolvedHTML = await MessageInlineCIDRenderPolicy.rewriteCIDImageSources(
            in: rendered.html,
            attachments: rendered.attachments,
            download: { attachment in
                try await downloadAttachment(attachment)
            }
        )
        guard resolvedHTML != rendered.html else { return rendered }
        return RenderedBody(
            html: resolvedHTML,
            plainText: rendered.plainText,
            attachments: rendered.attachments,
            securityState: rendered.securityState
        )
    }

    private var bodyPresentationContext: ThreadMessageBodyPresentation.Context {
        ThreadMessageBodyPresentation.Context(
            isLoading: isLoading,
            errorMessage: errorMessage,
            renderedBody: renderedBody,
            useRichRenderer: usesRichHTMLBodyRenderer,
            allowRemoteContent: allowRemoteContentDefault,
            showRemoteContent: showRemoteContent
        )
    }

    private func loadInviteIfNeeded() async {
        guard loadedInviteMessageID != header.id else { return }
        loadedInviteMessageID = header.id
        guard let attachment = renderedBody?.attachments.first(where: {
            ThreadCalendarInvitePresentation.isCalendarInviteAttachment($0)
        }) else { return }

        do {
            let data = try await downloadAttachment(attachment)
            guard let raw = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1),
                let parsed = ICSParser.parseFirstEvent(from: raw)
            else {
                inviteLoadErrorMessage = "Brev couldn't parse this calendar invite."
                parsedInvite = nil
                calendarInviteEvent = nil
                return
            }
            guard let displayEvent = CalendarInviteDisplayEvent.makeCalendarEvent(from: parsed) else {
                inviteLoadErrorMessage = "Brev couldn't parse this calendar invite."
                parsedInvite = nil
                calendarInviteEvent = nil
                return
            }
            parsedInvite = parsed
            calendarInviteEvent = displayEvent
            inviteLoadErrorMessage = nil
        } catch is CancellationError {
            // Task cancelled — normal during scroll off-screen.
        } catch {
            inviteLoadErrorMessage = "Couldn't load calendar invite."
            parsedInvite = nil
            calendarInviteEvent = nil
        }
    }

    private func respondToInvite(_ response: AttendeeState) async {
        guard CalendarInviteResponseStartPolicy.canStartResponse(
            activeRequest: activeInviteResponseRequest,
            isBlocked: isWorkBlocked
        ) else { return }
        guard CalendarInviteReplyRouting.supportsActions(capabilities: backend.capabilities) else { return }

        let request = CalendarInviteResponseRequest(
            messageID: header.id,
            sourceID: sourceID,
            response: response
        )
        activeInviteResponseRequest = request
        isRespondingToInvite = true
        inviteResponseConfirmation = nil
        inviteResponseErrorMessage = nil
        failedInviteResponse = nil
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
            inviteResponseErrorMessage = MessageDetailPresentation
                .inviteResponseErrorStatus(for: error)
                .subtitle
            finishInviteResponse(request)
        }
    }

    private func canApplyInviteResponse(_ request: CalendarInviteResponseRequest) -> Bool {
        CalendarInviteResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: activeInviteResponseRequest,
            currentSourceID: sourceID,
            currentMessageID: header.id
        )
    }

    private func finishInviteResponse(_ request: CalendarInviteResponseRequest) {
        guard activeInviteResponseRequest == request else { return }
        activeInviteResponseRequest = nil
        isRespondingToInvite = false
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
}

private struct ThreadMessageBodyLoadTimeoutError: LocalizedError {
    var errorDescription: String? {
        String(localized: "Message content is taking too long to load. Check the connection and try again.", bundle: .module)
    }
}

private struct ThreadCalendarInviteCard: View {
    @Environment(\.brevTheme) private var theme

    let event: CalendarEvent
    let presentation: ThreadCalendarInvitePresentation
    let confirmation: MailRootStatus?
    let errorMessage: String?
    let failedResponse: AttendeeState?
    let isResponding: Bool
    let isBlocked: Bool
    let onRespond: (AttendeeState) -> Void
    let onRetry: (AttendeeState) -> Void
    let onDismissConfirmation: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            HStack(spacing: BrevSpacing.xs) {
                Image(systemName: "calendar")
                    .foregroundStyle(theme.accent.color)
                Text("Calendar invite", bundle: .module)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textTertiary.color)
                    .textCase(.uppercase)
                Spacer()
                if let responseLabel = presentation.responseLabel {
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

            inviteDetailRow(
                symbolName: "clock",
                text: Self.formatEventRange(
                    start: event.start,
                    end: event.end,
                    isAllDay: event.isAllDay
                )
            )

            if let location = event.location, !location.isEmpty {
                inviteDetailRow(symbolName: "mappin.and.ellipse", text: location)
            }

            if let organizer = event.organizer {
                inviteDetailRow(
                    symbolName: "person",
                    text: "Organizer: \(organizer.name ?? organizer.email)"
                )
            }

            if let unsupportedMessage = presentation.unsupportedMessage {
                BrevInlineStatus(message: unsupportedMessage, tone: .info)
            }

            if let confirmation {
                BrevInlineStatus(
                    message: confirmation.message,
                    tone: Self.inlineStatusTone(for: confirmation.tone),
                    onDismiss: onDismissConfirmation
                )
            }

            if let errorMessage {
                BrevInlineStatus(
                    message: errorMessage,
                    tone: .danger
                )
            }

            if presentation.showsActions {
                HStack(spacing: BrevSpacing.sm) {
                    BrevButton("Accept", style: .primary) {
                        onRespond(.accepted)
                    }
                    .disabled(isResponding || isBlocked)
                    BrevButton("Maybe", style: .secondary) {
                        onRespond(.tentative)
                    }
                    .disabled(isResponding || isBlocked)
                    BrevButton("Decline", style: .tertiary) {
                        onRespond(.declined)
                    }
                    .disabled(isResponding || isBlocked)
                    if isResponding {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            } else if let failedResponse {
                BrevButton("Retry", style: .secondary) {
                    onRetry(failedResponse)
                }
                .disabled(isResponding || isBlocked)
            }
        }
        .padding(BrevSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.bgSecondary.color)
        )
    }

    private func inviteDetailRow(symbolName: String, text: String) -> some View {
        HStack(spacing: BrevSpacing.xxs) {
            Image(systemName: symbolName)
                .foregroundStyle(theme.textTertiary.color)
            Text(text)
                .brevFont(.footnote)
                .foregroundStyle(theme.textSecondary.color)
        }
    }

    private static func formatEventRange(start: Date, end: Date?, isAllDay: Bool) -> String {
        CalendarEventRangeFormatter.string(start: start, end: end, isAllDay: isAllDay, separator: "-")
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
}
