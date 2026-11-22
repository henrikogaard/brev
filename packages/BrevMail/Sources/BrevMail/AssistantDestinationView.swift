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

/// Deterministic gate applied by `AssistantDestinationView` before sending any prompt (#294).
enum AssistantPromptSubmissionGate {
    enum Outcome: Equatable {
        case ignore
        case requestConsent
        case openSettings
        case send(String)
    }

    static func evaluate(
        prompt: String,
        isSending: Bool,
        disabledReason: MailboxChatDisabledReason?
    ) -> Outcome {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return .ignore }
        if let disabledReason {
            switch disabledReason {
            case .notEnabled, .consentRequired:
                return .requestConsent
            case .missingBackend:
                return .openSettings
            }
        }
        return .send(trimmed)
    }
}

/// Full-pane Assistant sidebar destination (#294, ADR-0047 amendment): reuses
/// `MailboxChatController`, renders grounded conversation cards grouped by
/// priority, and keeps AI invocation strictly user-initiated with visible
/// provider destination labels (ADR-0051).
struct AssistantDestinationView: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 26

    @AppStorage(AIWriterSettings.Key.isEnabled) private var aiEnabled = false
    @AppStorage(AIWriterSettings.Key.consentGiven) private var aiConsentGiven = false

    let sourceID: MailSourceID?
    let aiBackend: (any AIBackend)?
    let actionFolders: [Folder]
    let focusedFolder: Folder?
    let actionSourceScope: MailboxActionAgentSourceScope
    let executeAction: MailboxChatActionExecute?
    let search: MailboxChatSearch
    let onOpenCard: (AssistantConversationCard) -> Void
    let onReplyCard: (AssistantConversationCard) -> Void
    let onOpenSettings: (() -> Void)?
    let availabilityOverride: MailboxChatAvailabilityState?

    @StateObject private var controller: MailboxChatController
    @State private var draftPrompt = ""
    @State private var confirmationPhrases: [UUID: String] = [:]
    @State private var showAIConsent = false

    private static let suggestedStarters: [String] = [
        String(localized: "What needs me today?", bundle: .module),
        String(localized: "Who hasn't replied?", bundle: .module),
    ]

    init(
        sourceID: MailSourceID?,
        aiBackend: (any AIBackend)?,
        actionFolders: [Folder] = [],
        focusedFolder: Folder? = nil,
        actionSourceScope: MailboxActionAgentSourceScope = .currentMailbox,
        executeAction: MailboxChatActionExecute? = nil,
        search: @escaping MailboxChatSearch,
        onOpenCard: @escaping (AssistantConversationCard) -> Void,
        onReplyCard: @escaping (AssistantConversationCard) -> Void,
        onOpenSettings: (() -> Void)? = nil,
        availabilityOverride: MailboxChatAvailabilityState? = nil,
        preloadedTurns: [MailboxChatTurnKind] = []
    ) {
        self.sourceID = sourceID
        self.aiBackend = aiBackend
        self.actionFolders = actionFolders
        self.focusedFolder = focusedFolder
        self.actionSourceScope = actionSourceScope
        self.executeAction = executeAction
        self.search = search
        self.onOpenCard = onOpenCard
        self.onReplyCard = onReplyCard
        self.onOpenSettings = onOpenSettings
        self.availabilityOverride = availabilityOverride
        _controller = StateObject(wrappedValue: MailboxChatController(
            scope: .account,
            sourceID: sourceID,
            aiBackend: aiBackend,
            actionFolders: actionFolders,
            focusedFolder: focusedFolder,
            actionSourceScope: actionSourceScope,
            executeAction: executeAction,
            turns: preloadedTurns,
            search: search
        ))
    }

    private var availabilityState: MailboxChatAvailabilityState {
        availabilityOverride ?? MailboxChatAvailabilityState(
            settings: AIWriterSettings(isEnabled: aiEnabled, consentGiven: aiConsentGiven),
            hasProviderBackend: aiBackend != nil
        )
    }

    private var disabledReason: MailboxChatDisabledReason? {
        MailboxChatAvailability.disabledReason(in: availabilityState)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            ScrollView {
                VStack(alignment: .leading, spacing: BrevSpacing.lg) {
                    if controller.turns.isEmpty {
                        welcomeState
                    } else {
                        ForEach(Array(controller.turns.enumerated()), id: \.offset) { _, turn in
                            turnView(turn)
                        }
                        if controller.isSending {
                            HStack(spacing: BrevSpacing.sm) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Searching local mail…", bundle: .module)
                                    .brevFont(.callout)
                                    .foregroundStyle(theme.textSecondary.color)
                            }
                            .padding(.vertical, BrevSpacing.xs)
                        }
                    }
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(.horizontal, BrevSpacing.xl)
                .padding(.vertical, BrevSpacing.xl)
                .frame(maxWidth: .infinity)
            }
            .scrollContentBackground(.hidden)
            promptBar
        }
        .background(theme.bgPrimary.color)
        .onChange(of: sourceID) { _, _ in
            reconfigureController()
        }
        .modifier(MailboxChatAIConsentAlert(
            showAIConsent: $showAIConsent,
            aiEnabled: $aiEnabled,
            aiConsentGiven: $aiConsentGiven
        ))
    }

    private func reconfigureController() {
        controller.configure(
            scope: .account,
            sourceID: sourceID,
            aiBackend: aiBackend,
            actionFolders: actionFolders,
            focusedFolder: focusedFolder,
            actionSourceScope: actionSourceScope,
            executeAction: executeAction,
            search: search
        )
    }

    private var headerBar: some View {
        HStack(spacing: BrevSpacing.sm) {
            Image(systemName: "sparkles")
                .foregroundStyle(theme.accent.color)
                .accessibilityHidden(true)
            Text("Assistant", bundle: .module)
                .brevFont(.headline)
                .foregroundStyle(theme.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let label = aiBackend?.transparencyLabel {
                Text(verbatim: label)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                    .padding(.horizontal, BrevSpacing.sm)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(theme.bgTertiary.color))
            }
        }
        .padding(.horizontal, BrevSpacing.lg)
        .padding(.vertical, BrevSpacing.sm)
        .background(theme.bgSecondary.color)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BrevSeparator.color(for: theme))
                .frame(height: 0.5)
        }
    }

    private var welcomeState: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.md) {
            Text("Assistant", bundle: .module)
                .brevFont(.largeTitle)
                .foregroundStyle(theme.textPrimary.color)
            Text(
                "Ask about your cached mail. Answers link to real conversations and never run until you press Send.",
                bundle: .module
            )
            .brevFont(.body)
            .foregroundStyle(theme.textSecondary.color)
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: BrevSpacing.sm) {
                ForEach(Self.suggestedStarters, id: \.self) { starter in
                    Button {
                        submit(starter)
                    } label: {
                        Text(verbatim: starter)
                            .brevFont(.callout)
                            .foregroundStyle(theme.textPrimary.color)
                            .padding(.horizontal, BrevSpacing.md)
                            .padding(.vertical, BrevSpacing.xs)
                            .background(Capsule().fill(theme.bgSecondary.color))
                            .overlay(
                                Capsule().strokeBorder(theme.border.color, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, BrevSpacing.xs)
        }
        .padding(.top, BrevSpacing.xl)
    }

    @ViewBuilder
    private func turnView(_ turn: MailboxChatTurnKind) -> some View {
        switch turn {
        case .user(let text):
            HStack {
                Spacer(minLength: BrevSpacing.xl)
                Text(verbatim: text)
                    .brevFont(.body)
                    .foregroundStyle(theme.textPrimary.color)
                    .padding(.horizontal, BrevSpacing.md)
                    .padding(.vertical, BrevSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: BrevRadius.lg)
                            .fill(theme.bgTertiary.color)
                    )
            }
        case .answer(let text, let citations, let providerLabel):
            answerTurnView(text: text, citations: citations, providerLabel: providerLabel)
        case .clarification(let text, let providerLabel):
            calloutTurn(text: text, providerLabel: providerLabel, tone: .info)
        case .error(let text, let providerLabel):
            calloutTurn(text: text, providerLabel: providerLabel, tone: .danger)
        case .actionReview(let plan, let providerLabel):
            actionReviewCard(plan: plan, providerLabel: providerLabel)
        }
    }

    private func answerTurnView(
        text: String,
        citations: [MailboxChatCitation],
        providerLabel: String
    ) -> some View {
        let presentation = AssistantAnswerCardsBuilder.build(citations: citations, locale: locale)
        return VStack(alignment: .leading, spacing: BrevSpacing.md) {
            Text(verbatim: text)
                .brevFont(.body)
                .foregroundStyle(theme.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)

            if !presentation.summaryChips.isEmpty {
                HStack(spacing: BrevSpacing.xs) {
                    ForEach(presentation.summaryChips, id: \.self) { chip in
                        Text(verbatim: chip)
                            .brevFont(.caption)
                            .foregroundStyle(theme.textSecondary.color)
                            .padding(.horizontal, BrevSpacing.sm)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(theme.bgSecondary.color))
                    }
                }
            }

            ForEach(presentation.sections) { section in
                VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                    Text(verbatim: section.kind.title)
                        .brevFont(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.textSecondary.color)
                    ForEach(section.cards) { card in
                        conversationCardView(card)
                    }
                }
            }

            if !presentation.actionChips.isEmpty {
                HStack(spacing: BrevSpacing.xs) {
                    ForEach(presentation.actionChips) { chip in
                        Button {
                            handleActionChip(chip)
                        } label: {
                            Text(verbatim: chip.title)
                                .brevFont(.caption)
                                .foregroundStyle(theme.textPrimary.color)
                                .padding(.horizontal, BrevSpacing.sm)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(theme.bgSecondary.color))
                                .overlay(
                                    Capsule().strokeBorder(theme.border.color, lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text(verbatim: providerLabel)
                .brevFont(.caption)
                .foregroundStyle(theme.textTertiary.color)
        }
    }

    private func conversationCardView(_ card: AssistantConversationCard) -> some View {
        Button {
            onOpenCard(card)
        } label: {
            HStack(spacing: BrevSpacing.sm) {
                Text(verbatim: InitialsAvatar.initials(displayName: card.senderName, email: card.senderEmail))
                    .brevFont(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.textSecondary.color)
                    .frame(width: avatarSize, height: avatarSize)
                    .background(Circle().fill(theme.bgTertiary.color))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: BrevSpacing.xs) {
                        Text(verbatim: card.senderName)
                            .brevFont(.callout)
                            .fontWeight(.semibold)
                            .foregroundStyle(theme.textPrimary.color)
                            .lineLimit(1)
                        ForEach(card.tags) { tag in
                            Text(verbatim: tag.title)
                                .brevFont(.caption)
                                .foregroundStyle(tag == .urgent ? theme.accent.color : theme.textSecondary.color)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(theme.bgTertiary.color))
                        }
                        Spacer(minLength: BrevSpacing.xs)
                        Text(verbatim: card.date.formatted(.dateTime.day().month(.abbreviated).locale(locale)))
                            .brevFont(.caption)
                            .foregroundStyle(theme.textTertiary.color)
                            .monospacedDigit()
                    }
                    Text(verbatim: card.subject)
                        .brevFont(.callout)
                        .foregroundStyle(theme.textPrimary.color)
                        .lineLimit(1)
                    if !card.snippet.isEmpty {
                        Text(verbatim: card.snippet)
                            .brevFont(.caption)
                            .foregroundStyle(theme.textSecondary.color)
                            .lineLimit(1)
                    }
                }
            }
            .padding(BrevSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: BrevRadius.md)
                    .fill(theme.bgSecondary.color)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BrevRadius.md)
                    .strokeBorder(theme.border.color, lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: BrevRadius.md))
        }
        .buttonStyle(.plain)
    }

    private func actionReviewCard(plan: MailboxActionAgentPlan, providerLabel: String) -> some View {
        let phraseBinding = Binding(
            get: { confirmationPhrases[plan.id] ?? "" },
            set: { confirmationPhrases[plan.id] = $0 }
        )
        return VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            Text(verbatim: plan.request)
                .brevFont(.callout)
                .foregroundStyle(theme.textPrimary.color)
            Text(verbatim: plan.confirmationChallenge.prompt)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
            HStack(spacing: BrevSpacing.sm) {
                TextField(plan.confirmationChallenge.requiredPhrase, text: phraseBinding)
                    .textFieldStyle(.roundedBorder)
                Button(String(localized: "Confirm", bundle: .module)) {
                    let typed = confirmationPhrases[plan.id] ?? ""
                    Task {
                        await controller.confirmAction(planID: plan.id, phrase: typed)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent.color)
                .disabled(
                    controller.confirmingPlanID == plan.id
                        || phraseBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        != plan.confirmationChallenge.requiredPhrase
                )
            }
            Text(verbatim: providerLabel)
                .brevFont(.caption)
                .foregroundStyle(theme.textTertiary.color)
        }
        .padding(BrevSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: BrevRadius.md)
                .fill(theme.bgSecondary.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BrevRadius.md)
                .strokeBorder(theme.border.color, lineWidth: 0.5)
        )
    }

    private func calloutTurn(text: String, providerLabel: String, tone: BrevInlineStatusTone) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            BrevInlineStatus(message: text, tone: tone)
            Text(verbatim: providerLabel)
                .brevFont(.caption)
                .foregroundStyle(theme.textTertiary.color)
        }
    }

    private var promptBar: some View {
        HStack(spacing: BrevSpacing.sm) {
            TextField(
                String(localized: "Ask anything about your mail…", bundle: .module),
                text: $draftPrompt
            )
            .textFieldStyle(.plain)
            .brevFont(.body)
            .onSubmit {
                submit(draftPrompt)
            }
            Button {
                submit(draftPrompt)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(theme.accent.color)
            }
            .buttonStyle(.plain)
            .disabled(draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || controller.isSending)
            .accessibilityLabel(String(localized: "Send", bundle: .module))
        }
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: BrevRadius.lg)
                .fill(theme.bgSecondary.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BrevRadius.lg)
                .strokeBorder(theme.border.color, lineWidth: 0.5)
        )
        .frame(maxWidth: 680)
        .padding(.horizontal, BrevSpacing.xl)
        .padding(.vertical, BrevSpacing.md)
        .frame(maxWidth: .infinity)
    }

    private func submit(_ prompt: String) {
        switch AssistantPromptSubmissionGate.evaluate(
            prompt: prompt,
            isSending: controller.isSending,
            disabledReason: disabledReason
        ) {
        case .ignore:
            return
        case .requestConsent:
            showAIConsent = true
        case .openSettings:
            onOpenSettings?()
        case .send(let trimmed):
            draftPrompt = ""
            Task {
                await controller.send(userText: trimmed)
            }
        }
    }

    private func handleActionChip(_ chip: AssistantAnswerActionChip) {
        switch chip {
        case .reply(_, let card):
            onReplyCard(card)
        case .followUpPrompt(let prompt):
            submit(prompt)
        case .archiveUpdates(_, let cards):
            guard !cards.isEmpty else { return }
            controller.stageArchiveCards(cards)
        }
    }
}
