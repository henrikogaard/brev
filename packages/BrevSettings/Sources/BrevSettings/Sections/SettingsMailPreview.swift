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

/// Local sample mail makes theme, text, and density choices visible immediately.
struct SettingsMailPreview: View {
    @Environment(\.brevTheme) private var theme
    var settings: MailboxViewSettings = .defaults

    var body: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            Text("Mail preview", bundle: .module)
                .brevFont(.footnote)
                .foregroundStyle(theme.textSecondary.color)
            VStack(spacing: 0) {
                sample(sender: String(localized: "Alex Morgan", bundle: .module),
                       subject: String(localized: "Plans for the weekend", bundle: .module), selected: true)
                sample(sender: String(localized: "Design team", bundle: .module),
                       subject: String(localized: "Updated project notes", bundle: .module), selected: false)
            }
            .clipShape(RoundedRectangle(cornerRadius: BrevRadius.sm))
            .overlay {
                RoundedRectangle(cornerRadius: BrevRadius.sm).stroke(theme.border.color, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func sample(sender: String, subject: String, selected: Bool) -> some View {
        HStack(alignment: .top, spacing: BrevSpacing.sm) {
            if settings.showSenderAvatars {
                Text(String(sender.prefix(1)))
                    .brevFont(.body)
                    .frame(width: 30, height: 30)
                    .background(theme.bgTertiary.color, in: Circle())
            }
            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                Text(sender).fontWeight(.semibold)
                Text(subject)
                if settings.previewLineCount.rawValue > 0 {
                    Text("Thanks for the update. I'll send the details before our next meeting.", bundle: .module)
                        .foregroundStyle(theme.textSecondary.color)
                        .lineLimit(settings.previewLineCount.rawValue)
                }
            }
            .font(settings.fontFamily.font(size: settings.textSize.bodyPointSize))
            Spacer(minLength: 0)
            Text("10:30", bundle: .module).brevFont(.footnote).foregroundStyle(theme.textSecondary.color)
        }
        .foregroundStyle(theme.textPrimary.color)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, verticalPadding)
        .background(selected ? theme.selection.color : theme.bgPrimary.color)
        .overlay(alignment: .leading) {
            if selected {
                Rectangle().fill(theme.textPrimary.color).frame(width: 2)
            }
        }
    }

    private var verticalPadding: CGFloat {
        switch settings.listDensity {
        case .compact: 6
        case .comfortable: 10
        case .spacious: 14
        }
    }
}
