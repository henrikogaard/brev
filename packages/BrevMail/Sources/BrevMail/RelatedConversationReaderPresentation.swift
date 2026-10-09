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

/// What the phone reader shows for related-conversation lookup (ADR-0074 §8):
/// the explicit actions live in the reader's overflow menu and only an honest
/// loading/failed/partial footnote surfaces in the content. The plain cached
/// and complete states show nothing. macOS keeps `RelatedConversationBar`.
struct RelatedConversationReaderPresentation: Equatable {
    /// Actions offered in the overflow menu, in display order.
    enum MenuItem: Hashable {
        case loadRelatedMail
        case retry
        case includeSpamAndTrash
    }

    /// Non-ideal lookup states worth a footnote.
    enum Status: Equatable {
        case loading
        case failed
        case partial
    }

    let menuItems: [MenuItem]
    let status: Status?

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
            menuItems = []
            status = .loading
            return
        }
        var items: [MenuItem] = []
        if canLoadRelated, !remoteLoadAttempted || remoteLoadDidFail {
            items.append(.loadRelatedMail)
        }
        let isPartial = coverage == .partial
        if remoteLoadDidFail || isPartial {
            items.append(.retry)
        }
        if hasExcludedFolders, !includesSpamAndTrash {
            items.append(.includeSpamAndTrash)
        }
        menuItems = items
        if remoteLoadDidFail {
            status = .failed
        } else if isPartial {
            status = .partial
        } else {
            status = nil
        }
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

// MARK: - Environment

private struct RelatedConversationControllerKey: EnvironmentKey {
    static let defaultValue: RelatedConversationController? = nil
}

extension EnvironmentValues {
    /// The reader's related-conversation owner. Set by the phone root so the
    /// reader's overflow menu and footnote can act on it; nil elsewhere.
    var relatedConversationController: RelatedConversationController? {
        get { self[RelatedConversationControllerKey.self] }
        set { self[RelatedConversationControllerKey.self] = newValue }
    }
}

// MARK: - Views

/// Overflow-menu section with the related-mail actions. Renders nothing (and
/// no trailing divider) when no action applies.
struct RelatedConversationReaderMenuSection: View {
    let controller: RelatedConversationController

    var body: some View {
        let presentation = RelatedConversationReaderPresentation(controller: controller)
        if !presentation.menuItems.isEmpty {
            ForEach(presentation.menuItems, id: \.self) { item in
                switch item {
                case .loadRelatedMail:
                    Button {
                        controller.loadRelatedMail()
                    } label: {
                        Label(
                            String(localized: "Load related mail", bundle: .module),
                            systemImage: "arrow.triangle.branch"
                        )
                    }
                    .accessibilityHint(String(
                        localized: "Searches every eligible folder in this account, including folders that are not synced, for related message headers.",
                        bundle: .module
                    ))
                case .retry:
                    Button {
                        controller.retry()
                    } label: {
                        Label(
                            String(localized: "Retry", bundle: .module),
                            systemImage: "arrow.clockwise"
                        )
                    }
                case .includeSpamAndTrash:
                    Button {
                        controller.includeSpamAndTrash()
                    } label: {
                        Label(
                            String(localized: "Include Spam and Trash", bundle: .module),
                            systemImage: "trash.slash"
                        )
                    }
                }
            }
            Divider()
        }
    }
}

/// One compact line of small text (no band) reporting a loading, failed or
/// partial related-mail lookup. Empty in every other state.
struct RelatedConversationFootnote: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.relatedConversationController) private var controller
    /// Insets applied only while a footnote is visible, so the empty state
    /// never reserves space.
    var horizontalPadding: CGFloat = 0
    var bottomPadding: CGFloat = 0

    var body: some View {
        if let controller,
           let status = RelatedConversationReaderPresentation(controller: controller).status {
            HStack(alignment: .firstTextBaseline, spacing: BrevSpacing.xs) {
                Image(systemName: symbol(for: status))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint(for: status))
                    .accessibilityHidden(true)
                Text(message(for: status))
                    .brevFont(.footnote)
                    .foregroundStyle(theme.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, bottomPadding)
            .accessibilityElement(children: .combine)
        }
    }

    private func symbol(for status: RelatedConversationReaderPresentation.Status) -> String {
        switch status {
        case .loading: "arrow.triangle.2.circlepath"
        case .failed: "exclamationmark.triangle"
        case .partial: "exclamationmark.circle"
        }
    }

    private func tint(for status: RelatedConversationReaderPresentation.Status) -> Color {
        switch status {
        case .loading: theme.textSecondary.color
        case .failed, .partial: theme.warning.color
        }
    }

    private func message(for status: RelatedConversationReaderPresentation.Status) -> String {
        switch status {
        case .loading:
            String(localized: "Loading related mail across folders…", bundle: .module)
        case .failed:
            String(localized: "Couldn't load related mail.", bundle: .module)
        case .partial:
            String(localized: "Partial — some folders couldn't be searched.", bundle: .module)
        }
    }
}
