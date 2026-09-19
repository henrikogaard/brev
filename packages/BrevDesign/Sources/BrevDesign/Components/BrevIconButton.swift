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

import BrevThemes
import SwiftUI

/// Shared icon-only button with a guaranteed 44-point minimum hit target on
/// touch platforms. The visible glyph keeps its compact size; only the tappable
/// area grows. Always provide an accessibility label — icon-only controls have
/// no readable text for VoiceOver.
public struct BrevIconButton: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    private let systemName: String
    private let accessibilityLabel: Text
    private let help: Text?
    private let iconSize: CGFloat
    private let isDestructive: Bool
    private let action: () -> Void

    /// Creates an icon-only button.
    /// - Parameters:
    ///   - systemName: SF Symbol name.
    ///   - accessibilityLabel: VoiceOver label. Pass `bundle:` from package call sites.
    ///   - help: Optional macOS tooltip; defaults to the accessibility label.
    ///   - iconSize: Glyph point size; the hit area stays 44 pt on iOS regardless.
    ///   - isDestructive: Tints the glyph with the theme danger role.
    public init(
        systemName: String,
        accessibilityLabel: LocalizedStringKey,
        bundle: Bundle? = nil,
        help: LocalizedStringKey? = nil,
        iconSize: CGFloat = 14,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.accessibilityLabel = Text(accessibilityLabel, bundle: bundle)
        self.help = help.map { Text($0, bundle: bundle) }
        self.iconSize = iconSize
        self.isDestructive = isDestructive
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(isDestructive ? theme.danger.color : theme.textSecondary.color)
                .frame(minWidth: minimumHitSize, minHeight: minimumHitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1.0 : 0.45)
        .accessibilityLabel(accessibilityLabel)
        .help(help ?? accessibilityLabel)
    }

    private var minimumHitSize: CGFloat {
        #if os(iOS)
        44
        #else
        0
        #endif
    }
}
