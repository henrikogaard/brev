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

#if canImport(WidgetKit)
import SwiftUI
import WidgetKit

/// The mail summary widget body. Renders purely from the snapshot —
/// semantic system colors only, since this package intentionally has no
/// BrevDesign dependency (ADR-0083 keeps the extension dependency-free).
struct MailSummaryWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    let entry: MailSummaryEntry
    /// Tests and previews pass an explicit family — `widgetFamily` is
    /// read-only in the environment.
    var familyOverride: WidgetFamily?

    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    var body: some View {
        switch family {
        case .systemMedium:
            mediumBody
        default:
            smallBody
        }
    }

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Spacer(minLength: 0)
            if let preview = entry.snapshot?.previews.first {
                previewRow(preview, showsAccount: false)
            } else {
                emptyLabel
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mediumBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let previews = entry.snapshot?.previews, !previews.isEmpty {
                ForEach(previews.prefix(3)) { preview in
                    previewRow(preview, showsAccount: true)
                }
            } else {
                Spacer(minLength: 0)
                emptyLabel
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(unreadTitle)
                .font(.title2.weight(.semibold))
            Spacer(minLength: 4)
            if let generatedAt = entry.snapshot?.generatedAt {
                Text(generatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var unreadTitle: String {
        let count = entry.snapshot?.totalUnread ?? 0
        return String(localized: "\(count) unread", bundle: .module)
    }

    private var emptyLabel: some View {
        Text(emptyTitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var emptyTitle: String {
        if entry.snapshot == nil {
            return String(localized: "Open Brev to see your mail.", bundle: .module)
        }
        return String(localized: "You're all caught up.", bundle: .module)
    }

    private func previewRow(_ preview: WidgetMessagePreview, showsAccount: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(.tint.opacity(0.15))
                .frame(width: 24, height: 24)
                .overlay(
                    Text(initials(for: preview.senderName))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                )
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(preview.senderName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    if showsAccount, let accountName = preview.accountName {
                        Text(accountName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text(preview.receivedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(preview.subject)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func initials(for sender: String) -> String {
        let parts = sender.split(separator: " ").filter { !$0.isEmpty }
        let letters = parts.prefix(2).compactMap { $0.first }
        if letters.isEmpty {
            return String(sender.prefix(1)).uppercased()
        }
        return letters.map(String.init).joined().uppercased()
    }
}
#endif
