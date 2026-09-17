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

/// Shared compact progress and coverage feedback for folder and unified searches.
struct MailSearchStatusView: View {
    @Environment(\.brevTheme) private var theme
    let progress: MailSearchProgressState
    let checksAttachments: Bool
    let retry: () -> Void

    private var title: String {
        if progress.sourceCount == 0 { return String(localized: "No mailboxes searched", bundle: .module) }
        if progress.hasFailure,
           progress.isSearching { return String(localized: "Searching remaining mailboxes…", bundle: .module) }
        if progress.hasFailure { return String(localized: "Search incomplete", bundle: .module) }
        if progress.isSearching {
            return progress.cachedSourceCount > 0
                ? String(localized: "Showing cached matches · Searching server…", bundle: .module)
                : String(localized: "Searching…", bundle: .module)
        }
        if progress.unverifiedSourceCount > 0 { return String(
            localized: "Search finished · Some results may be missing",
            bundle: .module
        ) }
        if progress.cachedSourceCount == progress.sourceCount { return String(localized: "Cached results only", bundle: .module) }
        if progress.cachedSourceCount > 0 { return String(localized: "Some results are limited to cached mail", bundle: .module) }
        return String(localized: "Server search complete", bundle: .module)
    }

    private var detail: String? {
        if progress.isSearching, checksAttachments {
            return String(
                localized: "Checks message contents page by page and may download data. No background fetch is running.",
                bundle: .module
            )
        }
        if progress.hasFailure {
            return progress.isSearching
                ? String(
                    localized: "Some results could not be loaded. Other mailboxes are still being searched.",
                    bundle: .module
                )
                : String(localized: "Some results could not be loaded. Try searching again.", bundle: .module)
        }
        if !progress.isSearching, progress.cachedSourceCount > 0 {
            return String(localized: "Cached results include only mail stored on this device.", bundle: .module)
        }
        return nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: BrevSpacing.sm) {
            if progress.isSearching {
                ProgressView().controlSize(.small).tint(theme.accent.color)
            }
            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                Text(title).foregroundStyle(theme.textPrimary.color)
                if let detail { Text(detail).foregroundStyle(theme.textSecondary.color) }
            }
            .brevFont(.caption)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if progress.canRetry {
                Button(action: retry) {
                    Text("Retry", bundle: .module)
                    #if os(iOS)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                    #endif
                }
                .buttonStyle(.borderless)
                .foregroundStyle(theme.accent.color)
                .accessibilityLabel(String(localized: "Retry search", bundle: .module))
            }
        }
        .padding(.horizontal, BrevSpacing.lg)
        .padding(.vertical, BrevSpacing.sm)
        .background(theme.bgSecondary.color)
        .accessibilityElement(children: .contain)
    }
}
