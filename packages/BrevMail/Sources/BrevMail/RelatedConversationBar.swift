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
import SwiftUI

/// What the macOS reader bar shows for related-conversation lookup
/// (ADR-0074 §8). It stays quiet until there is something to say or do: the
/// plain cached and complete states have no sentence, Load related mail is the
/// only idle action, and Spam and Trash is offered only after a lookup has
/// produced a result.
struct RelatedConversationBarPresentation: Equatable {
    /// Non-ideal lookup states worth a sentence.
    enum Status: Equatable {
        case loading
        case failed
        case partial
    }

    /// Actions in display order.
    enum Action: Hashable {
        case retry
        case loadRelatedMail
        case includeSpamAndTrash
    }

    let status: Status?
    let actions: [Action]

    /// True when the bar has nothing to show and should not render at all.
    var isEmpty: Bool { status == nil && actions.isEmpty }

    init(
        canLoadRelated: Bool,
        isLoadingRemote: Bool,
        remoteLoadDidFail: Bool,
        remoteLoadAttempted: Bool,
        coverage: ConversationCoverage?,
        hasExcludedFolders: Bool,
        includesSpamAndTrash: Bool
    ) {
        if isLoadingRemote || coverage == .loading {
            status = .loading
            actions = []
            return
        }
        let isPartial = coverage == .partial
        status = remoteLoadDidFail ? .failed : (isPartial ? .partial : nil)
        var items: [Action] = []
        if remoteLoadDidFail || isPartial {
            items.append(.retry)
        }
        if canLoadRelated, !remoteLoadAttempted || remoteLoadDidFail {
            items.append(.loadRelatedMail)
        }
        let hasLookupResult = remoteLoadAttempted || isPartial || coverage == .completeForScope
        if hasExcludedFolders, !includesSpamAndTrash, hasLookupResult {
            items.append(.includeSpamAndTrash)
        }
        actions = items
    }

    @MainActor
    init(controller: RelatedConversationController) {
        self.init(
            canLoadRelated: controller.canLoadRelated,
            isLoadingRemote: controller.isLoadingRemote,
            remoteLoadDidFail: controller.remoteLoadDidFail,
            remoteLoadAttempted: controller.remoteLoadAttempted,
            coverage: controller.snapshot?.coverage,
            hasExcludedFolders: !(controller.snapshot?.excludedFolderIDs.isEmpty ?? true),
            includesSpamAndTrash: controller.includesSpamAndTrash
        )
    }
}

/// Compact conversation-coverage feedback for the reader (ADR-0074 §8).
///
/// Shows the explicit **Load related mail** action while only the cached
/// snapshot is available, progress while remote discovery runs, and honest
/// failed/partial results with Retry and Spam/Trash inclusion.
struct RelatedConversationBar: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let controller: RelatedConversationController

    private var presentation: RelatedConversationBarPresentation {
        RelatedConversationBarPresentation(controller: controller)
    }

    var body: some View {
        let presentation = presentation
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                    if let status = presentation.status {
                        statusRow(status)
                    }
                    actions(presentation)
                }
            } else {
                HStack(spacing: BrevSpacing.sm) {
                    if let status = presentation.status {
                        statusRow(status)
                    }
                    Spacer(minLength: BrevSpacing.sm)
                    actions(presentation)
                }
            }
        }
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        #if os(iOS)
            .background(theme.bgSecondary.color)
        #endif
            .accessibilityElement(children: .combine)
    }

    private func statusRow(_ status: RelatedConversationBarPresentation.Status) -> some View {
        let appearance = appearance(for: status)
        return HStack(spacing: BrevSpacing.sm) {
            Image(systemName: appearance.symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(appearance.tint)
            Text(appearance.message)
                .brevFont(.footnote)
                .foregroundStyle(theme.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One dispatch over the status keeps the symbol, tint and copy
    /// consistent — a state can never show another state's icon.
    private func appearance(
        for status: RelatedConversationBarPresentation.Status
    ) -> (symbol: String, tint: Color, message: String) {
        switch status {
        case .loading:
            ("arrow.triangle.2.circlepath", theme.textSecondary.color,
             String(localized: "Loading related mail across folders…", bundle: .module))
        case .failed:
            ("exclamationmark.triangle", theme.warning.color,
             String(localized: "Couldn't load related mail.", bundle: .module))
        case .partial:
            ("exclamationmark.circle", theme.warning.color,
             String(localized: "Partial — some folders couldn't be searched.", bundle: .module))
        }
    }

    @ViewBuilder
    private func actions(_ presentation: RelatedConversationBarPresentation) -> some View {
        if presentation.status == .loading {
            ProgressView()
                .controlSize(.small)
        } else {
            ForEach(presentation.actions, id: \.self) { action in
                switch action {
                case .retry:
                    BrevButton(String(localized: "Retry", bundle: .module), style: .tertiary) {
                        controller.retry()
                    }
                case .loadRelatedMail:
                    BrevButton(
                        String(localized: "Load related mail", bundle: .module),
                        style: .secondary
                    ) {
                        controller.loadRelatedMail()
                    }
                    .accessibilityHint(String(
                        localized: "Searches every eligible folder in this account, including folders that are not synced, for related message headers.",
                        bundle: .module
                    ))
                case .includeSpamAndTrash:
                    BrevButton(
                        String(localized: "Include Spam and Trash", bundle: .module),
                        style: .tertiary
                    ) {
                        controller.includeSpamAndTrash()
                    }
                }
            }
        }
    }
}
