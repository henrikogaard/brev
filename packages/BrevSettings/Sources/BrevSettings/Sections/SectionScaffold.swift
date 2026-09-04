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

/// Shared chrome for a settings detail pane: title at the top, scroll
/// region beneath, padded by the standard rhythm.
struct SectionScaffold<Content: View>: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.settingsSearchTarget) private var searchTarget
    let title: String
    let subtitle: String?
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Pane title, then groups. The gap below the title is wider
                // than the gap between groups so the pane reads as titled
                // content rather than as one more group in the stack.
                VStack(alignment: .leading, spacing: BrevSpacing.xl) {
                    VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                        Text(title)
                            .brevFont(.title)
                            .foregroundStyle(theme.textPrimary.color)
                        if let subtitle {
                            Text(subtitle)
                                .brevFont(.subheadline)
                                .foregroundStyle(theme.textSecondary.color)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    content
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, topPadding)
                .padding(.bottom, BrevSpacing.xl)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .task(id: searchTarget) {
                guard let searchTarget else { return }
                await Task.yield()
                proxy.scrollTo(searchTarget, anchor: .top)
            }
        }
        .background(BrevWindowSurfaceBackground(role: .content).ignoresSafeArea())
    }

    private var horizontalPadding: CGFloat {
        #if os(iOS)
        BrevSpacing.lg
        #else
        BrevSpacing.xxl
        #endif
    }

    private var topPadding: CGFloat {
        #if os(iOS)
        BrevSpacing.xl
        #else
        BrevSpacing.xxl
        #endif
    }
}
