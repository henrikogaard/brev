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

/// Text for a macOS attachment card (#306 slice 4, part 2).
enum MessageAttachmentCardPresentation {
    /// "PDF · 240 KB": the file extension as a kind, then the size. Names
    /// without a short extension show the size only.
    static func subtitle(filename: String, sizeText: String) -> String {
        let ext = (filename as NSString).pathExtension
        // A kind is short, alphanumeric and has a letter, so "v1.2" or
        // "backup-2026" are not mistaken for one.
        let isPlausibleKind = !ext.isEmpty && ext.count <= 5
            && ext.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
            && ext.contains(where: \.isLetter)
            && !(filename as NSString).deletingPathExtension.isEmpty
        guard isPlausibleKind else { return sizeText }
        return [ext.uppercased(), sizeText].joined(separator: " · ")
    }
}

/// One attachment as a card: a file-type icon, the name, "kind · size", the
/// primary action and a ••• menu with the rest. The reader wraps it with the
/// macOS pointer interactions (hover, double-click to open, drag out).
struct MessageAttachmentCard: View {
    let name: String
    let systemImage: String
    let subtitle: String
    let isHovered: Bool
    let isDownloading: Bool
    let primaryAction: MessageAttachmentActionPresentation?
    let overflowActions: [MessageAttachmentActionPresentation]
    let onAction: (MessageAttachmentActionKind) -> Void

    @Environment(\.brevTheme) private var theme

    var body: some View {
        HStack(spacing: BrevSpacing.sm) {
            Image(systemName: systemImage)
                .foregroundStyle(theme.textSecondary.color)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: BrevRadius.sm, style: .continuous)
                        // Swap shades on hover so the icon tile stays visible.
                        .fill(isHovered ? theme.bgSecondary.color : theme.bgTertiary.color)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                Text(verbatim: name)
                    .brevFont(.footnote)
                    .foregroundStyle(theme.textPrimary.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: subtitle)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textTertiary.color)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: BrevSpacing.xs)
            if isDownloading {
                ProgressView()
                    .controlSize(.small)
            } else if let primaryAction {
                Button {
                    onAction(primaryAction.kind)
                } label: {
                    Image(systemName: primaryAction.systemImage)
                }
                .buttonStyle(.borderless)
                .disabled(primaryAction.isDisabled)
                .accessibilityLabel(primaryAction.title)
            }
            Menu {
                ForEach(overflowActions) { action in
                    Button {
                        onAction(action.kind)
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                    }
                    .disabled(action.isDisabled)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            #if os(macOS)
            .menuStyle(.borderlessButton)
            #endif
            .fixedSize()
            .accessibilityLabel(String(localized: "More attachment actions", bundle: .module))
        }
        .padding(BrevSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BrevRadius.md, style: .continuous)
                .fill(isHovered ? theme.bgTertiary.color : theme.bgSecondary.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BrevRadius.md, style: .continuous)
                .stroke(theme.border.color, lineWidth: 0.5)
        )
    }
}
