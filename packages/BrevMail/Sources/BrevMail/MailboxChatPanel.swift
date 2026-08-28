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
import BrevThemes
import SwiftUI

struct MailboxChatAvailabilityState: Equatable, Sendable {
    let settings: AIWriterSettings
    let hasProviderBackend: Bool
}

enum MailboxChatDisabledReason: Equatable, Sendable {
    case missingBackend
    case notEnabled
    case consentRequired

    var title: String {
        switch self {
        case .missingBackend:
            "Mailbox chat needs an AI provider for this account."
        case .notEnabled:
            "AI Writer is turned off."
        case .consentRequired:
            "AI Writer needs consent before sending message text."
        }
    }
}

enum MailboxChatAvailability {
    static func disabledReason(
        in state: MailboxChatAvailabilityState
    ) -> MailboxChatDisabledReason? {
        if !state.hasProviderBackend { return .missingBackend }
        if !state.settings.isEnabled { return .notEnabled }
        if !state.settings.consentGiven { return .consentRequired }
        return nil
    }
}

enum MailboxChatEmptyTranscriptPolicy {
    /// What the empty transcript says under its title.
    ///
    /// The title already invites the question ("Ask about this sender"), so
    /// this line carries what the title cannot: which mail the answers can draw
    /// on. Restating the invitation, as it did, put one sentence on screen
    /// twice — and the disabled reason, which it said before that, belongs in
    /// the composer callout beside the control it disables.
    static let message = "Answers use only the messages cached on this Mac."
}

enum MailboxChatSendOutcome: Equatable, Sendable {
    case send
    case showConsent
    case ignore
}

/// What the composer's blocked-state notice says and what its button does.
///
/// Every blocked state carries an action. The missing-provider case — the one a
/// new install lands in — used to state the problem and stop, because the only
/// button was gated behind `reason != .missingBackend`.
struct MailboxChatNotice: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case openSettings
        case showConsent
    }

    let reason: MailboxChatDisabledReason

    var message: String { reason.title }

    /// A missing provider is something the user has to go and fix; the other two
    /// are a switch they can throw from here.
    var tone: SettingsCalloutTone {
        reason == .missingBackend ? .warning : .info
    }

    var action: Action {
        reason == .missingBackend ? .openSettings : .showConsent
    }

    var actionTitle: String {
        switch action {
        case .openSettings: "Set Up Provider…"
        case .showConsent: "Enable AI Writer…"
        }
    }

    var symbolName: String {
        reason == .missingBackend ? "exclamationmark.triangle" : "lock.shield"
    }
}

enum MailboxChatComposerPolicy {
    static func isComposerInteractive(
        isSending: Bool,
        disabledReason: MailboxChatDisabledReason?
    ) -> Bool {
        !isSending && disabledReason == nil
    }

    static func sendOutcome(
        disabledReason: MailboxChatDisabledReason?
    ) -> MailboxChatSendOutcome {
        switch disabledReason {
        case nil:
            return .send
        case .missingBackend:
            return .ignore
        case .notEnabled, .consentRequired:
            return .showConsent
        }
    }

    /// How many lines of the ask field are visible.
    ///
    /// One line read as a search box in a column this narrow, and a question
    /// about a mailbox is usually a sentence. It still grows with the draft.
    static let visibleLineLimit = 2 ... 6

    /// Send is an arrow rather than the word, the way every chat composer on the
    /// platform draws it. Bare, not a `.circle` variant — the button draws the
    /// circle, and nesting one inside the other is the same mistake the mailbox
    /// filter glyph made.
    static let sendSymbolName = "arrow.up"

    /// A blocked field says so rather than inviting a question it will not take.
    /// The notice above it carries the reason, so this only has to stop the
    /// placeholder from reading as an available control.
    static func placeholder(
        subject: String,
        disabledReason: MailboxChatDisabledReason?
    ) -> String {
        disabledReason == nil ? "Ask about \(subject)…" : "Unavailable"
    }
}

struct MailboxChatPanel: View {
    @Environment(\.brevTheme) private var theme

    @AppStorage(AIWriterSettings.Key.isEnabled) private var aiEnabled = false
    @AppStorage(AIWriterSettings.Key.consentGiven) private var aiConsentGiven = false

    let scope: MailboxChatScope
    let sourceID: MailSourceID?
    let aiBackend: (any AIBackend)?
    let actionFolders: [Folder]
    let focusedFolder: Folder?
    let actionSourceScope: MailboxActionAgentSourceScope
    let actionProviderLabel: String
    let executeAction: MailboxChatActionExecute?
    let search: MailboxChatSearch
    let onOpenCitation: (MailboxChatCitation) -> Void
    /// Absent when the host has no Settings surface to open; the notice's button
    /// disables itself rather than pretending it leads somewhere.
    let onOpenSettings: (() -> Void)?

    @State private var draft = ""
    @State private var showAIConsent = false
    @State private var actionConfirmations: [UUID: String] = [:]
    @State private var selectedChipKind: MailboxChatScopeChipKind
    @StateObject private var controller: MailboxChatController

    init(
        scope: MailboxChatScope,
        sourceID: MailSourceID? = nil,
        aiBackend: (any AIBackend)?,
        actionFolders: [Folder] = [],
        focusedFolder: Folder? = nil,
        actionSourceScope: MailboxActionAgentSourceScope = .currentMailbox,
        actionProviderLabel: String = MailboxChatController.localActionProviderLabel,
        executeAction: MailboxChatActionExecute? = nil,
        search: @escaping MailboxChatSearch = { _, _ in [] },
        initialTurns: [MailboxChatTurnKind] = [],
        onOpenCitation: @escaping (MailboxChatCitation) -> Void = { _ in },
        onOpenSettings: (() -> Void)? = nil
    ) {
        let context = MailboxMailContextScopeWiring.chatScopeContext(
            mailboxChatScope: scope,
            sourceID: sourceID,
            focusedFolder: focusedFolder,
            actionSourceScope: actionSourceScope
        )
        let initialChipKind = context.defaultChipKind
        let initialScope = context.scope(for: initialChipKind) ?? scope

        self.scope = scope
        self.sourceID = sourceID
        self.aiBackend = aiBackend
        self.actionFolders = actionFolders
        self.focusedFolder = focusedFolder
        self.actionSourceScope = actionSourceScope
        self.actionProviderLabel = actionProviderLabel
        self.executeAction = executeAction
        self.search = search
        self.onOpenCitation = onOpenCitation
        self.onOpenSettings = onOpenSettings
        _selectedChipKind = State(initialValue: initialChipKind)
        _controller = StateObject(wrappedValue: MailboxChatController(
            scope: initialScope,
            sourceID: sourceID,
            aiBackend: aiBackend,
            actionFolders: actionFolders,
            focusedFolder: focusedFolder,
            actionSourceScope: actionSourceScope,
            actionProviderLabel: actionProviderLabel,
            executeAction: executeAction,
            turns: initialTurns,
            search: search
        ))
    }

    var body: some View {
        let controllerSearch: MailboxChatSearch = { @Sendable [search] query, sourceID in
            try await search(query, sourceID)
        }
        let controllerExecuteAction: MailboxChatActionExecute? = executeAction.map { executeAction in
            { @Sendable [executeAction] plan in
                try await executeAction(plan)
            }
        }

        VStack(alignment: .leading, spacing: 0) {
            // No rule under the header. It belongs to the transcript below it,
            // and a rule between them made the panel's own top boundary — the
            // draggable split — compete with an internal one a few points away.
            header
                .padding(.horizontal, BrevSpacing.lg)
                .padding(.top, BrevSpacing.lg)
                .padding(.bottom, BrevSpacing.md)

            transcriptSection
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, BrevSpacing.lg)
                .padding(.vertical, BrevSpacing.md)

            MailContextDivider()

            composerSection
                .padding(BrevSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(MailboxChatAIConsentAlert(
            showAIConsent: $showAIConsent,
            aiEnabled: $aiEnabled,
            aiConsentGiven: $aiConsentGiven
        ))
        .task(id: controllerConfigurationID) {
            guard let effectiveScope else { return }
            controller.configure(
                scope: effectiveScope,
                sourceID: sourceID,
                aiBackend: aiBackend,
                actionFolders: actionFolders,
                focusedFolder: focusedFolder,
                actionSourceScope: actionSourceScope,
                actionProviderLabel: actionProviderLabel,
                executeAction: controllerExecuteAction,
                search: controllerSearch
            )
        }
        .onChange(of: scopeContextIdentity) { _, _ in
            selectedChipKind = scopeContext.defaultChipKind
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            MailContextSectionHeader(
                title: "Mailbox chat",
                trailing: aiBackend?.transparencyLabel
            )

            HStack(spacing: BrevSpacing.sm) {
                Text("Search scope", bundle: .module)
                Spacer(minLength: 0)
                if let accountLabel = scopeContext.accountLabel {
                    Text(accountLabel)
                        .lineLimit(1)
                }
            }
            .brevFont(.caption)
            .foregroundStyle(theme.textSecondary.color)

            scopeChipRow
        }
    }

    private var scopeChipRow: some View {
        HStack(spacing: BrevSpacing.xs) {
            ForEach(MailboxChatScopeChipPolicy.chips(
                context: scopeContext,
                selected: selectedChipKind
            )) { chip in
                if chip.isEnabled {
                    Button {
                        selectedChipKind = chip.kind
                    } label: {
                        scopeChip(chip)
                    }
                    .buttonStyle(.plain)
                } else {
                    scopeChip(chip)
                }
            }
        }
    }

    private func scopeChip(_ chip: MailboxChatScopeChip) -> some View {
        Text(chip.title)
            .brevFont(.caption)
            .foregroundStyle(
                chip.isSelected
                    ? theme.accent.color
                    : (chip.isEnabled ? theme.textPrimary.color : theme.textTertiary.color)
            )
            .lineLimit(1)
            .padding(.horizontal, BrevSpacing.sm)
            .padding(.vertical, BrevSpacing.xs)
            .background(
                Capsule()
                    .fill(
                        chip.isSelected
                            ? theme.accent.color.opacity(0.12)
                            : (chip.isEnabled ? theme.bgSecondary.color : theme.bgPrimary.color)
                    )
            )
            .overlay {
                Capsule()
                    .stroke(
                        chip.isSelected
                            ? theme.accent.color.opacity(0.4)
                            : (chip.isEnabled ? theme.border.color : theme.border.color.opacity(0.6)),
                        lineWidth: 0.5
                    )
            }
            .accessibilityAddTraits(chip.isSelected ? .isSelected : [])
            .accessibilityLabel(chip.accessibilityLabel)
    }

    @ViewBuilder
    private var transcriptSection: some View {
        if controller.turns.isEmpty {
            ContentUnavailableView {
                Label(emptyTranscriptTitle, systemImage: "bubble.left.and.text.bubble.right")
                    .foregroundStyle(theme.textPrimary.color)
            } description: {
                Text(emptyTranscriptMessage)
                    .foregroundStyle(theme.textSecondary.color)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                    ForEach(Array(controller.turns.enumerated()), id: \.offset) { index, turn in
                        transcriptBubble(for: turn)
                            .id(index)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var composerSection: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            if let reason = disabledReason {
                composerNotice(MailboxChatNotice(reason: reason))
            }

            VStack(alignment: .trailing, spacing: BrevSpacing.xs) {
                askField

                if controller.isSending {
                    Button(String(localized: "Cancel", bundle: .module)) {
                        controller.cancel()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button {
                        Task {
                            await send()
                        }
                    } label: {
                        Image(systemName: MailboxChatComposerPolicy.sendSymbolName)
                            .fontWeight(.semibold)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.borderedProminent)
                    .clipShape(Circle())
                    .tint(theme.accent.color)
                    .disabled(isSendDisabled)
                    .accessibilityLabel(String(localized: "Send", bundle: .module))
                    .help(String(localized: "Send", bundle: .module))
                }
            }
        }
    }

    /// The ask field.
    ///
    /// Drawn rather than `.roundedBorder`, whose disabled state is almost
    /// indistinguishable from its enabled one — the field looked ready to take a
    /// question it would silently refuse. Send moved below it instead of beside
    /// it so the field gets the column's full width.
    private var askField: some View {
        TextField(
            MailboxChatComposerPolicy.placeholder(
                subject: scopePromptSubject,
                disabledReason: disabledReason
            ),
            text: $draft,
            axis: .vertical
        )
        .textFieldStyle(.plain)
        .brevFont(.body)
        .foregroundStyle(isComposerDisabled ? theme.textTertiary.color : theme.textPrimary.color)
        .lineLimit(MailboxChatComposerPolicy.visibleLineLimit)
        .padding(.horizontal, BrevSpacing.sm)
        .padding(.vertical, BrevSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BrevRadius.sm, style: .continuous)
                .fill(theme.bgPrimary.color.opacity(isComposerDisabled ? 0.35 : 0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: BrevRadius.sm, style: .continuous)
                .stroke(
                    BrevSeparator.color(
                        for: theme,
                        opacity: isComposerDisabled
                            ? BrevSeparator.interiorOpacity
                            : BrevSeparator.edgeOpacity
                    ),
                    lineWidth: 1
                )
        )
        .disabled(isComposerDisabled)
    }

    /// Why the composer is blocked, and the one control that unblocks it.
    ///
    /// A tinted hairline against the pane instead of the filled `bgTertiary` box
    /// `SettingsInfoCallout` draws: in a column this narrow that box was the
    /// heaviest thing on screen, and on a theme whose tertiary surface is blue it
    /// read as a blue panel rather than as a warning. The tone now comes from the
    /// theme's own warning colour, so a warning looks like one.
    private func composerNotice(_ notice: MailboxChatNotice) -> some View {
        let tint = notice.tone.color(in: theme)

        return VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: BrevSpacing.xs) {
                Image(systemName: notice.symbolName)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)

                Text(notice.message)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(notice.actionTitle) {
                switch notice.action {
                case .openSettings:
                    onOpenSettings?()
                case .showConsent:
                    showAIConsent = true
                }
            }
            // Not `.buttonStyle(.link)`: that renders as an `AXLink` whose
            // `AXPress` fails, so the one control that unblocks the panel was
            // unreachable to assistive technology, and it ignored `.tint` besides.
            .buttonStyle(.borderless)
            .brevFont(.caption)
            .foregroundStyle(tint)
            .disabled(notice.action == .openSettings && onOpenSettings == nil)
        }
        .padding(BrevSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BrevRadius.sm, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: BrevRadius.sm, style: .continuous)
                .stroke(tint.opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func transcriptBubble(for turn: MailboxChatTurnKind) -> some View {
        switch turn {
        case .user(let text):
            transcriptBubble(
                text: text,
                title: "You",
                fill: theme.accent.color.opacity(0.12),
                border: theme.accent.color.opacity(0.3)
            )
        case .answer(let text, let citations, let providerLabel):
            transcriptBubble(
                text: text,
                title: providerLabel,
                citations: citations,
                fill: theme.bgSecondary.color,
                border: theme.border.color
            )
        case .actionReview(_, let providerLabel):
            actionReviewBubble(for: turn, providerLabel: providerLabel)
        case .clarification(let text, let providerLabel):
            transcriptBubble(
                text: text,
                title: providerLabel,
                fill: theme.bgSecondary.color,
                border: theme.border.color
            )
        case .error(let text, let providerLabel):
            transcriptBubble(
                text: text,
                title: providerLabel,
                fill: theme.bgSecondary.color,
                border: theme.border.color
            )
        }
    }

    private func transcriptBubble(
        text: String,
        title: String,
        citations: [MailboxChatCitation] = [],
        fill: Color,
        border: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            Text(title)
                .brevFont(.caption)
                .foregroundStyle(theme.textTertiary.color)

            Text(text)
                .brevFont(.body)
                .foregroundStyle(theme.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)

            if !citations.isEmpty {
                VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                    ForEach(citations) { citation in
                        Button {
                            onOpenCitation(citation)
                        } label: {
                            HStack(alignment: .top, spacing: BrevSpacing.md) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(citation.subject)
                                        .brevFont(.subheadline)
                                        .foregroundStyle(theme.textPrimary.color)
                                        .lineLimit(2)
                                    Text(citation.date.formatted(date: .abbreviated, time: .omitted))
                                        .brevFont(.caption)
                                        .foregroundStyle(theme.textSecondary.color)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.right.square")
                                    .brevFont(.caption)
                                    .foregroundStyle(theme.textTertiary.color)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, BrevSpacing.xs)
            }
        }
        .padding(BrevSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill)
        .overlay {
            RoundedRectangle(cornerRadius: BrevRadius.md)
                .stroke(border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: BrevRadius.md))
    }

    @ViewBuilder
    private func actionReviewBubble(
        for turn: MailboxChatTurnKind,
        providerLabel: String
    ) -> some View {
        if case .actionReview(let plan, _) = turn {
            let presentation = MailboxActionAgentReviewPresentation.review(for: plan)
            let isConfirmingCurrentPlan = controller.confirmingPlanID == plan.id
            let confirmationBinding = Binding(
                get: { actionConfirmations[plan.id, default: ""] },
                set: { actionConfirmations[plan.id] = $0 }
            )

            VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                Text(providerLabel)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textTertiary.color)

                Text(presentation.title)
                    .brevFont(.headline)
                    .foregroundStyle(theme.textPrimary.color)

                Text(presentation.message)
                    .brevFont(.body)
                    .foregroundStyle(theme.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)

                if !presentation.detailRows.isEmpty {
                    actionReviewDetails(rows: presentation.detailRows)
                }

                if !presentation.sampleRows.isEmpty {
                    actionReviewSamples(rows: presentation.sampleRows)
                }

                if let warningMessage = presentation.warningMessage {
                    BrevInlineStatus(
                        message: warningMessage,
                        tone: .danger,
                        lineLimit: nil
                    )
                }

                if let requiredPhrase = presentation.requiredPhrase {
                    Text("Type \(requiredPhrase) to confirm.", bundle: .module)
                        .brevFont(.caption)
                        .foregroundStyle(theme.textSecondary.color)
                    TextField(String(localized: "Confirmation", bundle: .module), text: confirmationBinding)
                        .textFieldStyle(.roundedBorder)
                        .disabled(controller.isSending || isConfirmingCurrentPlan)
                }

                HStack {
                    Button(presentation.cancelButtonTitle) {
                        actionConfirmations[plan.id] = ""
                    }
                    .disabled(controller.isSending || isConfirmingCurrentPlan)

                    Spacer()

                    if let confirmButtonTitle = presentation.confirmButtonTitle {
                        Button(confirmButtonTitle, role: presentation.isDestructive ? .destructive : nil) {
                            let phrase = confirmationBinding.wrappedValue
                            actionConfirmations[plan.id] = ""
                            Task {
                                await controller.confirmAction(planID: plan.id, phrase: phrase)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(presentation.isDestructive ? theme.danger.color : theme.accent.color)
                        .disabled(
                            isConfirmingCurrentPlan
                                || !MailboxActionAgentReviewInputPolicy.canConfirm(
                                    confirmationBinding.wrappedValue,
                                    presentation: presentation
                                )
                        )
                    }
                }
            }
            .padding(BrevSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.bgSecondary.color)
            .overlay {
                RoundedRectangle(cornerRadius: BrevRadius.md)
                    .stroke(theme.border.color, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: BrevRadius.md))
        }
    }

    private func actionReviewDetails(
        rows: [MailboxActionAgentReviewDetailRow]
    ) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            Text("Review details", bundle: .module)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
            VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .brevFont(.caption)
                            .foregroundStyle(theme.textTertiary.color)
                        Text(row.value)
                            .brevFont(.subheadline)
                            .foregroundStyle(theme.textPrimary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func actionReviewSamples(
        rows: [MailboxActionAgentReviewSampleRow]
    ) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            Text("Matched messages", bundle: .module)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
            VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: BrevSpacing.xs) {
                        Image(systemName: "envelope")
                            .foregroundStyle(theme.textTertiary.color)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                                .brevFont(.subheadline)
                                .foregroundStyle(theme.textPrimary.color)
                                .lineLimit(1)
                            Text(row.subtitle)
                                .brevFont(.caption)
                                .foregroundStyle(theme.textSecondary.color)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private var availabilityState: MailboxChatAvailabilityState {
        MailboxChatAvailabilityState(
            settings: AIWriterSettings(isEnabled: aiEnabled, consentGiven: aiConsentGiven),
            hasProviderBackend: aiBackend != nil
        )
    }

    private var disabledReason: MailboxChatDisabledReason? {
        MailboxChatAvailability.disabledReason(in: availabilityState)
    }

    private var isComposerDisabled: Bool {
        !MailboxChatComposerPolicy.isComposerInteractive(
            isSending: controller.isSending,
            disabledReason: disabledReason
        )
    }

    private var isSendDisabled: Bool {
        isComposerDisabled || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var controllerConfigurationID: String {
        Self.controllerConfigurationID(
            selectedChipKind: selectedChipKind,
            scopeTitle: effectiveScopeTitle,
            sourceID: sourceID,
            aiBackendIdentifier: aiBackend?.identifier,
            actionFolders: actionFolders,
            focusedFolder: focusedFolder,
            actionSourceScope: actionSourceScope
        )
    }

    private var scopeContext: MailboxChatScopeContext {
        MailboxMailContextScopeWiring.chatScopeContext(
            mailboxChatScope: scope,
            sourceID: sourceID,
            focusedFolder: focusedFolder,
            actionSourceScope: actionSourceScope
        )
    }

    private var scopeContextIdentity: String {
        [
            Self.senderEmail(from: scope) ?? "no-sender",
            focusedFolder.map { "\($0.id):\($0.name)" } ?? "no-folder",
            actionSourceScope.accountName ?? "no-account",
            sourceID?.accountID ?? "no-account",
            sourceID?.mailboxID ?? "no-mailbox",
        ]
        .joined(separator: "|")
    }

    private var effectiveScope: MailboxChatScope? {
        scopeContext.scope(for: selectedChipKind)
    }

    private var effectiveScopeTitle: String {
        guard let effectiveScope else { return scopeTitle }
        switch effectiveScope {
        case .sender(let email):
            return email
        case .folder:
            return focusedFolder?.name ?? "Current folder"
        case .account:
            return actionSourceScope.accountName ?? "Current account"
        }
    }

    private var emptyTranscriptTitle: String {
        switch effectiveScope ?? scope {
        case .sender:
            "Ask about this sender"
        case .folder:
            "Ask about this folder"
        case .account:
            "Ask across all folders"
        }
    }

    private var emptyTranscriptMessage: String {
        MailboxChatEmptyTranscriptPolicy.message
    }

    private var scopeTitle: String {
        switch scope {
        case .sender(let email):
            return email
        case .folder:
            return "Current folder"
        case .account:
            return "All folders"
        }
    }

    private var scopePromptSubject: String {
        switch effectiveScope ?? scope {
        case .sender:
            return "this sender"
        case .folder:
            return "this folder"
        case .account:
            return "all folders"
        }
    }

    private func send() async {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        switch MailboxChatComposerPolicy.sendOutcome(disabledReason: disabledReason) {
        case .send:
            break
        case .showConsent:
            showAIConsent = true
            return
        case .ignore:
            return
        }
        draft = ""
        await controller.send(userText: message)
    }

    static func controllerConfigurationID(
        selectedChipKind: MailboxChatScopeChipKind,
        scopeTitle: String,
        sourceID: MailSourceID?,
        aiBackendIdentifier: String?,
        actionFolders: [Folder],
        focusedFolder: Folder?,
        actionSourceScope: MailboxActionAgentSourceScope
    ) -> String {
        return [
            selectedChipKind.rawValue,
            scopeTitle,
            sourceID?.accountID ?? "no-account",
            sourceID?.mailboxID ?? "no-mailbox",
            aiBackendIdentifier ?? "no-ai",
            actionFolders
                .map { "\($0.id):\($0.name):\(String(describing: $0.role))" }
                .joined(separator: ","),
            focusedFolder.map { "\($0.id):\($0.name):\(String(describing: $0.role))" } ?? "no-focused-folder",
            sourceScopeIdentity(actionSourceScope)
        ]
        .joined(separator: "|")
    }

    private static func sourceScopeIdentity(_ scope: MailboxActionAgentSourceScope) -> String {
        [
            scope.sourceID?.accountID ?? "no-scope-account",
            scope.sourceID?.mailboxID ?? "no-scope-mailbox",
            scope.accountName ?? "no-account-name",
            scope.mailboxName ?? "no-mailbox-name",
            scope.mailboxAddress ?? "no-mailbox-address"
        ]
        .joined(separator: ":")
    }

    private static func senderEmail(from scope: MailboxChatScope) -> String? {
        if case .sender(let email) = scope {
            return email
        }
        return nil
    }
}

private struct MailboxChatAIConsentAlert: ViewModifier {
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
        "Mailbox chat uses the same AI Writer consent and can be turned off any time in Settings."
    ].joined(separator: " ")
}
