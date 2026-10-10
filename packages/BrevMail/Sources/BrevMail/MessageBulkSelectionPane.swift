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
import Foundation
import SwiftUI

/// The message list's bulk-selection handlers, published to the reader pane
/// so its "N messages selected" buttons run the same code as the list's bulk
/// action bar.
struct MailBulkSelectionActions {
    /// Whether the open folder has an Archive destination.
    var canArchive: Bool
    var markRead: () -> Void
    var markUnread: () -> Void
    var flag: () -> Void
    var archive: () -> Void
    var delete: () -> Void
    var clearSelection: () -> Void
}

/// Copy for the multi-selection reader pane.
enum MessageBulkSelectionPresentation {
    /// Fewest checked messages for which the pane replaces the reader.
    static let minimumCount = 2

    /// Whether `count` checked messages replace the reader with the pane.
    static func showsPane(forSelectionCount count: Int) -> Bool {
        count >= minimumCount
    }

    /// Plural-aware heading, for example "3 messages selected".
    /// - Parameters:
    ///   - count: Number of checked messages.
    ///   - bundle: Bundle whose localization is used; tests pass a language
    ///     sub-bundle to check each translation.
    static func title(count: Int, bundle: Bundle = .module) -> String {
        String(localized: "\(count) messages selected", bundle: bundle)
    }
}

#if os(macOS)
/// Reader pane shown while two or more messages are checked: a count and the
/// main bulk actions, in place of the "No message selected" placeholder.
struct MessageBulkSelectionPane: View {
    @Environment(\.brevTheme) private var theme

    let count: Int
    let actions: MailBulkSelectionActions?
    let isDisabled: Bool

    var body: some View {
        VStack(spacing: BrevSpacing.lg) {
            Image(systemName: "square.stack")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(theme.textTertiary.color)
            Text(MessageBulkSelectionPresentation.title(count: count))
                .brevFont(.headline)
                .foregroundStyle(theme.textSecondary.color)
            if let actions {
                let disabled = isDisabled
                HStack(spacing: BrevSpacing.sm) {
                    actionButton(String(localized: "Mark Read", bundle: .module), "envelope.open", disabled, actions.markRead)
                    actionButton(
                        String(localized: "Mark Unread", bundle: .module),
                        "envelope.badge",
                        disabled,
                        actions.markUnread
                    )
                    actionButton(String(localized: "Flag", bundle: .module), "flag", disabled, actions.flag)
                    if actions.canArchive {
                        actionButton(String(localized: "Archive", bundle: .module), "archivebox", disabled, actions.archive)
                    }
                    actionButton(String(localized: "Delete", bundle: .module), "trash", disabled, actions.delete)
                }
                Button(String(localized: "Clear Selection", bundle: .module), action: actions.clearSelection)
                    .buttonStyle(.link)
                    .foregroundStyle(theme.textSecondary.color)
            }
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(BrevSpacing.xl)
        .accessibilityElement(children: .contain)
    }

    private func actionButton(
        _ title: String,
        _ systemImage: String,
        _ disabled: Bool,
        _ action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .disabled(disabled)
    }
}
#endif
