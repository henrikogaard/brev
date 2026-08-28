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
import BrevDesign
import BrevThemes
import SwiftUI

enum SenderContextPanelState: Equatable, Sendable {
    case idle
    case loading(MessageHeader)
    case empty(MessageHeader)
    case loaded(MessageHeader, SenderContextSnapshot)
    case failed(MessageHeader, String)

    var header: MessageHeader? {
        switch self {
        case .idle:
            nil
        case .loading(let header),
             .empty(let header),
             .loaded(let header, _),
             .failed(let header, _):
            header
        }
    }
}

struct SenderContextPanel: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.locale) private var locale

    let state: SenderContextPanelState
    let sourceID: MailSourceID?
    let composeActions: MailComposePresentationActions
    let onOpenMessage: (SenderContextRecentItem) -> Void
    let onShowAllFromSender: (String) -> Void

    @State private var hoveredRecentItemID: SenderContextRecentItem.ID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrevSpacing.lg) {
                switch state {
                case .idle:
                    idleState
                case .loading(let header):
                    identitySection(
                        displayName: header.from.displayName,
                        contactDisplayName: nil,
                        email: header.from.email
                    )
                    loadingState
                    actionsSection(for: header)
                case .empty(let header):
                    identitySection(
                        displayName: header.from.displayName,
                        contactDisplayName: nil,
                        email: header.from.email
                    )
                    emptyState
                    actionsSection(for: header)
                case .loaded(let header, let snapshot):
                    identitySection(
                        displayName: snapshot.identity.displayName,
                        contactDisplayName: snapshot.identity.contactDisplayName,
                        email: snapshot.identity.email
                    )
                    relationshipSection(snapshot)
                    recentSection(snapshot.recent)
                    actionsSection(for: header)
                case .failed(let header, let message):
                    identitySection(
                        displayName: header.from.displayName,
                        contactDisplayName: nil,
                        email: header.from.email
                    )
                    errorState(message)
                    actionsSection(for: header)
                }
            }
            .padding(BrevSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var idleState: some View {
        ContentUnavailableView {
            Label(MailContextColumnVisibility.idleTitle, systemImage: "mail.stack")
                .foregroundStyle(theme.textPrimary.color)
        } description: {
            Text("Select a message to see sender details. Mailbox chat below works without one.", bundle: .module)
                .foregroundStyle(theme.textSecondary.color)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.md) {
            Text("Loading local sender history…", bundle: .module)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)

            ForEach(0 ..< 4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.bgSecondary.color)
                    .frame(height: 42)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            Text("No local history yet", bundle: .module)
                .brevFont(.headline)
                .foregroundStyle(theme.textPrimary.color)
            Text("This sender has no cached messages beyond the current selection.", bundle: .module)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            Text("Couldn’t load sender history", bundle: .module)
                .brevFont(.headline)
                .foregroundStyle(theme.textPrimary.color)
            Text(message)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
        }
    }

    private func identitySection(
        displayName: String,
        contactDisplayName: String?,
        email: String
    ) -> some View {
        HStack(alignment: .center, spacing: BrevSpacing.md) {
            BrevAvatarView(
                email: email,
                displayName: contactDisplayName ?? displayName,
                size: 40
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(contactDisplayName ?? displayName)
                    .brevFont(.headline)
                    .foregroundStyle(theme.textPrimary.color)
                    .lineLimit(1)

                if let contactDisplayName,
                   contactDisplayName != displayName {
                    Text(displayName)
                        .brevFont(.caption)
                        .foregroundStyle(theme.textSecondary.color)
                        .lineLimit(1)
                }

                Text(email)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)
        }
    }

    /// What Brev knows about this sender, as aligned label/value rows.
    ///
    /// These were three grey sentences ("5 cached messages", "First seen …"),
    /// which scanned as a paragraph of status text rather than as facts. Get
    /// Info and Xcode's inspectors both put the label in secondary text on a
    /// shared leading edge and the value in primary text beside it, so the
    /// values line up and the eye can run down them.
    private func relationshipSection(_ snapshot: SenderContextSnapshot) -> some View {
        let rows = relationshipRows(for: snapshot)
        return VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            ForEach(rows, id: \.label) { row in
                HStack(alignment: .firstTextBaseline, spacing: BrevSpacing.sm) {
                    Text(row.label)
                        .foregroundStyle(theme.textSecondary.color)
                        .frame(
                            width: Self.relationshipLabelWidth,
                            alignment: .leading
                        )
                    Text(row.value)
                        .foregroundStyle(theme.textPrimary.color)
                    Spacer(minLength: 0)
                }
                .brevFont(.caption)
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// Recent mail from this sender.
    ///
    /// No rule between rows. A hairline per row turned a three-item list into
    /// four horizontal lines in a column barely wider than the text; macOS lists
    /// in an inspector separate rows with spacing and a hover highlight, and
    /// keep rules for boundaries between panels. The highlight is what tells you
    /// the row is a target, so it replaces both the rule and the permanent open
    /// glyph — that glyph, repeated once per row, only restated what clicking
    /// the row already does.
    private func recentSection(_ recent: [SenderContextRecentItem]) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
            MailContextSectionHeader(title: "Recent mail")
                .padding(.bottom, BrevSpacing.xxs)

            ForEach(recent) { item in
                let isHovered = hoveredRecentItemID == item.id
                Button {
                    onOpenMessage(item)
                } label: {
                    HStack(alignment: .top, spacing: BrevSpacing.md) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.subject)
                                .brevFont(.subheadline)
                                .foregroundStyle(theme.textPrimary.color)
                                .lineLimit(2)
                            HStack(spacing: BrevSpacing.xs) {
                                Text(formattedDate(item.date))
                                if let folderName = item.folderName {
                                    Text(verbatim: "•")
                                    Text(folderName)
                                }
                            }
                            .brevFont(.caption)
                            .foregroundStyle(theme.textSecondary.color)
                            .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right.square")
                            .brevFont(.caption)
                            .foregroundStyle(theme.textTertiary.color)
                            .opacity(isHovered ? 1 : 0)
                    }
                    .padding(.vertical, BrevSpacing.sm)
                    .padding(.horizontal, BrevSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: BrevRadius.md, style: .continuous)
                            .fill(
                                theme.textPrimary.color
                                    .opacity(isHovered ? MailContextSeparator.rowHoverOpacity : 0)
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Insets the row's highlight without moving its text off the
                // leading edge the rest of the column shares.
                .padding(.horizontal, -BrevSpacing.sm)
                .onHover { isHovering in
                    hoveredRecentItemID = isHovering ? item.id : nil
                }
                .accessibilityHint(String(localized: "Opens this message.", bundle: .module))
            }
        }
    }

    private func actionsSection(for header: MessageHeader) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            MailContextSectionHeader(title: "Actions")

            HStack(spacing: BrevSpacing.sm) {
                Button(String(localized: "Reply", bundle: .module)) {
                    composeActions.reply(header, sourceID: sourceID)
                }
                Button(String(localized: "Reply All", bundle: .module)) {
                    composeActions.replyAll(header, sourceID: sourceID)
                }
                Button(String(localized: "Forward", bundle: .module)) {
                    composeActions.forward(header, sourceID: sourceID)
                }
                Spacer(minLength: 0)
            }

            Button(String(localized: "Show all from sender", bundle: .module)) {
                onShowAllFromSender(header.from.email)
            }
        }
        // Small controls, the size macOS inspectors use. At the default size
        // four bordered buttons in a two-by-two block read as a form pasted
        // into the column rather than as the tail of a panel.
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(theme.accent.color)
    }

    private func relationshipRows(for snapshot: SenderContextSnapshot) -> [RelationshipRow] {
        var rows: [RelationshipRow] = []

        if let messageCount = snapshot.messageCount {
            let noun = messageCount == 1 ? "message" : "messages"
            rows.append(RelationshipRow(label: "Cached", value: "\(messageCount) \(noun)"))
        }
        if let firstSeen = snapshot.firstSeen {
            rows.append(
                RelationshipRow(label: "First seen", value: formattedDate(firstSeen))
            )
        }
        if let lastSeen = snapshot.lastSeen {
            rows.append(
                RelationshipRow(label: "Last seen", value: formattedDate(lastSeen))
            )
        }

        return rows
    }

    /// One labelled fact about the sender.
    private struct RelationshipRow {
        let label: String
        let value: String
    }

    /// Wide enough for the longest label ("First seen") at caption size, so the
    /// values share a leading edge without measuring text at render time.
    private static let relationshipLabelWidth: CGFloat = 72

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
