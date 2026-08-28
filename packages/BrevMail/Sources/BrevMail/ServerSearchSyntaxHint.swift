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

enum ServerSearchSyntaxHintPolicy {
    static func shouldShow(_ description: ServerSearchSyntaxDescription?) -> Bool {
        guard let description else { return false }
        return !description.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !description.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func examples(_ description: ServerSearchSyntaxDescription) -> [ServerSearchSyntaxExample] {
        description.examples
    }
}

/// A compact search-help menu for providers that expose native query syntax.
struct ServerSearchSyntaxHint: View {
    @Environment(\.brevTheme) private var theme

    let description: ServerSearchSyntaxDescription

    var body: some View {
        if ServerSearchSyntaxHintPolicy.shouldShow(description) {
            Menu {
                Text(verbatim: description.summary)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)

                let examples = ServerSearchSyntaxHintPolicy.examples(description)
                if !examples.isEmpty {
                    Divider()
                    ForEach(examples) { example in
                        VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                            Text(verbatim: example.query)
                                .brevFont(.caption)
                                .foregroundStyle(theme.textPrimary.color)
                            Text(verbatim: example.explanation)
                                .brevFont(.caption)
                                .foregroundStyle(theme.textTertiary.color)
                        }
                    }
                }
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(theme.textSecondary.color)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel(String(localized: "Search help", bundle: .module))
            .accessibilityHint(
                String(localized: "Show \(description.displayName) search operators", bundle: .module)
            )
            .help(String(localized: "Search help: \(description.displayName)", bundle: .module))
        }
    }
}
