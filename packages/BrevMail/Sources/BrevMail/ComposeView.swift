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
import BrevBackend
import BrevDesign
import BrevPlugins
import BrevSettings
import BrevThemes
import Foundation
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#elseif os(iOS)
import PhotosUI
import UIKit
#endif

private struct ComposeAutoSaveFingerprint: Equatable {
    let senderID: String
    let identityID: String?
    let to: [String]
    let cc: [String]
    let bcc: [String]
    let subject: String
    let bodyText: String
    let bodyHTML: String?
    let attachmentIDs: [UUID]
    let requestReadReceipt: Bool
}

private struct ComposeAttachmentRetryRequiredError: LocalizedError {
    var errorDescription: String? {
        String(localized: "Retry or remove failed attachments before saving or sending.", bundle: .module)
    }
}

#if os(macOS)
/// Stub NSObject that provides the standard bold/italic/underline selector names
/// for `NSApp.sendAction`. These are handled by NSTextView's built-in responder.
private final class ComposeRichTextCommandSelectors: NSObject {
    @objc func toggleBoldface(_: Any?) {}
    @objc func toggleItalics(_: Any?) {}
    @objc func underline(_: Any?) {}
}
#endif

private enum ComposeRichTextCommand: CaseIterable {
    case bold
    case italic
    case underline
    case insertLink
    case bulletedList
    case numberedList
    case insertImage
    case clearFormatting
    case undo
    case redo

    /// The iOS format bar: every text-level command the UIKit editor supports,
    /// plus inline image insertion via the Photos picker (handled outside this
    /// target — see `insertSelectedInlineImage`). Undo/redo come from the text
    /// view's own affordances.
    static var iosEssentials: [ComposeRichTextCommand] {
        [.bold, .italic, .underline, .bulletedList, .numberedList, .insertLink, .clearFormatting, .insertImage]
    }

    var label: String {
        switch self {
        case .bold: return String(localized: "Bold", bundle: .module)
        case .italic: return String(localized: "Italic", bundle: .module)
        case .underline: return String(localized: "Underline", bundle: .module)
        case .insertLink: return String(localized: "Insert Link", bundle: .module)
        case .bulletedList: return String(localized: "Bulleted List", bundle: .module)
        case .numberedList: return String(localized: "Numbered List", bundle: .module)
        case .insertImage: return String(localized: "Insert Image", bundle: .module)
        case .clearFormatting: return String(localized: "Clear Formatting", bundle: .module)
        case .undo: return String(localized: "Undo", bundle: .module)
        case .redo: return String(localized: "Redo", bundle: .module)
        }
    }

    var systemImage: String {
        switch self {
        case .bold: return "bold"
        case .italic: return "italic"
        case .underline: return "underline"
        case .insertLink: return "link"
        case .bulletedList: return "list.bullet"
        case .numberedList: return "list.number"
        case .insertImage: return "photo"
        case .clearFormatting: return "eraser"
        case .undo: return "arrow.uturn.backward"
        case .redo: return "arrow.uturn.forward"
        }
    }

    @MainActor
    func perform(iosTarget: ComposeIOSRichTextTarget? = nil) {
        #if os(macOS)
        switch self {
        case .bold:
            NSApp.sendAction(#selector(ComposeRichTextCommandSelectors.toggleBoldface(_:)), to: nil, from: nil)
        case .italic:
            NSApp.sendAction(#selector(ComposeRichTextCommandSelectors.toggleItalics(_:)), to: nil, from: nil)
        case .underline:
            NSApp.sendAction(#selector(ComposeRichTextCommandSelectors.underline(_:)), to: nil, from: nil)
        case .insertLink:
            // Handled by the Coordinator in ComposeBodyEditor via ComposeBodyEditorRichActions.
            NSApp.sendAction(#selector(ComposeBodyEditorRichActions.brevInsertLink(_:)), to: nil, from: nil)
        case .bulletedList:
            NSApp.sendAction(#selector(ComposeBodyEditorRichActions.brevToggleBulletedList(_:)), to: nil, from: nil)
        case .numberedList:
            NSApp.sendAction(#selector(ComposeBodyEditorRichActions.brevToggleNumberedList(_:)), to: nil, from: nil)
        case .insertImage:
            NSApp.sendAction(#selector(ComposeBodyEditorRichActions.brevInsertImage(_:)), to: nil, from: nil)
        case .clearFormatting:
            NSApp.sendAction(Selector(("removeFormat:")), to: nil, from: nil)
        case .undo:
            NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
        case .redo:
            NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
        }
        #else
        switch self {
        case .bold:
            iosTarget?.toggleBold()
        case .italic:
            iosTarget?.toggleItalic()
        case .underline:
            iosTarget?.toggleUnderline()
        case .bulletedList:
            iosTarget?.toggleBulletedList()
        case .numberedList:
            iosTarget?.toggleNumberedList()
        case .clearFormatting:
            iosTarget?.clearFormatting()
        case .insertLink:
            iosTarget?.requestLinkSheet()
        // Unreachable: image insertion is intercepted by ComposeView's format
        // menu before it reaches this target and presents the Photos picker
        // instead (see `insertSelectedInlineImage`). Undo and redo use the
        // text view's own shake/keyboard affordances rather than the format bar.
        case .insertImage, .undo, .redo:
            break
        }
        #endif
    }
}

/// Compose sheet: To / Cc / Bcc / subject / body, send via the active
/// `MailBackend`. Recipients use chip fields with autocomplete; Cc/Bcc
/// stay progressive-disclosed until revealed or populated.
public struct ComposeView: View {
    @StateObject private var htmlPreviewWebViewStore = HTMLBodyWebViewStore()
    @Environment(\.brevTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #endif

    private let sourceID: MailSourceID?
    private let senderOptions: [ComposeSenderOption]
    private let fallbackSenderOption: ComposeSenderOption
    private let backendForSenderSource: @MainActor (MailSourceID?) -> any MailBackend
    private let replyingTo: MessageHeader?
    private let replyMode: ComposeReplyMode
    private let forwardingFrom: MessageHeader?
    private let prefill: ComposePrefill?
    private let recoveredDraft: ComposeDraftRecoverySnapshot?
    private let aiBackend: (any AIBackend)?
    private let backendSupportsAIWriter: Bool
    private let signatureContext: ComposeSignatureContext?
    private let composeSecurityDefaults: ComposeSecurityDefaultState
    private let hasTrustedSigningIdentity: Bool
    private let hasTrustedEncryptionIdentity: Bool
    private let isWorkBlocked: Bool
    private let onClose: (() -> Void)?
    private let onCompletion: (ComposeCompletion) async -> Void

    @State private var to: [String] = []
    @State private var cc: [String] = []
    @State private var bcc: [String] = []
    @State private var toInputText = ""
    @State private var ccInputText = ""
    @State private var bccInputText = ""
    @State private var recipientSuggestions: [ComposeRecipientField: [RecipientAutocompleteSuggestion]] = [:]
    @State private var recipientLookupTask: Task<Void, Never>?
    @State private var showCc = false
    @State private var showBcc = false
    @State private var subject = ""
    @State private var bodyText = ""
    @State private var bodyHTML: String?
    @State private var bodySelection: ComposeBodyTextSelection?
    @State private var bodyInsertionPoint: ComposeBodyInsertionPoint?
    @State private var isSending = false
    @State private var isSavingDraft = false
    @State private var errorMessage: String?
    @State private var draftID = UUID().uuidString
    @State private var savedDraftRemoteID: String?
    @State private var hasCompletedExplicitOperation = false
    @State private var autoSaveDraftTask: Task<Void, Never>?
    @State private var nextComposeOperationRequestID = 0
    @State private var activeComposeOperationRequest: ComposeOperationRequest?
    @State private var pendingAttachments: [PendingAttachment] = []
    @State private var didImportPrefillAttachments = false
    @State private var isPickingFile = false
    /// True while a file drag hovers the compose window; drives the drop highlight.
    @State private var isDropTargeted = false
    @State private var isAIWorking = false
    @State private var activeAIShortcutRequest: ComposeAIShortcutRequest?
    @State private var nextAIPreviewID = 0
    @State private var aiPreview: ComposeAIPreviewState?
    @State private var showAIConsent = false
    @State private var showAIPromptDraft = false
    @State private var aiPromptDraftText = ""
    @State private var selectedSignatureID: String?
    @State private var insertedSignatureBody: String?
    /// Signed compose body seeded at open for reply/forward. Used to upgrade
    /// the quote from a decoded `MessageBody` without clobbering user edits.
    @State private var provisionalSignedBody: String?
    @State private var isQuotedBodyUpgradePending: Bool
    @State private var pendingSendGuardWarning: ComposeSendGuardWarning?
    @State private var signMessage: Bool
    @State private var encryptMessage: Bool
    @State private var requestReadReceipt = false
    @State private var aliases: [ServerAlias] = []
    @State private var selectedAliasID: String?
    @State private var currentSignatureContext: ComposeSignatureContext?
    @State private var scheduledSendDate: Date?
    @State private var isScheduleSheetPresented = false
    @State private var selectedSenderID: String

    // Draft autosave is driven by the inactivity task below. Keeping one
    // driver avoids a second 30-second timer racing the same save path.
    @State private var showDraftRecoveryBanner: Bool

    // #150 Compose templates
    @State private var showTemplatePicker = false
    @State private var templateSettings = MessageTemplateSettings.load()

    // #155 Undo-send
    @State private var pendingUndoSendTask: Task<Void, Never>?
    @State private var pendingUndoSendCountdown = 0

    // #251 Rich-compose: inline images + link sheet
    /// Owned here so the same registry lives for the whole compose session.
    /// Passed down into `ComposeBodyEditor` so the Coordinator can stage images.
    @State private var inlineImageRegistry = ComposeInlineImageRegistry()
    /// Bridges the mounted platform editor so save/send can publish the latest
    /// coalesced HTML snapshot before building a draft.
    @State private var htmlPublicationFlushBox = ComposeHTMLPublicationFlushBox()
    @State private var linkSheetInput: ComposeLinkSheetInput?
    /// Bridges the iOS formatting toolbar to the active UITextView coordinator.
    @State private var iosRichTextTargetBox = ComposeIOSRichTextTargetBox()
    #if os(iOS)
    @State private var isInlineImagePickerPresented = false
    @State private var selectedInlineImageItem: PhotosPickerItem?
    #endif
    #if os(macOS)
    @State private var showsHTMLPreview = false
    #endif
    /// Maps each staged inline-image Content-ID to its source-scoped backend attachment.
    /// Populated lazily in `draftForSend` so we don't touch the backend on
    /// every autosave. Re-used across retry attempts so staging is idempotent.
    @State private var stagedInlineAttachments: [String: ComposeStagedInlineAttachment] = [:]

    @AppStorage(ComposeBodyAppearance.storageKey) private var bodyAppearanceRaw = ComposeBodyAppearance.system.rawValue
    @AppStorage("compose.messageFormat") private var composeMessageFormatRaw = "automatic"
    @AppStorage(ComposeTextCheckingPolicy.storageKey) private var textCheckingEnabled = ComposeTextCheckingPolicy.defaultIsEnabled
    @AppStorage(MailboxViewPreferenceKey.fontFamily) private var mailboxFontFamilyRaw = MailboxFontFamily.system.rawValue
    @AppStorage(MailboxViewPreferenceKey.textSize) private var mailboxTextSizeRaw = MailboxTextSize.medium.rawValue
    @AppStorage(AIWriterSettings.Key.isEnabled) private var aiEnabled = false
    @AppStorage(AIWriterSettings.Key.consentGiven) private var aiConsentGiven = false

    public init(
        backend: any MailBackend,
        sourceID: MailSourceID? = nil,
        from: BrevAccount,
        replyingTo: MessageHeader? = nil,
        replyMode: ComposeReplyMode = .sender,
        forwardingFrom: MessageHeader? = nil,
        prefill: ComposePrefill? = nil,
        recoveredDraft: ComposeDraftRecoverySnapshot? = nil,
        aiBackend: (any AIBackend)? = nil,
        backendSupportsAIWriter: Bool? = nil,
        signatureContext: ComposeSignatureContext? = nil,
        composeSecurityDefaults: ComposeSecurityDefaultState = .disabled,
        hasTrustedSigningIdentity: Bool = false,
        hasTrustedEncryptionIdentity: Bool = false,
        isWorkBlocked: Bool = false,
        onClose: (() -> Void)? = nil,
        onCompletion: @escaping (ComposeCompletion) async -> Void = { _ in }
    ) {
        self.init(
            backend: backend,
            sourceID: sourceID,
            from: Correspondent(name: from.displayName, email: from.emailAddress),
            replyingTo: replyingTo,
            replyMode: replyMode,
            forwardingFrom: forwardingFrom,
            prefill: prefill,
            recoveredDraft: recoveredDraft,
            aiBackend: aiBackend,
            backendSupportsAIWriter: backendSupportsAIWriter,
            signatureContext: signatureContext,
            composeSecurityDefaults: composeSecurityDefaults,
            hasTrustedSigningIdentity: hasTrustedSigningIdentity,
            hasTrustedEncryptionIdentity: hasTrustedEncryptionIdentity,
            isWorkBlocked: isWorkBlocked,
            onClose: onClose,
            onCompletion: onCompletion
        )
    }

    public init(
        backend: any MailBackend,
        sourceID: MailSourceID? = nil,
        from: Correspondent,
        replyingTo: MessageHeader? = nil,
        replyMode: ComposeReplyMode = .sender,
        forwardingFrom: MessageHeader? = nil,
        prefill: ComposePrefill? = nil,
        recoveredDraft: ComposeDraftRecoverySnapshot? = nil,
        aiBackend: (any AIBackend)? = nil,
        backendSupportsAIWriter: Bool? = nil,
        signatureContext: ComposeSignatureContext? = nil,
        composeSecurityDefaults: ComposeSecurityDefaultState = .disabled,
        hasTrustedSigningIdentity: Bool = false,
        hasTrustedEncryptionIdentity: Bool = false,
        isWorkBlocked: Bool = false,
        onClose: (() -> Void)? = nil,
        onCompletion: @escaping (ComposeCompletion) async -> Void = { _ in }
    ) {
        self.init(
            backend: backend,
            sourceID: sourceID,
            from: from,
            senderOptions: [],
            initialSenderOption: nil,
            backendForSenderSource: nil,
            replyingTo: replyingTo,
            replyMode: replyMode,
            forwardingFrom: forwardingFrom,
            prefill: prefill,
            recoveredDraft: recoveredDraft,
            aiBackend: aiBackend,
            backendSupportsAIWriter: backendSupportsAIWriter,
            signatureContext: signatureContext,
            composeSecurityDefaults: composeSecurityDefaults,
            hasTrustedSigningIdentity: hasTrustedSigningIdentity,
            hasTrustedEncryptionIdentity: hasTrustedEncryptionIdentity,
            isWorkBlocked: isWorkBlocked,
            onClose: onClose,
            onCompletion: onCompletion
        )
    }

    init(
        backend: any MailBackend,
        sourceID: MailSourceID? = nil,
        from: Correspondent,
        senderOptions: [ComposeSenderOption],
        initialSenderOption: ComposeSenderOption? = nil,
        backendForSenderSource: (@MainActor (MailSourceID?) -> any MailBackend)? = nil,
        replyingTo: MessageHeader? = nil,
        replyMode: ComposeReplyMode = .sender,
        forwardingFrom: MessageHeader? = nil,
        prefill: ComposePrefill? = nil,
        recoveredDraft: ComposeDraftRecoverySnapshot? = nil,
        aiBackend: (any AIBackend)? = nil,
        backendSupportsAIWriter: Bool? = nil,
        signatureContext: ComposeSignatureContext? = nil,
        composeSecurityDefaults: ComposeSecurityDefaultState = .disabled,
        hasTrustedSigningIdentity: Bool = false,
        hasTrustedEncryptionIdentity: Bool = false,
        isWorkBlocked: Bool = false,
        onClose: (() -> Void)? = nil,
        onCompletion: @escaping (ComposeCompletion) async -> Void = { _ in }
    ) {
        let fallbackSenderOption = Self.fallbackSenderOption(
            backend: backend,
            sourceID: sourceID,
            from: from
        )
        let resolvedSenderOptions = senderOptions.isEmpty ? [fallbackSenderOption] : senderOptions
        let selectedSenderOption = initialSenderOption.flatMap { initial in
            resolvedSenderOptions.first { $0.id == initial.id }
        } ?? resolvedSenderOptions.first(where: { $0.sourceID == sourceID }) ?? resolvedSenderOptions.first
            ?? fallbackSenderOption

        self.sourceID = sourceID
        self.senderOptions = resolvedSenderOptions
        self.fallbackSenderOption = fallbackSenderOption
        self.backendForSenderSource = backendForSenderSource ?? { _ in backend }
        self.replyingTo = replyingTo
        self.replyMode = replyMode
        self.forwardingFrom = forwardingFrom
        self.prefill = prefill
        self.recoveredDraft = recoveredDraft
        self.aiBackend = aiBackend
        self.backendSupportsAIWriter = backendSupportsAIWriter ?? backend.capabilities.contains(.aiWriter)
        self.signatureContext = signatureContext
        self.composeSecurityDefaults = composeSecurityDefaults
        self.hasTrustedSigningIdentity = hasTrustedSigningIdentity
        self.hasTrustedEncryptionIdentity = hasTrustedEncryptionIdentity
        self.isWorkBlocked = isWorkBlocked
        self.onClose = onClose
        self.onCompletion = onCompletion
        let initialBodyText: String
        if let replyingTo {
            _to = State(initialValue: ComposeReplyResolver.recipients(
                for: replyingTo,
                mode: replyMode,
                accountEmail: from.email
            ))
            _subject = State(initialValue: ComposeReplyFormatter.subject(for: replyingTo.subject))
            initialBodyText = ComposeReplyFormatter.body(
                for: replyingTo,
                placement: ComposeReplyQuotePlacement.load()
            )
        } else if let forwardingFrom {
            _subject = State(initialValue: ComposeForwardFormatter.subject(for: forwardingFrom.subject))
            initialBodyText = ComposeForwardFormatter.body(for: forwardingFrom)
        } else if let recoveredDraft {
            _to = State(initialValue: recoveredDraft.to)
            _cc = State(initialValue: recoveredDraft.cc)
            _bcc = State(initialValue: recoveredDraft.bcc)
            _subject = State(initialValue: recoveredDraft.subject)
            _draftID = State(initialValue: recoveredDraft.draftID)
            _savedDraftRemoteID = State(initialValue: recoveredDraft.remoteID)
            initialBodyText = recoveredDraft.bodyText
        } else if let prefill {
            _to = State(initialValue: prefill.to)
            _cc = State(initialValue: prefill.cc)
            _bcc = State(initialValue: prefill.bcc)
            _subject = State(initialValue: prefill.subject)
            initialBodyText = prefill.bodyText
        } else {
            initialBodyText = ""
        }
        let initialSignature = recoveredDraft == nil ? signatureContext?.selectedSignature : nil
        let signedInitialBody = ComposeSignatureBodyPolicy.body(
            afterSelecting: initialSignature?.body,
            in: initialBodyText,
            replacing: nil
        )
        _bodyText = State(initialValue: signedInitialBody)
        _selectedSignatureID = State(initialValue: initialSignature?.id)
        _insertedSignatureBody = State(initialValue: ComposeSignatureBodyPolicy.managedSignatureBody(
            from: initialSignature?.body
        ))
        // Only reply/forward start with a provisional snippet-backed quote that
        // may later be replaced by a CTE-decoded MessageBody.
        if recoveredDraft == nil, replyingTo != nil || forwardingFrom != nil {
            _provisionalSignedBody = State(initialValue: signedInitialBody)
        } else {
            _provisionalSignedBody = State(initialValue: nil)
        }
        _isQuotedBodyUpgradePending = State(
            initialValue: ComposeQuotedBodyUpgradePolicy.initiallyPending(
                hasRecoveredDraft: recoveredDraft != nil,
                isReplyOrForward: replyingTo != nil || forwardingFrom != nil
            )
        )
        _signMessage = State(initialValue: composeSecurityDefaults.shouldSignByDefault)
        _encryptMessage = State(initialValue: composeSecurityDefaults.shouldEncryptByDefault)
        _showDraftRecoveryBanner = State(initialValue: recoveredDraft != nil)
        _currentSignatureContext = State(initialValue: signatureContext)
        _selectedSenderID = State(initialValue: selectedSenderOption.id)
    }

    private static func fallbackSenderOption(
        backend: any MailBackend,
        sourceID: MailSourceID?,
        from: Correspondent
    ) -> ComposeSenderOption {
        ComposeSenderOption(
            sourceID: sourceID,
            accountID: backend.account.id,
            displayName: from.name,
            email: from.email,
            subtitle: backend.account.backendDisplayName
        )
    }

    public var body: some View {
        let content = composeContent
            .overlay { dropHighlight }
            .onDrop(of: ComposeAttachmentDrop.acceptedContentTypes, isTargeted: $isDropTargeted) { providers in
                handleDrop(providers)
            }
            .background(BrevWindowSurfaceBackground(role: .utility).ignoresSafeArea())
            .frame(minWidth: frameMetrics.minWidth, minHeight: frameMetrics.minHeight)
            .accessibilityAddTraits(.isModal)
            .brevWindowTranslucency(windowRole: .utility)
            .task {
                await loadAliases()
                await reloadServerSignaturesIfPossible()
                defer { isQuotedBodyUpgradePending = false }
                await upgradeQuotedOriginalBodyIfNeeded()
            }
            .task {
                await importPrefillAttachmentsIfNeeded()
            }
            .sheet(isPresented: $isScheduleSheetPresented) {
                ScheduleSendSheet(
                    initiallyScheduledDate: scheduledSendDate,
                    onConfirm: { chosenDate in
                        scheduledSendDate = chosenDate
                    }
                )
                .brevTheme(theme)
            }
            .sheet(item: $linkSheetInput) { input in
                ComposeLinkSheet(
                    input: input,
                    onConfirm: { url, displayText in
                        applyLink(url: url, displayText: displayText)
                    },
                    onRemove: {
                        removeLink()
                    }
                )
                .brevTheme(theme)
            }
            .onDisappear {
                cancelAutoSaveDraftTask()
                invalidateComposeOperation()
                pendingUndoSendTask?.cancel()
                recipientLookupTask?.cancel()
            }
            .onChange(of: autoSaveFingerprint) {
                scheduleAutoSaveAfterInactivity()
            }
            .modifier(ComposeFileImporter(
                isPickingFile: $isPickingFile,
                handleFilePick: handleFilePick
            ))
            .modifier(ComposeAIConsentAlert(
                showAIConsent: $showAIConsent,
                aiEnabled: $aiEnabled,
                aiConsentGiven: $aiConsentGiven
            ))
            .modifier(ComposeAIPromptDraftAlert(
                isPresented: $showAIPromptDraft,
                prompt: $aiPromptDraftText,
                providerLabel: aiBackend?.transparencyLabel ?? ""
            ) { prompt in
                guard let aiBackend else { return }
                Task { await runAIPromptDraft(prompt, backend: aiBackend) }
            })
            .alert(item: $pendingSendGuardWarning) { warning in
                Alert(
                    title: Text(warning.title),
                    message: Text(warning.message),
                    primaryButton: .default(Text("Send Anyway", bundle: .module)) {
                        Task { await send(bypassingSendGuard: true) }
                    },
                    secondaryButton: .cancel()
                )
            }
        #if os(iOS)
        return content
            .photosPicker(
                isPresented: $isInlineImagePickerPresented,
                selection: $selectedInlineImageItem,
                matching: .images,
                preferredItemEncoding: .compatible
            )
            .onChange(of: selectedInlineImageItem) {
                handleSelectedInlineImage()
            }
        #else
        return content
        #endif
    }

    private var frameMetrics: ComposeFrameMetrics {
        ComposeLayoutPolicy.frameMetrics(for: composeLayoutPlatform)
    }

    private var toolbarMetrics: ComposeToolbarMetrics {
        ComposeLayoutPolicy.toolbarMetrics(for: composeLayoutPlatform)
    }

    private var composeLayoutPlatform: ComposeLayoutPlatform {
        #if os(iOS)
        ComposeLayoutPolicy.platform(
            horizontalSizeClassIsCompact: horizontalSizeClass == .compact,
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize,
            deviceClass: UIDevice.current.userInterfaceIdiom == .phone ? .phone : .pad
        )
        #else
        ComposeLayoutPolicy.platform(
            horizontalSizeClassIsCompact: false,
            isAccessibilitySize: false,
            deviceClass: .mac
        )
        #endif
    }

    private var denseChromeDynamicTypeRange: PartialRangeThrough<DynamicTypeSize> {
        ...DynamicTypeSize.xxxLarge
    }

    private var toolbarActionLayout: ComposeToolbarActionLayout {
        ComposePresentation.toolbarActionLayout(for: composeLayoutPlatform)
    }

    // MARK: - Sections

    @ViewBuilder
    private var composeContent: some View {
        VStack(spacing: 0) {
            header
            draftRecoveryBanner
            undoSendBanner
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    attachmentsList
                    bodyField
                }
                .disabled(isBusy)
                aiPreviewPanel
            }
            scheduledSendBanner
            errorBanner
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Subtle accent outline shown while files are dragged over the window.
    @ViewBuilder
    private var dropHighlight: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: BrevRadius.lg, style: .continuous)
                .fill(theme.accent.color.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: BrevRadius.lg, style: .continuous)
                        .strokeBorder(theme.accent.color, lineWidth: 2)
                )
                .padding(BrevSpacing.sm)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var scheduledSendBanner: some View {
        if let scheduledSendDate {
            BrevDivider()
            BrevInlineStatus(
                message: String(
                    localized: "Scheduled to send at \(ScheduleSendDateResolver.formattedScheduleDate(scheduledSendDate)).",
                    bundle: .module
                ),
                tone: .info,
                actionTitle: String(localized: "Clear", bundle: .module),
                onAction: clearScheduledSendDate,
                lineLimit: 2
            )
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let errorMessage {
            let status = ComposePresentation.errorStatus(errorMessage)
            BrevDivider()
            BrevInlineStatus(
                message: status.message,
                tone: status.tone.inlineStatusTone,
                onDismiss: status.isDismissible ? { self.errorMessage = nil } : nil,
                lineLimit: status.lineLimit
            )
        }
    }

    @ViewBuilder
    private var draftRecoveryBanner: some View {
        if showDraftRecoveryBanner {
            BrevDivider()
            BrevInlineStatus(
                message: String(localized: "Draft recovered from a previous session.", bundle: .module),
                tone: .info,
                onDismiss: { showDraftRecoveryBanner = false }
            )
        }
    }

    @ViewBuilder
    private var undoSendBanner: some View {
        if pendingUndoSendTask != nil {
            BrevDivider()
            BrevInlineStatus(
                message: String(localized: "Sending in \(pendingUndoSendCountdown)s…", bundle: .module),
                tone: .warning,
                actionTitle: String(localized: "Undo", bundle: .module),
                onAction: { cancelUndoSend() }
            )
        }
    }

    @ViewBuilder
    private var header: some View {
        VStack(spacing: 0) {
            toolbar
            fieldPanel
        }
        .padding(.top, toolbarMetrics.topInset)
        // No opaque chrome background: the toolbar and fields sit directly on the
        // window's shared (opacity-aware) surface, so the whole compose window is
        // one continuous colour rather than a header band split off from the body.
        .disabled(isBusy)
    }

    @ViewBuilder
    private var toolbar: some View {
        if composeLayoutPlatform == .compactIOS || composeLayoutPlatform == .compactIOSAccessibility {
            compactAccessibilityToolbar
        } else {
            defaultToolbar
        }
    }

    private var defaultToolbar: some View {
        HStack(spacing: BrevSpacing.xs) {
            #if os(iOS)
            toolbarButton(
                label: ComposeToolbarAction.close.accessibilityLabel,
                systemImage: "xmark",
                isDisabled: isBusy,
                action: close
            )
            #endif

            if toolbarMetrics.leadingInset > 0 {
                Color.clear
                    .frame(width: toolbarMetrics.leadingInset, height: 1)
                    .accessibilityHidden(true)
            }

            // No title text — the toolbar floats like Apple Mail's compose
            // toolbar. Controls sit borderless on the shared surface; Send is
            // isolated at the trailing edge.
            Spacer(minLength: BrevSpacing.sm)

            toolbarCluster {
                toolbarButton(
                    label: ComposeToolbarAction.attach.accessibilityLabel,
                    systemImage: "paperclip",
                    isDisabled: isBusy
                ) {
                    isPickingFile = true
                }
                formatMenu
                signatureMenu
                receiptOptionsMenu
                toolbarButton(
                    label: ComposeToolbarAction.templates.accessibilityLabel,
                    systemImage: "doc.on.doc",
                    isDisabled: isBusy
                ) {
                    showTemplatePicker = true
                }
                .sheet(isPresented: $showTemplatePicker) {
                    templatePickerSheet
                }
                securityMenu
                aiWriterMenu
                pluginToolbarButtons
            }

            toolbarCluster {
                toolbarButton(
                    label: isSavingDraft
                        ? String(localized: "Saving Draft", bundle: .module)
                        : ComposeToolbarAction.saveDraft.accessibilityLabel,
                    systemImage: isSavingDraft ? "tray.and.arrow.down.fill" : "tray.and.arrow.down",
                    isDisabled: isInteractionBlocked || !canSave
                ) {
                    Task { await saveDraft() }
                }
                scheduleSendToolbarButton
            }

            editorAppearanceToggle
            #if os(macOS)
            htmlPreviewToggle
            #endif

            composeSecondaryActionsMenu
            sendButton
        }
        .padding(.leading, BrevSpacing.sm)
        .padding(.trailing, BrevSpacing.md)
        .frame(maxWidth: .infinity, minHeight: toolbarMetrics.height, maxHeight: toolbarMetrics.height)
    }

    /// Groups toolbar controls according to chrome cluster treatment.
    @ViewBuilder
    private func toolbarCluster<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        switch ComposePresentation.chrome.toolbarClusterTreatment {
        case .borderless:
            HStack(spacing: BrevSpacing.xxs) {
                content()
            }
        }
    }

    private var compactAccessibilityToolbar: some View {
        HStack(spacing: BrevSpacing.xs) {
            toolbarButton(
                label: ComposeToolbarAction.close.accessibilityLabel,
                systemImage: "xmark",
                isDisabled: isBusy,
                action: close
            )

            Spacer(minLength: BrevSpacing.sm)

            sendButton
            toolbarSeparator
            composeActionsMenu
        }
        .padding(.leading, BrevSpacing.sm)
        .padding(.trailing, BrevSpacing.md)
        .frame(maxWidth: .infinity, minHeight: toolbarMetrics.height, maxHeight: toolbarMetrics.height)
    }

    private var composeActionsMenu: some View {
        let layout = toolbarActionLayout
        let menu = Menu {
            compactComposeActionsMenuContent
        } label: {
            toolbarControlIcon("ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(layout.moreActionsAccessibilityLabel)
        .accessibilityValue(layout.moreActionsAccessibilityValue)
        .accessibilityHint(String(localized: "Contains secondary compose actions.", bundle: .module))
        .help(layout.moreActionsAccessibilityLabel)
        .dynamicTypeSize(denseChromeDynamicTypeRange)
        .sheet(isPresented: $showTemplatePicker) {
            templatePickerSheet
        }
        return menu
    }

    /// Overflow menu for secondary compose tools on the default toolbar
    /// (templates, security, AI, plugins, meeting suggestions). Primary
    /// attach / draft / schedule stay as icons.
    private var composeSecondaryActionsMenu: some View {
        let layout = toolbarActionLayout
        return Menu {
            Button {
                showTemplatePicker = true
            } label: {
                Label(ComposeToolbarAction.templates.accessibilityLabel, systemImage: "doc.on.doc")
            }
            .disabled(isBusy)

            if composeSecurityDefaults.isFeatureEnabled {
                Menu(ComposeToolbarAction.security.accessibilityLabel) {
                    securityMenuContent
                }
            }

            Menu(ComposeToolbarAction.aiWriter.accessibilityLabel) {
                aiWriterMenuContent
            }
            .disabled(aiWriterMenuDisabled)

        } label: {
            toolbarControlIcon("ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(layout.moreActionsAccessibilityLabel)
        .accessibilityValue(layout.moreActionsAccessibilityValue)
        .accessibilityHint(String(localized: "Contains secondary compose actions.", bundle: .module))
        .help(layout.moreActionsAccessibilityLabel)
        .dynamicTypeSize(denseChromeDynamicTypeRange)
        .sheet(isPresented: $showTemplatePicker) {
            templatePickerSheet
        }
    }

    @ViewBuilder
    private var compactComposeActionsMenuContent: some View {
        Group {
            Button {
                isPickingFile = true
            } label: {
                Label(ComposeToolbarAction.attach.accessibilityLabel, systemImage: "paperclip")
            }
            .disabled(isBusy)

            Button {
                showTemplatePicker = true
            } label: {
                Label(ComposeToolbarAction.templates.accessibilityLabel, systemImage: "doc.on.doc")
            }
            .disabled(isBusy)

            if let activeSignatureContext, !activeSignatureContext.options.isEmpty {
                Menu(ComposeToolbarAction.signature.accessibilityLabel) {
                    signatureMenuContent
                }
            }

            receiptOptionsMenuContent

            if composeBodyFormat == .richTextHTML {
                Divider()
                Menu(String(localized: "Format", bundle: .module)) {
                    #if os(iOS)
                    iosRichTextFormattingMenuContent
                    #else
                    richTextFormattingMenuContent
                    #endif
                }
            }

            if composeSecurityDefaults.isFeatureEnabled {
                Menu(ComposeToolbarAction.security.accessibilityLabel) {
                    securityMenuContent
                }
            }

            Menu(ComposeToolbarAction.aiWriter.accessibilityLabel) {
                aiWriterMenuContent
            }
            .disabled(aiWriterMenuDisabled)

            Divider()

            Button {
                Task { await saveDraft() }
            } label: {
                Label(
                    isSavingDraft
                        ? String(localized: "Saving Draft", bundle: .module)
                        : ComposeToolbarAction.saveDraft.accessibilityLabel,
                    systemImage: isSavingDraft ? "tray.and.arrow.down.fill" : "tray.and.arrow.down"
                )
            }
            .disabled(isInteractionBlocked || !canSave)

            Button {
                isScheduleSheetPresented = true
            } label: {
                Label(
                    scheduledSendDate == nil
                        ? ComposeToolbarAction.scheduleSend.accessibilityLabel
                        : String(localized: "Edit scheduled send", bundle: .module),
                    systemImage: "calendar.badge.clock"
                )
            }
            .disabled(isInteractionBlocked || selectedComposeBackend.extensionService(ScheduledSendManaging.self) == nil)
        }
        .dynamicTypeSize(MailDenseChromeDynamicType.compactRange)
    }

    private var toolbarSeparator: some View {
        Rectangle()
            .fill(BrevSeparator.color(for: theme))
            .frame(width: 1, height: 18)
            .padding(.horizontal, BrevSpacing.xxs)
            .accessibilityHidden(true)
    }

    private func toolbarButton(
        label: String,
        systemImage: String,
        isDisabled: Bool,
        isPrimary: Bool = false,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            toolbarControlIcon(
                systemImage,
                isPrimary: isPrimary && !isDisabled,
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .accessibilityLabel(label)
        .accessibilityRepresentation {
            Button(label, action: action)
        }
        .help(label)
    }

    private func toolbarControlIcon(
        _ systemImage: String,
        isPrimary: Bool = false,
        isSelected: Bool = false
    ) -> some View {
        toolbarIcon(
            systemImage,
            isPrimary: isPrimary,
            isSelected: isSelected
        )
        .frame(
            width: toolbarMetrics.hitTargetSize,
            height: toolbarMetrics.hitTargetSize
        )
        .contentShape(Rectangle())
    }

    private func toolbarIcon(
        _ systemImage: String,
        isPrimary: Bool = false,
        isSelected: Bool = false
    ) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isPrimary ? theme.accent.color : theme.textSecondary.color)
            .frame(
                width: toolbarMetrics.buttonSize,
                height: toolbarMetrics.buttonSize
            )
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? theme.selection.color : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// Compact light/dark switch for the body editor.
    private var editorAppearanceToggle: some View {
        HStack(spacing: 2) {
            ForEach(ComposeBodyAppearance.allCases, id: \.self) { appearance in
                Button {
                    bodyAppearanceRaw = appearance.rawValue
                } label: {
                    Image(systemName: appearance.symbolName)
                        .font(.system(size: 12, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(
                            bodyAppearanceSelection == appearance ? theme.accent.color : theme.textSecondary.color
                        )
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(bodyAppearanceSelection == appearance ? theme.selection.color.opacity(0.55) : Color.clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isInteractionBlocked)
                .accessibilityLabel(appearance.label)
                .help(appearance.label)
            }
        }
        .opacity(isInteractionBlocked ? 0.45 : 0.85)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Editor Appearance", bundle: .module))
    }

    private var sendButton: some View {
        let isDisabled = isInteractionBlocked || (!canSend && pendingUndoSendTask == nil)
        return Button {
            if pendingUndoSendTask != nil {
                cancelUndoSend()
            } else {
                beginUndoSend {
                    await send()
                }
            }
        } label: {
            ZStack {
                toolbarControlIcon(
                    pendingUndoSendTask != nil ? "xmark.circle" : sendButtonSystemImage,
                    isPrimary: pendingUndoSendTask == nil && (!isDisabled || isSending)
                )
                if isSending {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.55)
                        .tint(theme.accent.color)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled && !isSending ? 0.45 : 1)
        .accessibilityLabel(
            pendingUndoSendTask != nil
                ? String(localized: "Cancel Send", bundle: .module)
                : sendButtonLabel
        )
        .accessibilityRepresentation {
            Button(
                pendingUndoSendTask != nil
                    ? String(localized: "Cancel Send", bundle: .module)
                    : sendButtonLabel
            ) {
                if pendingUndoSendTask != nil {
                    cancelUndoSend()
                } else {
                    beginUndoSend {
                        await send()
                    }
                }
            }
        }
        .help(
            pendingUndoSendTask != nil
                ? String(localized: "Cancel Send", bundle: .module)
                : sendButtonLabel
        )
    }

    private var sendButtonLabel: String {
        if isSending { return String(localized: "Sending", bundle: .module) }
        if scheduledSendDate != nil { return String(localized: "Schedule send", bundle: .module) }
        return String(localized: "Send", bundle: .module)
    }

    private var sendButtonSystemImage: String {
        if isSending { return "paperplane.fill" }
        if scheduledSendDate != nil { return "paperplane.circle.fill" }
        return "paperplane"
    }

    private var scheduleSendToolbarButton: some View {
        let isScheduled = scheduledSendDate != nil
        return toolbarButton(
            label: isScheduled
                ? String(localized: "Edit scheduled send", bundle: .module)
                : ComposeToolbarAction.scheduleSend.accessibilityLabel,
            systemImage: isScheduled ? "calendar.badge.clock" : "calendar.badge.clock",
            isDisabled: isInteractionBlocked || selectedComposeBackend.extensionService(ScheduledSendManaging.self) == nil,
            isSelected: isScheduled
        ) {
            isScheduleSheetPresented = true
        }
    }

    // Header fields sit directly on the window surface — flat rows with
    // hairline dividers, matching the message list rather than floating in
    // a glass card inside an already-translucent window.
    private var fieldPanel: some View {
        switch ComposePresentation.chrome.fieldPanelTreatment {
        case .flatHairline:
            flatHairlineFieldPanel
        }
    }

    private var flatHairlineFieldPanel: some View {
        let rows = ComposePresentation.chrome.fieldRows
        let horizontalInset: CGFloat = isAccessibilityFieldLayout ? BrevSpacing.sm : BrevSpacing.lg
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element) { index, row in
                composeFieldRow(row)
                    .padding(.horizontal, horizontalInset)
                if index < rows.count - 1 {
                    BrevDivider()
                }
            }
            BrevDivider()
        }
        .padding(.top, BrevSpacing.xs)
    }

    private var isAccessibilityFieldLayout: Bool {
        composeLayoutPlatform == .compactIOSAccessibility
    }

    private var fieldVerticalPadding: CGFloat {
        #if os(macOS)
        // Generous row height for the header fields, closer to Apple Mail's
        // compose rhythm.
        return BrevSpacing.md
        #else
        return BrevSpacing.md
        #endif
    }

    @ViewBuilder
    private func composeFieldRow(_ row: ComposeFieldRow) -> some View {
        switch row {
        case .recipients:
            recipientFields
        case .subject:
            subjectField
        case .sender:
            fromField
        }
    }

    @ViewBuilder
    private var recipientFields: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            if isAccessibilityFieldLayout {
                RecipientChipField(
                    label: String(localized: "To", bundle: .module),
                    labelWidth: ComposeLayout.fieldLabelWidth,
                    recipients: $to,
                    inputText: $toInputText,
                    suggestions: suggestions(for: .to),
                    onInputTextChanged: { query in updateRecipientSuggestions(for: .to, query: query) },
                    onSuggestionSelected: { _ in clearRecipientSuggestions(for: .to) }
                )
                carbonCopyControls
            } else {
                HStack(alignment: .center, spacing: BrevSpacing.sm) {
                    RecipientChipField(
                        label: String(localized: "To", bundle: .module),
                        labelWidth: ComposeLayout.fieldLabelWidth,
                        recipients: $to,
                        inputText: $toInputText,
                        suggestions: suggestions(for: .to),
                        onInputTextChanged: { query in updateRecipientSuggestions(for: .to, query: query) },
                        onSuggestionSelected: { _ in clearRecipientSuggestions(for: .to) }
                    )
                    carbonCopyControls
                }
            }
            if isCcFieldVisible {
                RecipientChipField(
                    label: String(localized: "Cc", bundle: .module),
                    labelWidth: ComposeLayout.fieldLabelWidth,
                    recipients: $cc,
                    inputText: $ccInputText,
                    suggestions: suggestions(for: .cc),
                    onInputTextChanged: { query in updateRecipientSuggestions(for: .cc, query: query) },
                    onSuggestionSelected: { _ in clearRecipientSuggestions(for: .cc) }
                )
            }
            if isBccFieldVisible {
                RecipientChipField(
                    label: String(localized: "Bcc", bundle: .module),
                    labelWidth: ComposeLayout.fieldLabelWidth,
                    recipients: $bcc,
                    inputText: $bccInputText,
                    suggestions: suggestions(for: .bcc),
                    onInputTextChanged: { query in updateRecipientSuggestions(for: .bcc, query: query) },
                    onSuggestionSelected: { _ in clearRecipientSuggestions(for: .bcc) }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, fieldVerticalPadding)
    }

    @ViewBuilder
    private var carbonCopyControls: some View {
        let fields = ComposePresentation.hiddenCarbonCopyFields(
            isCcVisible: isCcFieldVisible,
            isBccVisible: isBccFieldVisible
        )
        if !fields.isEmpty {
            HStack(spacing: 4) {
                ForEach(fields) { field in
                    Button {
                        revealCarbonCopyField(field)
                    } label: {
                        Text(field.label)
                            .brevFont(.subheadline)
                            .foregroundStyle(theme.accent.color)
                            .frame(height: ComposeLayout.fieldAccessorySize)
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(field.accessibilityLabel)
                    .help(field.accessibilityLabel)
                }
            }
        }
    }

    private var isCcFieldVisible: Bool {
        showCc || !cc.isEmpty
    }

    private var isBccFieldVisible: Bool {
        showBcc || !bcc.isEmpty
    }

    private func revealCarbonCopyField(_ field: ComposeCarbonCopyField) {
        switch field {
        case .cc:
            showCc = true
        case .bcc:
            showBcc = true
        }
    }

    private func suggestions(for field: ComposeRecipientField) -> [RecipientAutocompleteSuggestion] {
        recipientSuggestions[field] ?? []
    }

    private func clearRecipientSuggestions(for field: ComposeRecipientField) {
        recipientSuggestions[field] = []
    }

    private func updateRecipientSuggestions(for field: ComposeRecipientField, query: String) {
        recipientLookupTask?.cancel()
        guard let lookupQuery = ComposeRecipientAutocomplete.query(
            text: query,
            sourceID: activeComposeSourceID
        ) else {
            clearRecipientSuggestions(for: field)
            return
        }
        let existingRecipients = recipients(for: field)
        let recentRecipientLookup = RecentRecipientLookup.shared
        let provider = selectedComposeBackend.extensionService(ContactLookupProviding.self)
        let usesAppleContacts = RecipientSuggestionSettings.load().useAppleContacts
        recipientLookupTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled else { return }

                let recentRecipients = await recentRecipientLookup.recipients(
                    matching: lookupQuery.text,
                    accountID: lookupQuery.sourceID.accountID
                )
                guard !Task.isCancelled else { return }

                var candidates: [RecipientAutocompleteCandidate] = []
                if usesAppleContacts {
                    let appleContacts = await SystemContactsRecipientLookup.shared.contacts(matching: lookupQuery)
                    guard !Task.isCancelled else { return }
                    candidates += appleContacts.map {
                        RecipientAutocompleteCandidate(result: $0, source: .appleContacts)
                    }
                }
                candidates += recentRecipients.map { recipient in
                    RecipientAutocompleteCandidate(
                        result: ContactLookupResult(
                            id: "recent-recipient-\(recipient.id)",
                            displayName: recipient.displayName,
                            email: recipient.email,
                            sourceID: lookupQuery.sourceID
                        ),
                        source: .recentRecipients
                    )
                }
                if let provider {
                    let providerCandidates = await ComposeRecipientAutocomplete.providerCandidates {
                        try await provider.contacts(matching: lookupQuery)
                    }
                    guard !Task.isCancelled else { return }
                    candidates += providerCandidates
                }
                guard !Task.isCancelled else { return }
                recipientSuggestions[field] = ComposeRecipientAutocomplete.suggestions(
                    from: candidates,
                    existingRecipients: existingRecipients
                )
            } catch {
                if !Task.isCancelled {
                    clearRecipientSuggestions(for: field)
                }
            }
        }
    }

    private func recipients(for field: ComposeRecipientField) -> [String] {
        switch field {
        case .to:
            return to
        case .cc:
            return cc
        case .bcc:
            return bcc
        }
    }

    private var activeComposeSourceID: MailSourceID {
        selectedComposeSourceID ?? MailSourceID(
            accountID: selectedComposeBackend.account.id,
            mailboxID: selectedComposeBackend.account.id
        )
    }

    private var selectedSenderOption: ComposeSenderOption {
        senderOptions.first { $0.id == selectedSenderID }
            ?? senderOptions.first { $0.sourceID == sourceID }
            ?? senderOptions.first
            ?? fallbackSenderOption
    }

    private var selectedComposeSourceID: MailSourceID? {
        selectedSenderOption.sourceID ?? sourceID
    }

    private var selectedComposeBackend: any MailBackend {
        backendForSenderSource(selectedComposeSourceID)
    }

    private var hasMultipleSenderOptions: Bool {
        senderOptions.count > 1
    }

    private var hasAliasOptions: Bool {
        selectedComposeBackend.capabilities.contains(.aliases) && !aliases.isEmpty
    }

    private var shouldShowFromPicker: Bool {
        hasMultipleSenderOptions || hasAliasOptions
    }

    private var fromField: some View {
        fromPickerField
            .padding(.vertical, fieldVerticalPadding)
    }

    @ViewBuilder
    private var fromPickerField: some View {
        fieldRow(label: String(localized: "From", bundle: .module)) {
            HStack(alignment: .center, spacing: BrevSpacing.sm) {
                fromSenderControl
                Spacer(minLength: BrevSpacing.sm)
                fromRowSignaturePicker
            }
        }
    }

    @ViewBuilder
    private var fromSenderControl: some View {
        if shouldShowFromPicker {
            Menu {
                fromPickerMenuContent
            } label: {
                fromPickerLabel
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel(String(localized: "From", bundle: .module))
            .accessibilityValue(currentFromEmail)
            .help(
                hasMultipleSenderOptions
                    ? String(localized: "Choose sender", bundle: .module)
                    : String(localized: "Send from a different alias", bundle: .module)
            )
        } else {
            Text(currentFromEmail)
                .brevFont(.body)
                .foregroundStyle(theme.textTertiary.color)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Signature picker at the trailing edge of the From row, mirroring Apple
    /// Mail's "Signatur:" control. Shown only when the account exposes signature
    /// options.
    @ViewBuilder
    private var fromRowSignaturePicker: some View {
        if let activeSignatureContext, !activeSignatureContext.options.isEmpty {
            Menu {
                signatureMenuContent
            } label: {
                HStack(spacing: BrevSpacing.xxs) {
                    Text("Signature:", bundle: .module)
                        .foregroundStyle(theme.textTertiary.color)
                    Text(verbatim: selectedSignature?.title ?? String(localized: "None", bundle: .module))
                        .foregroundStyle(theme.textSecondary.color)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .foregroundStyle(theme.textTertiary.color)
                }
                .brevFont(.footnote)
                .frame(height: ComposeLayout.fieldAccessorySize)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(signatureMenuHelpText)
            .accessibilityLabel(String(localized: "Signature", bundle: .module))
            .accessibilityValue(selectedSignature?.title ?? String(localized: "None", bundle: .module))
        }
    }

    private var fromPickerLabel: some View {
        HStack(spacing: BrevSpacing.xs) {
            Image(systemName: "person.crop.circle")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.textSecondary.color)
                .accessibilityHidden(true)
            Text(currentFromEmail)
                .brevFont(.body)
                .foregroundStyle(theme.textPrimary.color)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
                .foregroundStyle(theme.textTertiary.color)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var fromPickerMenuContent: some View {
        if hasMultipleSenderOptions {
            ForEach(senderOptions) { option in
                Button {
                    selectSender(option)
                } label: {
                    senderMenuLabel(
                        title: option.title,
                        subtitle: option.subtitle,
                        isSelected: selectedSenderOption.id == option.id
                    )
                }
            }
        }

        if hasAliasOptions {
            if hasMultipleSenderOptions {
                Divider()
            }

            Button {
                selectAlias(nil)
            } label: {
                senderMenuLabel(
                    title: selectedSenderOption.email,
                    subtitle: selectedSenderOption.title,
                    isSelected: selectedAliasID == nil
                )
            }

            Divider()

            ForEach(aliases) { alias in
                Button {
                    selectAlias(alias.id)
                } label: {
                    senderMenuLabel(
                        title: alias.displayName?.isEmpty == false ? alias.displayName ?? alias.email : alias.email,
                        subtitle: alias.displayName?.isEmpty == false ? alias.email : nil,
                        isSelected: selectedAliasID == alias.id
                    )
                }
            }
        }
    }

    private func senderMenuLabel(
        title: String,
        subtitle: String?,
        isSelected: Bool
    ) -> some View {
        Label {
            if let subtitle, !subtitle.isEmpty, subtitle != title {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(title)
            }
        } icon: {
            if isSelected {
                Image(systemName: "checkmark")
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var subjectField: some View {
        fieldRow(label: String(localized: "Subject", bundle: .module)) {
            TextField("", text: $subject, prompt: Text("Subject", bundle: .module))
                .textFieldStyle(.plain)
                .brevFont(.body)
                .foregroundStyle(theme.textPrimary.color)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, fieldVerticalPadding)
    }

    @ViewBuilder
    private func fieldRow<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if isAccessibilityFieldLayout {
            VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                fieldLabel(label)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: BrevSpacing.sm) {
                fieldLabel(label)
                    .frame(width: ComposeLayout.fieldLabelWidth, alignment: .trailing)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func fieldLabel(_ label: String) -> some View {
        Text(label)
            .brevFont(.subheadline)
            .foregroundStyle(theme.textSecondary.color)
    }

    @ViewBuilder
    private var attachmentsList: some View {
        if !pendingAttachments.isEmpty {
            VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                ForEach(pendingAttachments) { att in
                    let presentation = ComposeAttachmentRowPresentation.presentation(for: att)
                    VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                        HStack(spacing: BrevSpacing.sm) {
                            Image(systemName: "doc")
                                .foregroundStyle(theme.textSecondary.color)
                            Text(presentation.filename)
                                .brevFont(.footnote)
                                .foregroundStyle(theme.textPrimary.color)
                            Text(presentation.formattedSize)
                                .brevFont(.footnote)
                                .foregroundStyle(theme.textTertiary.color)
                            Spacer()
                            if let retryButtonTitle = presentation.retryButtonTitle {
                                Button(retryButtonTitle) {
                                    retryAttachmentUpload(att)
                                }
                                .buttonStyle(.borderless)
                            }
                            Button {
                                pendingAttachments.removeAll { $0.id == att.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(theme.textTertiary.color)
                            }
                            .accessibilityLabel(presentation.removeAccessibilityLabel)
                            .buttonStyle(.plain)
                        }

                        if let statusText = presentation.statusText {
                            Text(statusText)
                                .brevFont(.caption)
                                .foregroundStyle(att.uploadErrorMessage == nil ? theme.success.color : theme.danger.color)
                                .padding(.leading, BrevSpacing.xl)
                        }
                    }
                    .padding(.horizontal, BrevSpacing.lg)
                }
            }
            .padding(.vertical, BrevSpacing.sm)
            BrevDivider()
        }
    }

    @ViewBuilder
    private var bodyField: some View {
        #if os(macOS)
        if showsHTMLPreview {
            composeHTMLPreview
                .padding(BrevSpacing.lg)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .environment(\.colorScheme, bodyAppearance.colorScheme)
        } else {
            composeBodyEditor
        }
        #else
        composeBodyEditor
        #endif
    }

    private var composeBodyEditor: some View {
        ComposeBodyEditor(
            text: $bodyText,
            richHTML: $bodyHTML,
            selection: $bodySelection,
            insertionPoint: $bodyInsertionPoint,
            bodyFormat: composeBodyFormat,
            appearance: bodyAppearance,
            htmlPublicationFlushBox: htmlPublicationFlushBox,
            textCheckingConfiguration: ComposeTextCheckingPolicy.configuration(isEnabled: textCheckingEnabled),
            fontFamily: MailboxFontFamily(rawValue: mailboxFontFamilyRaw) ?? .system,
            textSize: MailboxTextSize(rawValue: mailboxTextSizeRaw) ?? .medium,
            inlineImageRegistry: inlineImageRegistry,
            onRequestLinkSheet: { input in
                linkSheetInput = input
            },
            iosRichTextTargetBox: iosRichTextTargetBox,
            onDropFileURLs: { urls in
                Task { await importAttachments(from: urls) }
            },
            onFileDragTargetChanged: { isTargeted in
                isDropTargeted = isTargeted
            }
        )
        .padding(.horizontal, BrevSpacing.xl)
        .padding(.vertical, BrevSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.colorScheme, bodyAppearance.colorScheme)
        .contextMenu {
            selectedTextAIContextMenu
        }
    }

    #if os(macOS)
    private var composeHTMLPreview: some View {
        let fontFamily = MailboxFontFamily(rawValue: mailboxFontFamilyRaw) ?? .system
        let textSize = MailboxTextSize(rawValue: mailboxTextSizeRaw) ?? .medium
        let html = ComposeHTMLPreviewSource.html(richHTML: bodyHTML, plainBody: bodyText)
        return ScrollView {
            HTMLBodyWebView(
                store: htmlPreviewWebViewStore,
                html: html,
                allowRemoteContent: false,
                fontFamily: fontFamily,
                textSize: textSize,
                renderingMode: ComposeHTMLPreviewSource.renderingMode(for: bodyAppearance),
                onOpenURL: { _ in }
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .accessibilityLabel(String(localized: "HTML preview", bundle: .module))
    }

    private var htmlPreviewToggle: some View {
        toolbarButton(
            label: showsHTMLPreview
                ? String(localized: "Edit", bundle: .module)
                : String(localized: "Preview", bundle: .module),
            systemImage: showsHTMLPreview ? "square.and.pencil" : "eye",
            isDisabled: isInteractionBlocked,
            isSelected: showsHTMLPreview
        ) {
            showsHTMLPreview.toggle()
        }
    }
    #endif

    @ViewBuilder
    private var aiPreviewPanel: some View {
        if let aiPreview {
            BrevDivider()
            VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                HStack(spacing: BrevSpacing.sm) {
                    Image(systemName: aiPreview.action.symbolName)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(theme.accent.color)
                    Text(aiPreview.title)
                        .brevFont(.headline)
                        .foregroundStyle(theme.textPrimary.color)
                    Spacer()
                    Text(aiPreview.providerLabel)
                        .brevFont(.caption)
                        .foregroundStyle(theme.textSecondary.color)
                }
                aiPreviewBody(aiPreview)
                aiPreviewActions(aiPreview)
            }
            .padding(.horizontal, BrevSpacing.lg)
            .padding(.vertical, BrevSpacing.md)
            .background(
                BrevWindowSurfaceBackground(role: .utility)
                    .opacity(0.92)
            )
        }
    }

    @ViewBuilder
    private func aiPreviewBody(_ preview: ComposeAIPreviewState) -> some View {
        switch preview.phase {
        case .loading:
            HStack(spacing: BrevSpacing.sm) {
                ProgressView()
                    .controlSize(.small)
                Text("Generating preview", bundle: .module)
                    .brevFont(.subheadline)
                    .foregroundStyle(theme.textSecondary.color)
            }
        case .success(let generatedText):
            VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                Text("Original", bundle: .module)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textTertiary.color)
                Text(preview.originalText)
                    .brevFont(.footnote)
                    .foregroundStyle(theme.textSecondary.color)
                    .lineLimit(3)
                Text("Preview", bundle: .module)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textTertiary.color)
                    .padding(.top, BrevSpacing.xs)
                ScrollView {
                    Text(generatedText)
                        .brevFont(.body)
                        .foregroundStyle(theme.textPrimary.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: ComposeLayout.aiPreviewMaxHeight)
            }
        case .failure(let message):
            BrevInlineStatus(
                message: message,
                tone: .danger,
                lineLimit: 3
            )
        }
    }

    private func aiPreviewActions(_ preview: ComposeAIPreviewState) -> some View {
        HStack(spacing: BrevSpacing.sm) {
            if preview.generatedText != nil {
                Button(preview.replaceActionTitle) {
                    applyAIPreview(.replaceTarget)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canApplyAIPreview(preview, action: .replaceTarget))

                if preview.applyTarget == .body, bodyInsertionPoint != nil {
                    Button(String(localized: "Insert at Cursor", bundle: .module)) {
                        applyAIPreview(.insertAtCursor)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canApplyAIPreview(preview, action: .insertAtCursor))
                }

                Button(String(localized: "Copy", bundle: .module)) {
                    if let text = preview.copyText {
                        copyToPasteboard(text)
                    }
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button(String(localized: "Try Again", bundle: .module)) {
                retryAIPreview(preview)
            }
            .buttonStyle(.bordered)
            .disabled(!preview.canRetry(
                currentBodyText: bodyText,
                currentSelection: bodySelection,
                currentSubject: subject
            ) || isAIWorking)

            Button(String(localized: "Cancel", bundle: .module)) {
                cancelAIPreview()
            }
            .buttonStyle(.bordered)
        }
    }

    private var bodyAppearance: ComposeBodyAppearance {
        bodyAppearanceSelection.resolved(for: theme.mode)
    }

    private var bodyAppearanceSelection: ComposeBodyAppearance {
        ComposeBodyAppearance.resolve(bodyAppearanceRaw)
    }

    private var composeBodyFormat: ComposeBodyFormat {
        switch composeMessageFormatRaw {
        case "plainText":
            return .plainText
        case "automatic", "richText":
            return .richTextHTML
        default:
            return .richTextHTML
        }
    }

    private var selectedSignature: ComposeSignatureOption? {
        activeSignatureContext?.options.first { $0.id == selectedSignatureID }
    }

    private var signatureMenuHelpText: String {
        if let selectedSignature {
            return String(localized: "Signature: \(selectedSignature.title)", bundle: .module)
        }
        return String(localized: "No signature", bundle: .module)
    }

    private var securityMenuHelpText: String {
        ComposeSecurityPresentation.menuHelpText(
            isSigningEnabled: signMessage,
            isEncryptionEnabled: encryptMessage
        )
    }

    @ViewBuilder
    private var receiptOptionsMenuContent: some View {
        Toggle(isOn: $requestReadReceipt) {
            Label(String(localized: "Request read receipt", bundle: .module), systemImage: "envelope.badge")
        }
    }

    private var receiptOptionsHelpText: String {
        requestReadReceipt
            ? String(localized: "Read receipt requested.", bundle: .module)
            : String(localized: "No read receipt requested.", bundle: .module)
    }

    @ViewBuilder
    private var formatMenu: some View {
        if composeBodyFormat == .richTextHTML {
            #if os(macOS)
            Menu {
                richTextFormattingMenuContent
            } label: {
                toolbarControlIcon("textformat")
            }
            .menuStyle(.borderlessButton)
            .disabled(isInteractionBlocked)
            .opacity(isInteractionBlocked ? 0.45 : 1)
            .accessibilityLabel(String(localized: "Format", bundle: .module))
            .help(String(localized: "Format", bundle: .module))
            #else
            Menu {
                iosRichTextFormattingMenuContent
            } label: {
                toolbarControlIcon("textformat")
            }
            .disabled(isInteractionBlocked)
            .opacity(isInteractionBlocked ? 0.45 : 1)
            .accessibilityLabel(String(localized: "Format", bundle: .module))
            #endif
        }
    }

    #if os(iOS)
    @ViewBuilder
    private var iosRichTextFormattingMenuContent: some View {
        ForEach(ComposeRichTextCommand.iosEssentials, id: \.self) { command in
            Button {
                if command == .insertImage {
                    isInlineImagePickerPresented = true
                } else {
                    command.perform(iosTarget: iosRichTextTargetBox.target)
                }
            } label: {
                Label(command.label, systemImage: command.systemImage)
            }
            .disabled(isInteractionBlocked)
        }
    }
    #endif

    @ViewBuilder
    private var richTextFormattingMenuContent: some View {
        if composeBodyFormat == .richTextHTML {
            formatMenuSection([.bold, .italic, .underline])
            Divider()
            #if os(macOS)
            formatMenuSection([.insertLink, .bulletedList, .numberedList, .insertImage])
            Divider()
            formatMenuSection([.clearFormatting])
            Divider()
            formatMenuSection([.undo, .redo])
            #else
            // Inline images stay macOS-only (cid: staging pipeline follow-up,
            // ADR-0038); undo/redo come from the text view's own affordances.
            formatMenuSection([.insertLink, .bulletedList, .numberedList])
            Divider()
            formatMenuSection([.clearFormatting])
            #endif
        }
    }

    @ViewBuilder
    private func formatMenuSection(_ commands: [ComposeRichTextCommand]) -> some View {
        ForEach(commands, id: \.self) { command in
            Button {
                // macOS ignores the target (responder chain); iOS needs it,
                // otherwise the compact overflow's Format submenu is a no-op.
                command.perform(iosTarget: iosRichTextTargetBox.target)
            } label: {
                Label(command.label, systemImage: command.systemImage)
            }
            .disabled(isInteractionBlocked)
        }
    }

    private func applySignatureSelection(_ option: ComposeSignatureOption?) {
        bodyText = ComposeSignatureBodyPolicy.body(
            afterSelecting: option?.body,
            in: bodyText,
            replacing: insertedSignatureBody
        )
        selectedSignatureID = option?.id
        insertedSignatureBody = ComposeSignatureBodyPolicy.managedSignatureBody(from: option?.body)
    }

    /// The menu items shared by the iOS in-content toolbar and the macOS
    /// native toolbar. Only the label/placement differs per platform.
    @ViewBuilder
    private var signatureMenuContent: some View {
        if let activeSignatureContext, !activeSignatureContext.options.isEmpty {
            Button {
                applySignatureSelection(nil)
            } label: {
                if selectedSignatureID == nil {
                    Label(String(localized: "No signature", bundle: .module), systemImage: "checkmark")
                } else {
                    Text("No signature", bundle: .module)
                }
            }

            Divider()

            ForEach(activeSignatureContext.options) { option in
                Button {
                    applySignatureSelection(option)
                } label: {
                    if selectedSignatureID == option.id {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        }
    }

    private var receiptOptionsMenu: some View {
        Menu {
            receiptOptionsMenuContent
        } label: {
            toolbarControlIcon(
                "envelope.badge",
                isSelected: requestReadReceipt
            )
        }
        .menuStyle(.borderlessButton)
        .disabled(isInteractionBlocked)
        .opacity(isInteractionBlocked ? 0.45 : 1)
        .accessibilityLabel(String(localized: "Message Options", bundle: .module))
        .accessibilityValue(receiptOptionsHelpText)
        .help(receiptOptionsHelpText)
    }

    @ViewBuilder
    private var securityMenuContent: some View {
        Toggle(isOn: $signMessage) {
            Label(String(localized: "Sign message", bundle: .module), systemImage: "signature")
        }
        .disabled(!hasTrustedSigningIdentity)

        Toggle(isOn: $encryptMessage) {
            Label(String(localized: "Encrypt message", bundle: .module), systemImage: "lock")
        }
        .disabled(!hasTrustedEncryptionIdentity)

        if !hasTrustedSigningIdentity || !hasTrustedEncryptionIdentity {
            Divider()
            if !hasTrustedSigningIdentity {
                Text("No trusted signing identities available.", bundle: .module)
            }
            if !hasTrustedEncryptionIdentity {
                Text("No trusted encryption identities available.", bundle: .module)
            }
        }
    }

    @ViewBuilder
    private var signatureMenu: some View {
        if let activeSignatureContext, !activeSignatureContext.options.isEmpty {
            Menu {
                signatureMenuContent
            } label: {
                toolbarControlIcon(
                    "signature",
                    isSelected: selectedSignatureID != nil
                )
            }
            .menuStyle(.borderlessButton)
            .disabled(isInteractionBlocked)
            .opacity(isInteractionBlocked ? 0.45 : 1)
            .accessibilityLabel(String(localized: "Signature", bundle: .module))
            .accessibilityValue(signatureMenuHelpText)
            .help(signatureMenuHelpText)
        }
    }

    private var activeSignatureContext: ComposeSignatureContext? {
        currentSignatureContext ?? signatureContext
    }

    @ViewBuilder
    private var securityMenu: some View {
        if composeSecurityDefaults.isFeatureEnabled {
            Menu {
                securityMenuContent
            } label: {
                toolbarControlIcon(
                    "lock.shield",
                    isSelected: signMessage || encryptMessage
                )
            }
            .menuStyle(.borderlessButton)
            .disabled(isInteractionBlocked)
            .opacity(isInteractionBlocked ? 0.45 : 1)
            .accessibilityLabel(String(localized: "Message Security", bundle: .module))
            .accessibilityValue(securityMenuHelpText)
            .help(securityMenuHelpText)
        }
    }

    // MARK: - Templates

    private var templatePickerSheet: some View {
        TemplatePickerView(
            templateSettings: $templateSettings,
            accountID: selectedComposeBackend.account.id,
            currentSubject: subject,
            currentBody: bodyText,
            onInsert: { template in
                let newBody = ComposeTemplateBodyPolicy.body(
                    applying: template,
                    to: bodyText,
                    selection: bodySelection,
                    insertionPoint: bodyInsertionPoint,
                    currentSignatureBody: currentSignatureContext?.options.first { $0.id == selectedSignatureID }?.body,
                    previousSignatureBody: insertedSignatureBody
                )
                bodyText = newBody
                subject = ComposeTemplateBodyPolicy.subject(applying: template, to: subject)
                var settings = templateSettings
                settings.recordUsage(id: template.id)
                settings.save(to: .standard)
                templateSettings = settings
            },
            onSaveAsTemplate: { name in
                var settings = templateSettings
                let template = MessageTemplate(
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    body: bodyText,
                    subject: subject.isEmpty ? nil : subject
                )
                settings.add(template)
                settings.save(to: .standard)
                templateSettings = settings
            }
        )
    }

    // MARK: - Undo-send

    private func beginUndoSend(action: @escaping () async -> Void) {
        let delaySeconds = ComposeUndoSendPolicy.delaySeconds()
        guard delaySeconds > 0 else {
            Task { await action() }
            return
        }
        pendingUndoSendCountdown = delaySeconds
        pendingUndoSendTask = Task { @MainActor in
            for remaining in ComposeUndoSendPolicy.countdownValues(for: delaySeconds) {
                guard !Task.isCancelled else { return }
                pendingUndoSendCountdown = remaining
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard !Task.isCancelled else { return }
            pendingUndoSendTask = nil
            await action()
        }
    }

    private func cancelUndoSend() {
        pendingUndoSendTask?.cancel()
        pendingUndoSendTask = nil
        pendingUndoSendCountdown = 0
    }

    // MARK: - AI Writer

    @ViewBuilder
    private var aiWriterMenuContent: some View {
        if let providerUnavailableReason = aiAvailability.providerUnavailableReason {
            Label(providerUnavailableReason.title, systemImage: "exclamationmark.triangle")
            Text(aiUnavailableHelpText(for: providerUnavailableReason))
        } else if !aiWriterSettings.isAvailable {
            Button(String(localized: "Enable AI Writer…", bundle: .module)) {
                showAIConsent = true
            }
            Text(AIWriterDisclosure.defaultProvider.transparencyLabel)
        } else if let aiBackend {
            Button {
                aiPromptDraftText = ""
                showAIPromptDraft = true
            } label: {
                Label(
                    ComposeAIAction.draftFromPrompt.title,
                    systemImage: ComposeAIAction.draftFromPrompt.symbolName
                )
            }
            .disabled(disabledReasonForPromptEntry() != nil)

            Button {
                Task { await runAIAction(.draftReply, backend: aiBackend) }
            } label: {
                Label(ComposeAIAction.draftReply.title, systemImage: ComposeAIAction.draftReply.symbolName)
            }
            .disabled(disabledReason(for: .draftReply) != nil)

            Button {
                Task { await runAIAction(.suggestSubject, backend: aiBackend) }
            } label: {
                Label(ComposeAIAction.suggestSubject.title, systemImage: ComposeAIAction.suggestSubject.symbolName)
            }
            .disabled(disabledReason(for: .suggestSubject) != nil)

            Divider()

            ForEach(ComposeAIAction.wholeDraftShortcutActions) { aiAction in
                Button {
                    Task { await runAIAction(aiAction, backend: aiBackend) }
                } label: {
                    Label(aiAction.title, systemImage: aiAction.symbolName)
                }
                .disabled(disabledReason(for: aiAction) != nil)
            }
            if bodySelection != nil {
                Divider()
                Menu(String(localized: "Rewrite Selection", bundle: .module)) {
                    selectedTextAIButtons(backend: aiBackend)
                }
            }
            Divider()
            Text(aiBackend.transparencyLabel)
        }
    }

    private var aiWriterMenuDisabled: Bool {
        AIWriterMenuPolicy.isMenuDisabled(
            isBusy: isInteractionBlocked,
            isAIWorking: isAIWorking
        )
    }

    @ViewBuilder
    private var aiWriterMenu: some View {
        Menu {
            aiWriterMenuContent
        } label: {
            ZStack {
                toolbarControlIcon("wand.and.stars", isSelected: isAIWorking)
                if isAIWorking {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .menuStyle(.borderlessButton)
        .disabled(aiWriterMenuDisabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ComposeToolbarAction.aiWriter.accessibilityLabel)
        .accessibilityValue(
            aiWriterMenuDisabled
                ? String(localized: "Unavailable", bundle: .module)
                : String(localized: "Available", bundle: .module)
        )
        .help(String(localized: "AI Writer", bundle: .module))
    }

    @ViewBuilder
    private var pluginToolbarButtons: some View {
        let contributions = BrevPluginRegistry.shared.registeredContributions(for: .composeToolbar)
        if !contributions.isEmpty {
            ForEach(contributions) { contribution in
                if let view = BrevPluginRegistry.shared.view(for: contribution) {
                    view
                }
            }
        }
    }

    @ViewBuilder
    private var selectedTextAIContextMenu: some View {
        if let aiBackend, aiAvailability.providerUnavailableReason == nil, aiWriterSettings.isAvailable {
            selectedTextAIButtons(backend: aiBackend)
            Divider()
            Text(aiBackend.transparencyLabel)
        }
    }

    @ViewBuilder
    private func selectedTextAIButtons(backend: any AIBackend) -> some View {
        ForEach(ComposeAIAction.selectedTextActions) { aiAction in
            Button {
                Task { await runAIAction(aiAction, backend: backend) }
            } label: {
                Label(aiAction.title, systemImage: aiAction.symbolName)
            }
            .disabled(disabledReason(for: aiAction) != nil)
        }
    }

    private func runAIAction(_ aiAction: ComposeAIAction, backend: any AIBackend) async {
        switch aiAction {
        case .draftFromPrompt:
            showAIPromptDraft = true
            return
        case .draftReply, .suggestSubject:
            await runAIGenerativeAction(aiAction, backend: backend)
            return
        case .shortcut:
            break
        }
        guard let shortcut = aiAction.shortcutAction else { return }
        guard let request = makeAIShortcutRequest(for: aiAction, shortcut: shortcut) else { return }
        guard canStartAIAction(aiAction) else { return }
        let preview = startAIPreview(
            action: aiAction,
            request: request,
            backend: backend,
            operation: .shortcut(shortcut)
        )
        await executeAIRequest(preview, backend: backend)
    }

    private func runAIPromptDraft(_ prompt: String, backend: any AIBackend) async {
        guard let context = ComposeAIGenerativeContext.promptDraft(prompt: prompt) else { return }
        guard disabledReasonForPromptEntry() == nil else { return }
        let request = ComposeAIShortcutRequest(
            action: .improveWriting,
            bodyText: bodyText,
            target: .wholeDraft
        )
        let preview = startAIPreview(
            action: .draftFromPrompt,
            request: request,
            backend: backend,
            operation: .generateReply(messages: context.messages, instruction: context.instruction),
            originalText: prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        await executeAIRequest(preview, backend: backend)
    }

    private func runAIGenerativeAction(
        _ action: ComposeAIAction,
        backend: any AIBackend
    ) async {
        let context: ComposeAIGenerativeContext?
        let applyTarget: ComposeAIPreviewApplyTarget
        let originalText: String?
        switch action {
        case .draftReply:
            context = ComposeAIGenerativeContext.replyDraft(
                replyingTo: replyingTo,
                draftBody: bodyText
            )
            applyTarget = .body
            originalText = context?.messages.map(\.content).joined(separator: "\n\n")
        case .suggestSubject:
            context = ComposeAIGenerativeContext.subjectSuggestion(
                bodyText: bodyText,
                currentSubject: subject
            )
            applyTarget = .subject(subjectSnapshot: subject)
            originalText = bodyText
        case .draftFromPrompt, .shortcut:
            return
        }
        guard let context else { return }
        guard canStartAIAction(action) else { return }
        let request = ComposeAIShortcutRequest(
            action: .improveWriting,
            bodyText: bodyText,
            target: .wholeDraft
        )
        let preview = startAIPreview(
            action: action,
            request: request,
            backend: backend,
            operation: .generateReply(messages: context.messages, instruction: context.instruction),
            applyTarget: applyTarget,
            originalText: originalText
        )
        await executeAIRequest(preview, backend: backend)
    }

    private func startAIPreview(
        action: ComposeAIAction,
        request: ComposeAIShortcutRequest,
        backend: any AIBackend,
        operation: ComposeAIPreviewOperation,
        applyTarget: ComposeAIPreviewApplyTarget = .body,
        originalText: String? = nil
    ) -> ComposeAIPreviewState {
        nextAIPreviewID += 1
        let preview = ComposeAIPreviewState(
            id: nextAIPreviewID,
            action: action,
            request: request,
            providerLabel: backend.transparencyLabel,
            phase: .loading,
            operation: operation,
            applyTarget: applyTarget,
            originalText: originalText
        )
        aiPreview = preview
        return preview
    }

    private func executeAIRequest(
        _ preview: ComposeAIPreviewState,
        backend: any AIBackend
    ) async {
        let request = preview.request
        activeAIShortcutRequest = request
        isAIWorking = true
        errorMessage = nil
        do {
            let response: AIResponse
            switch preview.operation {
            case .shortcut(let action):
                response = try await backend.shortcut(action, on: request.inputText)
            case .generateReply(let messages, let instruction):
                response = try await backend.generateReply(to: messages, instruction: instruction)
            }
            updateAIPreview(preview) { current in
                if canApplyAIShortcutResponse(request) {
                    return current.succeeded(with: response.text)
                }
                return current.failed(with: ComposePresentation.aiShortcutStaleResponseMessage)
            }
            finishAIShortcut(request)
        } catch is CancellationError {
            finishAIShortcut(request)
        } catch {
            updateAIPreview(preview) { current in
                if canApplyAIShortcutResponse(request) {
                    return current.failed(with: ComposePresentation.aiShortcutErrorMessage(for: error))
                }
                return current.failed(with: ComposePresentation.aiShortcutStaleResponseMessage)
            }
            finishAIShortcut(request)
        }
    }

    private func updateAIPreview(
        _ preview: ComposeAIPreviewState,
        transform: (ComposeAIPreviewState) -> ComposeAIPreviewState
    ) {
        guard aiPreview?.id == preview.id, let current = aiPreview else { return }
        aiPreview = transform(current)
    }

    private func makeAIShortcutRequest(
        for aiAction: ComposeAIAction,
        shortcut: AIShortcutAction
    ) -> ComposeAIShortcutRequest? {
        switch aiAction.scope {
        case .wholeDraft:
            return ComposeAIShortcutRequest(
                action: shortcut,
                bodyText: bodyText,
                target: .wholeDraft
            )
        case .selection:
            guard let bodySelection else { return nil }
            return ComposeAIShortcutRequest(
                action: shortcut,
                bodyText: bodyText,
                target: .selection(bodySelection)
            )
        case .prompt, .replyContext, .subject:
            return nil
        }
    }

    private func canStartAIAction(_ action: ComposeAIAction) -> Bool {
        disabledReason(for: action) == nil
    }

    private func canApplyAIShortcutResponse(_ request: ComposeAIShortcutRequest) -> Bool {
        ComposeAIShortcutResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: activeAIShortcutRequest,
            currentBodyText: bodyText,
            currentSelection: bodySelection
        )
    }

    private func canApplyAIPreview(
        _ preview: ComposeAIPreviewState,
        action: ComposeAIPreviewApplyAction
    ) -> Bool {
        if case .subject = preview.applyTarget {
            return action == .replaceTarget && ComposeAIPreviewApplyPolicy.appliedSubject(
                preview,
                currentBodyText: bodyText,
                currentSubject: subject
            ) != nil
        }
        return ComposeAIPreviewApplyPolicy.appliedText(
            preview,
            action: action,
            currentBodyText: bodyText,
            currentSelection: bodySelection,
            insertionPoint: bodyInsertionPoint
        ) != nil
    }

    private func applyAIPreview(_ action: ComposeAIPreviewApplyAction) {
        guard let aiPreview else { return }
        if case .subject = aiPreview.applyTarget {
            guard action == .replaceTarget,
                  let updatedSubject = ComposeAIPreviewApplyPolicy.appliedSubject(
                      aiPreview,
                      currentBodyText: bodyText,
                      currentSubject: subject
                  ) else {
                self.aiPreview = aiPreview.failed(with: ComposePresentation.aiShortcutStaleResponseMessage)
                return
            }
            subject = updatedSubject
            self.aiPreview = nil
            return
        }
        guard let updatedText = ComposeAIPreviewApplyPolicy.appliedText(
            aiPreview,
            action: action,
            currentBodyText: bodyText,
            currentSelection: bodySelection,
            insertionPoint: bodyInsertionPoint
        ) else {
            self.aiPreview = aiPreview.failed(with: ComposePresentation.aiShortcutStaleResponseMessage)
            return
        }
        bodyText = updatedText
        bodySelection = nil
        bodyInsertionPoint = nil
        self.aiPreview = nil
    }

    private func retryAIPreview(_ preview: ComposeAIPreviewState) {
        guard let aiBackend else { return }
        guard preview.canRetry(
            currentBodyText: bodyText,
            currentSelection: bodySelection,
            currentSubject: subject
        ) else {
            aiPreview = preview.failed(with: ComposePresentation.aiShortcutStaleResponseMessage)
            return
        }
        let loadingPreview = ComposeAIPreviewState(
            id: preview.id,
            action: preview.action,
            request: preview.request,
            providerLabel: preview.providerLabel,
            phase: .loading,
            operation: preview.operation,
            applyTarget: preview.applyTarget,
            originalText: preview.originalTextOverride
        )
        aiPreview = loadingPreview
        Task {
            await executeAIRequest(loadingPreview, backend: aiBackend)
        }
    }

    private func cancelAIPreview() {
        aiPreview = nil
    }

    private func copyToPasteboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = text
        #endif
    }

    private func disabledReasonForPromptEntry() -> ComposeAIActionDisabledReason? {
        ComposeAIActionAvailability.disabledReason(
            for: .draftFromPrompt,
            in: aiAvailability.context(
                bodyText: bodyText,
                selectedText: bodySelection?.selectedText,
                promptText: "Prompt",
                hasReplyContext: replyingTo != nil
            )
        )
    }

    private func disabledReason(for action: ComposeAIAction) -> ComposeAIActionDisabledReason? {
        ComposeAIActionAvailability.disabledReason(
            for: action,
            in: aiAvailability.context(
                bodyText: bodyText,
                selectedText: bodySelection?.selectedText,
                hasReplyContext: replyingTo != nil
            )
        )
    }

    private var aiWriterSettings: AIWriterSettings {
        AIWriterSettings(isEnabled: aiEnabled, consentGiven: aiConsentGiven)
    }

    private var aiAvailability: ComposeAIAvailabilityState {
        ComposeAIAvailabilityState(
            settings: aiWriterSettings,
            hasProviderBackend: aiBackend != nil,
            backendSupportsAIWriter: backendSupportsAIWriter,
            isBusy: isBusy || isWorkBlocked,
            hasActiveRequest: activeAIShortcutRequest != nil
        )
    }

    private func aiUnavailableHelpText(for reason: ComposeAIActionDisabledReason) -> String {
        switch reason {
        case .unsupportedAccount:
            return AIWriterDisclosure.unsupportedAccountMessage
        case .missingBackend:
            return String(
                localized: "AI Writer is enabled for this account type, but no AI provider is available in this compose window.",
                bundle: .module
            )
        default:
            return reason.title
        }
    }

    private func finishAIShortcut(_ request: ComposeAIShortcutRequest) {
        guard activeAIShortcutRequest == request else { return }
        activeAIShortcutRequest = nil
        isAIWorking = false
    }

    // MARK: - Link application (#251)

    /// Applies the confirmed URL and display text to the current selection.
    ///
    /// The actual attributed-string mutation lives in the Coordinator; we
    /// broadcast via the responder chain so the editor can do it with the
    /// correct NSTextView context.
    private func applyLink(url: URL, displayText: String) {
        #if os(macOS)
        NSApp.sendAction(
            #selector(ComposeBodyEditorRichActions.brevApplyLink(_:)),
            to: nil,
            from: ComposeBodyEditorLinkPayload(url: url, displayText: displayText)
        )
        #else
        iosRichTextTargetBox.target?.applyLink(url: url, displayText: displayText)
        #endif
    }

    /// Clears the `.link` attribute from the current selection.
    private func removeLink() {
        #if os(macOS)
        NSApp.sendAction(
            #selector(ComposeBodyEditorRichActions.brevRemoveLink(_:)),
            to: nil,
            from: nil
        )
        #else
        iosRichTextTargetBox.target?.removeLink()
        #endif
    }

    #if os(iOS)
    private func handleSelectedInlineImage() {
        guard let item = selectedInlineImageItem else { return }
        Task { await insertSelectedInlineImage(item) }
    }

    /// Loads a selected Photos item and inserts a CID-backed attachment at the caret.
    @MainActor
    private func insertSelectedInlineImage(_ item: PhotosPickerItem) async {
        defer { selectedInlineImageItem = nil }
        guard !isInteractionBlocked else { return }
        guard let transferredData = try? await item.loadTransferable(type: Data.self) else { return }
        guard !isInteractionBlocked else { return }

        if transferredData.count <= ComposeInlineImagePolicy.maxBytes,
           let mimeType = ComposeInlineImageData.mimeType(for: transferredData) {
            _ = iosRichTextTargetBox.target?.insertInlineImage(
                data: transferredData,
                mimeType: mimeType
            )
            return
        }

        guard let image = UIImage(data: transferredData),
              let jpegData = image.jpegData(compressionQuality: 0.85),
              jpegData.count <= ComposeInlineImagePolicy.maxBytes else {
            return
        }
        _ = iosRichTextTargetBox.target?.insertInlineImage(
            data: jpegData,
            mimeType: "image/jpeg"
        )
    }
    #endif

    // MARK: - Logic

    /// The email address the composer is currently sending as.
    /// Resolves the selected alias when one is set, otherwise falls
    /// back to the account's default identity.
    private var currentFromEmail: String {
        if let selectedAliasID,
           let alias = aliases.first(where: { $0.id == selectedAliasID }) {
            return alias.email
        }
        return selectedSenderOption.email
    }

    private var canSend: Bool {
        guard scheduledSendDate == nil || selectedComposeBackend.extensionService(ScheduledSendManaging.self) != nil
        else { return false }
        return ComposeDraftBuilder.canSend(
            to: resolvedToRecipients,
            cc: resolvedCcRecipients,
            bcc: resolvedBccRecipients
        ) && !ComposeQuotedBodyUpgradePolicy.blocksSending(
            isUpgradePending: isQuotedBodyUpgradePending
        )
    }

    private var canSave: Bool {
        ComposeDraftBuilder.canSave(
            to: resolvedToRecipients,
            cc: resolvedCcRecipients,
            bcc: resolvedBccRecipients,
            subject: subject,
            bodyText: bodyTextExcludingManagedSignature,
            hasAttachments: !pendingAttachments.isEmpty
        ) && !ComposeQuotedBodyUpgradePolicy.blocksSending(
            isUpgradePending: isQuotedBodyUpgradePending
        )
    }

    private var isBusy: Bool {
        ComposePresentation.isInteractionBusy(
            isSending: isSending,
            isSavingDraft: isSavingDraft,
            isAIWorking: isAIWorking
        )
    }

    private var isInteractionBlocked: Bool {
        isBusy || isWorkBlocked
    }

    private var bodyTextExcludingManagedSignature: String {
        ComposeSignatureBodyPolicy.body(
            removing: insertedSignatureBody,
            from: bodyText
        )
    }

    private func send(bypassingSendGuard: Bool = false) async {
        guard !ComposeQuotedBodyUpgradePolicy.blocksSending(
            isUpgradePending: isQuotedBodyUpgradePending
        ) else { return }
        guard canStartComposeOperation(kind: .send) else { return }
        if let missingKeyWarning = ComposeSecurityPresentation.missingKeyWarning(
            isSigningEnabled: signMessage,
            hasTrustedSigningIdentity: hasTrustedSigningIdentity,
            isEncryptionEnabled: encryptMessage,
            hasTrustedEncryptionIdentity: hasTrustedEncryptionIdentity
        ) {
            errorMessage = missingKeyWarning
            return
        }
        if !bypassingSendGuard,
           let warning = ComposeSendGuardPolicy.warning(
               for: currentSendGuardSnapshot(),
               preferences: ComposeSendGuardPreferences.load()
           ) {
            pendingSendGuardWarning = warning
            return
        }
        let request = startComposeOperation(kind: .send)
        isSending = true
        errorMessage = nil
        defer { finishComposeOperation(request) }

        do {
            let draft = try await draftForSend(request: request)
            let result = try await send(draft)
            guard canApplyComposeOperationResponse(request) else { return }
            recordRecentRecipients(from: draft)
            await onCompletion(.sentMessage(
                draft: draft,
                result: result,
                relatedHeader: replyingTo ?? forwardingFrom
            ))
            hasCompletedExplicitOperation = true
            close()
        } catch is CancellationError {
            // The composer may be dismissed while work is in flight.
        } catch {
            guard canApplyComposeOperationResponse(request) else { return }
            errorMessage = ComposePresentation.sendErrorMessage(for: error)
        }
    }

    private func saveDraft() async {
        guard !ComposeQuotedBodyUpgradePolicy.blocksSending(
            isUpgradePending: isQuotedBodyUpgradePending
        ) else { return }
        guard canStartComposeOperation(kind: .saveDraft) else { return }
        let request = startComposeOperation(kind: .saveDraft)
        isSavingDraft = true
        errorMessage = nil
        defer { finishComposeOperation(request) }

        do {
            let saved = try await persistDraft(for: request)
            guard canApplyComposeOperationResponse(request) else { return }
            await onCompletion(.savedDraft(saved))
            hasCompletedExplicitOperation = true
            close()
        } catch is CancellationError {
            // The composer may be dismissed while work is in flight.
        } catch {
            guard canApplyComposeOperationResponse(request) else { return }
            errorMessage = ComposePresentation.saveDraftErrorMessage(for: error)
        }
    }

    private func canStartComposeOperation(kind: ComposeOperationKind) -> Bool {
        ComposeOperationStartPolicy.canStartOperation(
            requestedKind: kind,
            isInteractionBusy: isBusy,
            isBlocked: isWorkBlocked,
            activeRequest: activeComposeOperationRequest
        )
    }

    private func close() {
        cancelAutoSaveDraftTask()
        if ComposeAutoSavePolicy.shouldAutoSaveOnDismiss(
            canSave: canSave,
            isBusy: isBusy,
            hasCompletedExplicitOperation: hasCompletedExplicitOperation
        ) {
            Task { await autoSaveDraftOnDismiss() }
        }
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func autoSaveDraftOnDismiss() async {
        await autoSaveDraft(requireApplicableResponse: false)
    }

    private func autoSaveDraftAfterInactivity() async {
        await autoSaveDraft(requireApplicableResponse: true)
    }

    private func autoSaveDraft(requireApplicableResponse: Bool) async {
        guard canStartComposeOperation(kind: .autoSaveDraft) else { return }
        guard ComposeDraftBuilder.canSave(
            to: resolvedToRecipients,
            cc: resolvedCcRecipients,
            bcc: resolvedBccRecipients,
            subject: subject,
            bodyText: bodyTextExcludingManagedSignature,
            hasAttachments: !pendingAttachments.isEmpty
        ) else { return }
        let request = startComposeOperation(kind: .autoSaveDraft)
        defer { finishComposeOperation(request) }
        do {
            let saved = try await persistDraft(for: request)
            if requireApplicableResponse {
                guard canApplyComposeOperationResponse(request) else { return }
            }
            savedDraftRemoteID = saved.remoteID
            await onCompletion(.savedDraft(saved))
        } catch is CancellationError {
            // Composer dismissed during auto-save — acceptable.
        } catch {
            errorMessage = ComposePresentation.saveDraftErrorMessage(for: error)
        }
    }

    private func draftForSend(request: ComposeOperationRequest) async throws -> Draft {
        htmlPublicationFlushBox.performFlush()
        // Reconcile the inline-image registry against the current HTML body and
        // stage any images that aren't yet known to the backend. This must happen
        // before building or persisting the draft so the attachment IDs are
        // available in `currentDraft()`.
        try await stageInlineImages()
        guard ComposeSendDraftPersistencePolicy.shouldPersistDraftBeforeSend(
            hasPendingAttachments: !pendingAttachments.isEmpty
        ) else {
            return currentDraft()
        }
        return try await persistDraft(for: request)
    }

    /// Reconciles the inline-image registry against the serialised HTML body,
    /// then stages any images whose Content-IDs are absent from
    /// `stagedInlineAttachments` with the backend.
    private func stageInlineImages() async throws {
        let html = composeBodyFormat == .richTextHTML ? (bodyHTML ?? bodyText) : bodyText
        let images = ComposeDraftBuilder.inlineAttachments(
            fromRegistry: inlineImageRegistry,
            draftID: draftID,
            bodyHTML: html
        )
        let stagingSourceID = activeComposeSourceID
        let backend = selectedComposeBackend
        let sourceID = selectedComposeSourceID
        for image in images {
            // Backend attachment IDs are source-local. A sender/source switch
            // must restage the same Content-ID instead of reusing another
            // account's opaque ID.
            guard ComposeAttachmentUploadState.shouldStageInlineAttachment(
                stagedInlineAttachments[image.contentID],
                for: stagingSourceID
            ) else { continue }
            let attID: String
            if let sourceID {
                attID = try await backend.stageInlineAttachment(
                    draftID: draftID,
                    contentID: image.contentID,
                    filename: image.filename,
                    mimeType: image.mimeType,
                    data: image.data,
                    sourceID: sourceID
                )
            } else {
                attID = try await backend.stageInlineAttachment(
                    draftID: draftID,
                    contentID: image.contentID,
                    filename: image.filename,
                    mimeType: image.mimeType,
                    data: image.data
                )
            }
            stagedInlineAttachments[image.contentID] = ComposeStagedInlineAttachment(
                attachmentID: attID,
                sourceID: stagingSourceID
            )
        }
        // Remove any IDs whose images were reconciled away.
        let stagedCIDs = Set(inlineImageRegistry.staged.map(\.contentID))
        stagedInlineAttachments = stagedInlineAttachments.filter { stagedCIDs.contains($0.key) }
    }

    private func persistDraft(for request: ComposeOperationRequest) async throws -> Draft {
        htmlPublicationFlushBox.performFlush()
        // Save and autosave must persist CID parts too, not only the send path.
        // The staging method is idempotent for already-known Content-IDs.
        try await stageInlineImages()
        let draft = currentDraft()
        var saved = try await save(draft)
        // Record the server-assigned id before any bail-out: if the request was
        // superseded by a newer keystroke, the draft we just saved still exists
        // on the server, so the next save must reuse this id to supersede it
        // rather than orphaning it as a duplicate draft.
        savedDraftRemoteID = saved.remoteID
        guard canApplyComposeOperationResponse(request) else { throw CancellationError() }
        let shouldUploadAttachments = ComposeAttachmentUploadState.shouldUploadAttachments(for: request.kind)
        if shouldUploadAttachments,
           ComposeAttachmentUploadState.unresolvedFailureMessage(for: pendingAttachments) != nil {
            throw ComposeAttachmentRetryRequiredError()
        }

        for att in shouldUploadAttachments ? ComposeAttachmentUploadState.attachmentsNeedingUpload(pendingAttachments) : [] {
            do {
                let attID = try await uploadAttachment(
                    draftID: saved.remoteID ?? saved.id,
                    data: att.data,
                    filename: att.filename,
                    mimeType: att.mimeType
                )
                guard canApplyComposeOperationResponse(request) else { throw CancellationError() }
                markAttachmentUploaded(id: att.id, remoteID: attID)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard canApplyComposeOperationResponse(request) else { throw CancellationError() }
                markAttachmentFailed(id: att.id, error: error)
                throw error
            }
        }
        if shouldUploadAttachments {
            // Set (not append) the full uploaded set — currentDraft() already
            // carries forward previously-uploaded IDs, so appending would
            // duplicate them.
            let reconciledAttachmentIDs = ComposeAttachmentUploadState.mergedAttachmentIDs(
                inline: currentInlineAttachmentIDs,
                regular: ComposeAttachmentUploadState.uploadedAttachmentIDs(
                    from: pendingAttachments
                )
            )
            if ComposeAttachmentUploadState.requiresDraftResave(
                savedAttachmentIDs: saved.attachmentIDs,
                reconciledAttachmentIDs: reconciledAttachmentIDs
            ) {
                saved.attachmentIDs = reconciledAttachmentIDs
                saved = try await save(saved)
                // As above, record the server id before cancellation checks so
                // a newer operation supersedes the actual latest remote draft.
                savedDraftRemoteID = saved.remoteID
                guard canApplyComposeOperationResponse(request) else { throw CancellationError() }
            }
        }
        return saved
    }

    private var currentInlineAttachmentIDs: [String] {
        ComposeAttachmentUploadState.inlineAttachmentIDs(
            from: stagedInlineAttachments,
            for: activeComposeSourceID
        )
    }

    private func currentDraft() -> Draft {
        // Already-staged inline image IDs come first so `stagedAttachments(for:)`
        // finds them alongside regular file attachments. Regular attachments are
        // appended after so ordering is stable across retries.
        let attachmentIDs = ComposeAttachmentUploadState.mergedAttachmentIDs(
            inline: currentInlineAttachmentIDs,
            regular: ComposeAttachmentUploadState.uploadedAttachmentIDs(from: pendingAttachments)
        )
        return ComposeDraftBuilder.draft(
            id: draftID,
            remoteID: savedDraftRemoteID,
            identityID: selectedAliasID,
            replyingTo: replyingTo,
            forwardingFrom: forwardingFrom,
            to: resolvedToRecipients,
            cc: resolvedCcRecipients,
            bcc: resolvedBccRecipients,
            subject: subject,
            bodyText: bodyText,
            bodyHTML: bodyHTML,
            bodyFormat: composeBodyFormat,
            signatureBody: nil,
            // Carry forward already-uploaded attachments so every save —
            // including autosave, which never re-uploads — preserves them
            // instead of persisting a draft with no attachments.
            attachmentIDs: attachmentIDs,
            scheduledFor: scheduledSendDate,
            readReceiptNotificationTo: requestReadReceipt ? currentFromEmail : nil,
            securityMode: OutboundMessageSecurityMode(
                signing: signMessage,
                encrypting: encryptMessage
            )
        )
    }

    private var autoSaveFingerprint: ComposeAutoSaveFingerprint {
        ComposeAutoSaveFingerprint(
            senderID: selectedSenderID,
            identityID: selectedAliasID,
            to: resolvedToRecipients,
            cc: resolvedCcRecipients,
            bcc: resolvedBccRecipients,
            subject: subject,
            bodyText: bodyTextExcludingManagedSignature,
            bodyHTML: composeBodyFormat == .richTextHTML ? bodyHTML : nil,
            attachmentIDs: pendingAttachments.map(\.id),
            requestReadReceipt: requestReadReceipt
        )
    }

    private func scheduleAutoSaveAfterInactivity() {
        cancelAutoSaveDraftTask()
        guard ComposeAutoSavePolicy.shouldScheduleAutoSave(
            canSave: canSave,
            isBusy: isBusy,
            isBlocked: isWorkBlocked
        ) else {
            return
        }
        autoSaveDraftTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: ComposeAutoSavePolicy.inactivityDelayNanoseconds)
            } catch {
                return
            }
            await autoSaveDraftAfterInactivity()
        }
    }

    private func cancelAutoSaveDraftTask() {
        autoSaveDraftTask?.cancel()
        autoSaveDraftTask = nil
    }

    private func retryAttachmentUpload(_ attachment: PendingAttachment) {
        guard let index = pendingAttachments.firstIndex(where: { $0.id == attachment.id }) else { return }
        pendingAttachments[index] = ComposeAttachmentUploadState.clearFailure(pendingAttachments[index])
        errorMessage = nil
    }

    private func markAttachmentUploaded(id: UUID, remoteID: String) {
        guard let index = pendingAttachments.firstIndex(where: { $0.id == id }) else { return }
        pendingAttachments[index] = ComposeAttachmentUploadState.markUploaded(
            pendingAttachments[index],
            remoteID: remoteID
        )
    }

    private func markAttachmentFailed(id: UUID, error: any Error) {
        guard let index = pendingAttachments.firstIndex(where: { $0.id == id }) else { return }
        pendingAttachments[index] = ComposeAttachmentUploadState.markFailed(
            pendingAttachments[index],
            message: error.localizedDescription
        )
    }

    private func save(_ draft: Draft) async throws -> Draft {
        let backend = selectedComposeBackend
        if let sourceID = selectedComposeSourceID {
            return try await backend.save(draft: draft, sourceID: sourceID)
        }
        return try await backend.save(draft: draft)
    }

    private func uploadAttachment(
        draftID: String,
        data: Data,
        filename: String,
        mimeType: String
    ) async throws -> String {
        let backend = selectedComposeBackend
        if let sourceID = selectedComposeSourceID {
            return try await backend.uploadAttachment(
                draftID: draftID,
                data: data,
                filename: filename,
                mimeType: mimeType,
                sourceID: sourceID
            )
        }
        return try await backend.uploadAttachment(
            draftID: draftID,
            data: data,
            filename: filename,
            mimeType: mimeType
        )
    }

    private func send(_ draft: Draft) async throws -> SendResult {
        let backend = selectedComposeBackend
        if let sourceID = selectedComposeSourceID {
            return try await backend.send(draft: draft, sourceID: sourceID)
        }
        return try await backend.send(draft: draft)
    }

    private func recordRecentRecipients(from draft: Draft) {
        let recipients = draft.to + draft.cc + draft.bcc
        let observations = recipients.map { recipient in
            RecentRecipientObservation(
                accountID: selectedComposeBackend.account.id,
                displayName: recipient.name,
                email: recipient.email,
                date: Date()
            )
        }
        RecentRecipientStore().record(observations)
    }

    private func startComposeOperation(kind: ComposeOperationKind) -> ComposeOperationRequest {
        nextComposeOperationRequestID += 1
        let request = ComposeOperationRequest(
            id: nextComposeOperationRequestID,
            kind: kind,
            snapshot: currentComposeOperationSnapshot()
        )
        activeComposeOperationRequest = request
        return request
    }

    private func canApplyComposeOperationResponse(_ request: ComposeOperationRequest) -> Bool {
        ComposeOperationResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: activeComposeOperationRequest,
            currentSnapshot: currentComposeOperationSnapshot()
        )
    }

    private func finishComposeOperation(_ request: ComposeOperationRequest) {
        guard activeComposeOperationRequest == request else { return }
        activeComposeOperationRequest = nil
        switch request.kind {
        case .send:
            isSending = false
        case .saveDraft:
            isSavingDraft = false
        case .autoSaveDraft:
            break
        }
    }

    private func invalidateComposeOperation() {
        activeComposeOperationRequest = nil
        isSending = false
        isSavingDraft = false
    }

    private func currentComposeOperationSnapshot() -> ComposeOperationSnapshot {
        ComposeOperationSnapshot(
            senderID: selectedSenderID,
            identityID: selectedAliasID,
            to: resolvedToRecipients,
            cc: resolvedCcRecipients,
            bcc: resolvedBccRecipients,
            subject: subject,
            bodyText: bodyText,
            attachmentIDs: pendingAttachments.map(\.id)
        )
    }

    private func currentSendGuardSnapshot() -> ComposeSendGuardSnapshot {
        ComposeSendGuardSnapshot(
            fromEmail: currentFromEmail,
            to: resolvedToRecipients,
            cc: resolvedCcRecipients,
            bcc: resolvedBccRecipients,
            subject: subject,
            bodyText: bodyTextExcludingManagedSignature,
            hasAttachments: !pendingAttachments.isEmpty
        )
    }

    private var resolvedToRecipients: [String] {
        ComposeDraftBuilder.recipientAddresses(from: to + [toInputText])
    }

    private var resolvedCcRecipients: [String] {
        ComposeDraftBuilder.recipientAddresses(from: cc + [ccInputText])
    }

    private var resolvedBccRecipients: [String] {
        ComposeDraftBuilder.recipientAddresses(from: bcc + [bccInputText])
    }

    private func handleFilePick(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task { await importAttachments(from: urls) }
        case .failure(let error):
            errorMessage = ComposeAttachmentImport.filePickerErrorMessage(for: error)
        }
    }

    private func importPrefillAttachmentsIfNeeded() async {
        guard !didImportPrefillAttachments else { return }
        didImportPrefillAttachments = true
        guard let prefill, !prefill.attachmentFileURLs.isEmpty else { return }
        await importAttachments(from: prefill.attachmentFileURLs)
    }

    /// Attaches files and loose images dropped anywhere on the compose window.
    /// Returns `false` when nothing in the drop can be attached so the drop is
    /// refused rather than silently swallowed.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let sources = providers.compactMap { provider -> (NSItemProvider, ComposeAttachmentDrop.Source)? in
            guard let source = ComposeAttachmentDrop.source(
                forRegisteredTypeIdentifiers: provider.registeredTypeIdentifiers
            ) else { return nil }
            return (provider, source)
        }
        guard !sources.isEmpty else { return false }
        Task {
            var urls: [URL] = []
            var images: [ComposeAttachmentDrop.DroppedImage] = []
            for (provider, source) in sources {
                switch source {
                case .fileURL:
                    if let url = await loadDroppedFileURL(from: provider) {
                        urls.append(url)
                    }
                case .imageData(let type):
                    if let data = await loadDroppedData(from: provider, type: type) {
                        images.append(ComposeAttachmentDrop.DroppedImage(data: data, type: type))
                    }
                }
            }
            if !urls.isEmpty {
                await importAttachments(from: urls)
            }
            if !images.isEmpty {
                let imported = await ComposeAttachmentDrop.importDroppedImages(
                    images,
                    existingFilenames: Set(pendingAttachments.map(\.filename)),
                    existingByteCount: pendingAttachments.reduce(0) { $0 + $1.data.count }
                )
                pendingAttachments.append(contentsOf: imported.attachments)
                if let message = imported.errorMessage {
                    errorMessage = message
                }
            }
        }
        return true
    }

    private func loadDroppedFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                continuation.resume(returning: ComposeAttachmentDrop.fileURL(fromLoadedItem: item))
            }
        }
    }

    private func loadDroppedData(from provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private func importAttachments(from urls: [URL]) async {
        let imported = await ComposeAttachmentImport.importFiles(
            from: urls,
            existingFilenames: Set(pendingAttachments.map(\.filename)),
            existingByteCount: pendingAttachments.reduce(0) { $0 + $1.data.count }
        )
        pendingAttachments.append(contentsOf: imported.attachments)
        errorMessage = imported.errorMessage
        if imported.errorMessage == nil {
            SharedComposePayload.purgeImportedHandoffDirectories(for: urls)
        }
    }

    // MARK: - Aliases and signature reload

    /// Replaces the provisional listing-snippet quote with CTE-decoded body
    /// text once the full message is available. Skips if the user already edited.
    private func upgradeQuotedOriginalBodyIfNeeded() async {
        guard let provisionalSignedBody, bodyText == provisionalSignedBody else { return }

        let header: MessageHeader
        let placement = ComposeReplyQuotePlacement.load()
        let buildBase: (String) -> String
        if let replyingTo {
            header = replyingTo
            buildBase = { quoteText in
                ComposeReplyFormatter.body(
                    for: replyingTo,
                    quoteText: quoteText,
                    placement: placement
                )
            }
        } else if let forwardingFrom {
            header = forwardingFrom
            buildBase = { quoteText in
                ComposeForwardFormatter.body(for: forwardingFrom, quoteText: quoteText)
            }
        } else {
            return
        }

        let messageBody: MessageBody?
        do {
            messageBody = try await selectedComposeBackend.body(
                for: header.id,
                sourceID: activeComposeSourceID
            )
        } catch {
            do {
                messageBody = try await selectedComposeBackend.body(for: header.id)
            } catch {
                return
            }
        }

        let quoteText = ComposeQuoteTextPolicy.quoteText(
            body: messageBody,
            fallbackSnippet: header.snippet
        )
        let upgradedBase = buildBase(quoteText)
        let upgraded = ComposeSignatureBodyPolicy.body(
            afterSelecting: selectedSignature?.body,
            in: upgradedBase,
            replacing: insertedSignatureBody
        )

        guard bodyText == provisionalSignedBody else { return }
        bodyText = upgraded
        self.provisionalSignedBody = upgraded
        insertedSignatureBody = ComposeSignatureBodyPolicy.managedSignatureBody(
            from: selectedSignature?.body
        )
    }

    /// Fetches the server-side alias list once per compose session.
    /// Backends without the `.aliases` capability throw
    /// `.notSupported`; we silently treat that as "no aliases" and
    /// fall back to the default account identity.
    private func loadAliases() async {
        let backend = selectedComposeBackend
        guard backend.capabilities.contains(.aliases) else {
            aliases = []
            return
        }
        do {
            let fetched = try await listAliases(using: backend)
            aliases = fetched
        } catch {
            aliases = []
        }
    }

    private func listAliases(using backend: any MailBackend) async throws -> [ServerAlias] {
        try await backend.listAliases()
    }

    private func selectSender(_ option: ComposeSenderOption) {
        guard option.id != selectedSenderID else { return }
        selectedSenderID = option.id
        selectedAliasID = nil
        recipientSuggestions = [:]
        currentSignatureContext = nil
        applySignatureSelection(nil)
        Task {
            await loadAliases()
            await reloadServerSignaturesIfPossible()
        }
    }

    /// Updates the selected alias and (best-effort) reloads the
    /// server signature list, since signatures are typically bound
    /// to a specific identity. We always clear the current
    /// signature selection so a body that already had a different
    /// identity's signature doesn't bleed into the new identity.
    private func selectAlias(_ aliasID: String?) {
        guard aliasID != selectedAliasID else { return }
        selectedAliasID = aliasID
        currentSignatureContext = nil
        applySignatureSelection(nil)
        Task { await reloadServerSignaturesIfPossible() }
    }

    private func reloadServerSignaturesIfPossible() async {
        let backend = selectedComposeBackend
        guard backend.capabilities.contains(.serverSignatures) else {
            currentSignatureContext = nil
            return
        }
        let signatures: [ServerSignature]
        do {
            signatures = try await listServerSignatures(using: backend)
        } catch {
            currentSignatureContext = nil
            return
        }
        let context = ComposeServerSignaturePolicy.contextForReload(
            serverSignatures: signatures,
            selectedAliasID: selectedAliasID,
            senderEmail: currentFromEmail,
            localContext: signatureContext
        )
        currentSignatureContext = context
        if recoveredDraft == nil, let selected = context?.selectedSignature {
            applySignatureSelection(selected)
        }
    }

    private func listServerSignatures(using backend: any MailBackend) async throws -> [ServerSignature] {
        try await backend.listServerSignatures()
    }

    // MARK: - Schedule send helpers

    private func clearScheduledSendDate() {
        scheduledSendDate = nil
    }
}

private extension ComposeErrorStatus.Tone {
    var inlineStatusTone: BrevInlineStatusTone {
        switch self {
        case .danger:
            return .danger
        }
    }
}

private enum ComposeLayout {
    static let fieldLabelWidth: CGFloat = 64
    static let fieldAccessorySize: CGFloat = 24
    static let aiPreviewMaxHeight: CGFloat = 180
}

private struct ComposeFileImporter: ViewModifier {
    @Binding var isPickingFile: Bool
    let handleFilePick: (Result<[URL], Error>) -> Void

    func body(content: Content) -> some View {
        content.fileImporter(
            isPresented: $isPickingFile,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handleFilePick(result)
        }
    }
}

private struct ComposeAIConsentAlert: ViewModifier {
    @Binding var showAIConsent: Bool
    @Binding var aiEnabled: Bool
    @Binding var aiConsentGiven: Bool

    func body(content: Content) -> some View {
        content.alert(String(localized: "Enable AI Writer?", bundle: .module), isPresented: $showAIConsent) {
            Button(String(localized: "Enable", bundle: .module)) {
                aiConsentGiven = true
                aiEnabled = true
            }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) {}
        } message: {
            Text(Self.message)
        }
    }

    private static let message = [
        AIWriterDisclosure.defaultProvider.consentMessage,
        "You can turn AI Writer off any time in Settings."
    ].joined(separator: " ")
}

private struct ComposeAIPromptDraftAlert: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var prompt: String
    let providerLabel: String
    let submit: (String) -> Void

    func body(content: Content) -> some View {
        content.alert(String(localized: "Draft with AI", bundle: .module), isPresented: $isPresented) {
            TextField(String(localized: "Prompt", bundle: .module), text: $prompt)
            Button(String(localized: "Draft", bundle: .module)) {
                let prompt = prompt
                self.prompt = ""
                submit(prompt)
            }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) {
                prompt = ""
            }
        } message: {
            Text(providerLabel)
        }
    }
}

// MARK: - Pending attachment model

struct PendingAttachment: Identifiable, Sendable {
    let id: UUID
    let filename: String
    let mimeType: String
    let data: Data
    let uploadErrorMessage: String?
    let uploadedAttachmentID: String?

    init(
        id: UUID = UUID(),
        filename: String,
        mimeType: String,
        data: Data,
        uploadErrorMessage: String? = nil,
        uploadedAttachmentID: String? = nil
    ) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
        self.uploadErrorMessage = uploadErrorMessage
        self.uploadedAttachmentID = uploadedAttachmentID
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }
}
