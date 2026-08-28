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

import BrevDesign
import BrevThemes
import SwiftUI

struct MailboxActionAgentSheet: View {
    typealias Resolve = (String) async throws -> MailboxActionAgentPlanningResult
    typealias Execute = (MailboxActionAgentPlan, String) async throws -> String

    @Environment(\.brevTheme) private var theme
    @State private var requestText = ""
    @State private var confirmationText = ""
    @State private var phase: Phase = .editing

    let resolve: Resolve
    let execute: Execute
    let onClose: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            BrevDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: BrevSpacing.md) {
                    requestEditor
                    phaseContent
                }
                .padding(BrevSpacing.md)
            }
        }
        .frame(minWidth: 360, idealWidth: 460, minHeight: 360, idealHeight: 480)
        .background(theme.bgPrimary.color)
    }

    private var header: some View {
        HStack(spacing: BrevSpacing.sm) {
            Image(systemName: "wand.and.sparkles")
                .foregroundStyle(theme.accent.color)
            Text("Mailbox Assistant", bundle: .module)
                .brevFont(.headline)
                .foregroundStyle(theme.textPrimary.color)
            Spacer()
            Button {
                onClose?()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(theme.textTertiary.color)
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.sm)
    }

    private var requestEditor: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            Text("Request", bundle: .module)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
            TextField(
                String(localized: "Ask for a sender-scoped mailbox action", bundle: .module),
                text: $requestText,
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(2 ... 4)
            .disabled(isBusy)
            HStack {
                Spacer()
                Button(String(localized: "Review", bundle: .module)) {
                    Task { await reviewRequest() }
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent.color)
                .disabled(!canReview)
            }
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch phase {
        case .editing:
            EmptyView()
        case .resolving:
            statusRow(symbol: "magnifyingglass", message: "Checking cached mail...")
        case .clarification(let message):
            statusRow(symbol: "questionmark.circle", message: message)
        case .review(let plan):
            reviewContent(for: plan)
        case .executing:
            statusRow(symbol: "clock", message: "Applying mailbox action...")
        case .completed(let message):
            statusRow(symbol: "checkmark.circle", message: message)
        case .failed(let message):
            statusRow(symbol: "exclamationmark.triangle", message: message)
        }
    }

    private func reviewContent(for plan: MailboxActionAgentPlan) -> some View {
        let presentation = MailboxActionAgentReviewPresentation.review(for: plan)
        return VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            Text(presentation.title)
                .brevFont(.headline)
                .foregroundStyle(theme.textPrimary.color)
            Text(presentation.message)
                .brevFont(.body)
                .foregroundStyle(theme.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
            if !presentation.detailRows.isEmpty {
                detailPreview(rows: presentation.detailRows)
            }
            if !presentation.sampleRows.isEmpty {
                samplePreview(rows: presentation.sampleRows)
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
                TextField(String(localized: "Confirmation", bundle: .module), text: $confirmationText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isBusy)
            }
            HStack {
                Button(presentation.cancelButtonTitle) {
                    phase = .editing
                    confirmationText = ""
                }
                .disabled(isBusy)
                Spacer()
                if let confirmButtonTitle = presentation.confirmButtonTitle {
                    Button(confirmButtonTitle, role: presentation.isDestructive ? .destructive : nil) {
                        Task { await executePlan(plan) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(presentation.isDestructive ? theme.danger.color : theme.accent.color)
                    .disabled(!MailboxActionAgentReviewInputPolicy.canConfirm(
                        confirmationText,
                        presentation: presentation
                    ))
                }
            }
        }
    }

    private func detailPreview(rows: [MailboxActionAgentReviewDetailRow]) -> some View {
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

    private func samplePreview(rows: [MailboxActionAgentReviewSampleRow]) -> some View {
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

    private func statusRow(symbol: String, message: String) -> some View {
        HStack(alignment: .top, spacing: BrevSpacing.xs) {
            Image(systemName: symbol)
                .foregroundStyle(theme.textSecondary.color)
                .frame(width: 18)
            Text(message)
                .brevFont(.subheadline)
                .foregroundStyle(theme.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var canReview: Bool {
        !isBusy && !requestText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isBusy: Bool {
        switch phase {
        case .resolving, .executing:
            return true
        case .editing, .clarification, .review, .completed, .failed:
            return false
        }
    }

    private func reviewRequest() async {
        let request = requestText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }
        confirmationText = ""
        phase = .resolving
        do {
            switch try await resolve(request) {
            case .planned(let plan):
                phase = .review(plan)
            case .clarificationRequired(let clarification):
                phase = .clarification(
                    MailboxActionAgentClarificationPresentation.message(for: clarification)
                )
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func executePlan(_ plan: MailboxActionAgentPlan) async {
        let phrase = confirmationText.trimmingCharacters(in: .whitespacesAndNewlines)
        confirmationText = ""
        phase = .executing
        do {
            phase = try await .completed(execute(plan, phrase))
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

private enum Phase {
    case editing
    case resolving
    case clarification(String)
    case review(MailboxActionAgentPlan)
    case executing
    case completed(String)
    case failed(String)
}
