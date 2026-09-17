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

/// Compact conversation-coverage feedback for the reader (ADR-0074 §8).
///
/// Shows the explicit **Load related mail** action while only the cached
/// snapshot is available, progress while remote discovery runs, and honest
/// partial/complete-for-scope results with Retry and Spam/Trash inclusion.
struct RelatedConversationBar: View {
    @Environment(\.brevTheme) private var theme
    let controller: RelatedConversationController

    var body: some View {
        HStack(spacing: BrevSpacing.sm) {
            Image(systemName: presentation.symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(presentation.tint)
            Text(presentation.message)
                .brevFont(.footnote)
                .foregroundStyle(theme.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: BrevSpacing.sm)
            actions
        }
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bgSecondary.color)
        .accessibilityElement(children: .combine)
    }

    /// One dispatch over the controller's state keeps the symbol, tint and
    /// copy consistent — a coverage case can never show another case's icon.
    private var presentation: (symbol: String, tint: Color, message: String) {
        if controller.isLoadingRemote {
            return ("arrow.triangle.2.circlepath", theme.textSecondary.color,
                    String(localized: "Loading related mail across folders…", bundle: .module))
        }
        if controller.remoteLoadDidFail {
            return ("exclamationmark.triangle", theme.warning.color,
                    String(localized: "Couldn't load related mail.", bundle: .module))
        }
        switch controller.snapshot?.coverage {
        case .completeForScope:
            return ("checkmark.circle", theme.accent.color,
                    String(localized: "Conversation complete for this mailbox.", bundle: .module))
        case .partial:
            return ("exclamationmark.circle", theme.warning.color,
                    String(localized: "Partial — some folders couldn't be searched.", bundle: .module))
        case .loading:
            return ("arrow.triangle.2.circlepath", theme.textSecondary.color,
                    String(localized: "Loading related mail…", bundle: .module))
        case .cached:
            return ("arrow.triangle.branch", theme.textSecondary.color,
                    String(localized: "Showing cached conversation.", bundle: .module))
        case nil:
            return ("arrow.triangle.branch", theme.textSecondary.color,
                    String(localized: "Brev can look for related mail in other folders of this account.",
                           bundle: .module))
        }
    }

    @ViewBuilder
    private var actions: some View {
        if controller.isLoadingRemote {
            ProgressView()
                .controlSize(.small)
        } else {
            if controller.remoteLoadDidFail || controller.snapshot?.coverage == .partial {
                BrevButton(String(localized: "Retry", bundle: .module), style: .tertiary) {
                    controller.retry()
                }
            }
            if controller.canLoadRelated,
               !controller.remoteLoadAttempted || controller.remoteLoadDidFail {
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
            }
            if let snapshot = controller.snapshot,
               !snapshot.excludedFolderIDs.isEmpty,
               !controller.includesSpamAndTrash {
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
