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

import Observation
import SwiftUI

/// Observable state behind the share sheet, owned by `ShareViewController`.
@MainActor
@Observable
final class ShareSheetModel {
    /// What was shared and whether it can be opened.
    var content = ShareSheetContent.loading
    /// Set after Brev could not be opened, so the primary action reads "Try Again".
    var handoffFailed = false
}

/// Native share sheet content: a grouped list of what is being shared with
/// Cancel and "Open Brev" in the navigation bar, like the system Mail and
/// Messages share sheets. The extension links no Brev packages, so colors are
/// system semantic colors and the tint is the system tint.
struct ShareSheetView: View {
    let model: ShareSheetModel
    let onCancel: () -> Void
    let onOpen: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if model.content.isLoading {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Loading shared content...", bundle: .main)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } else {
                    contentSections
                }
            }
            .navigationTitle(Text("Compose in Brev", bundle: .main))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onCancel) { Text("Cancel", bundle: .main) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: onOpen) {
                        if model.handoffFailed {
                            Text("Try Again", bundle: .main).bold()
                        } else {
                            Text("Open Brev", bundle: .main).bold()
                        }
                    }
                    .disabled(!model.content.canOpen)
                }
            }
        }
    }

    @ViewBuilder
    private var contentSections: some View {
        let content = model.content

        if model.handoffFailed {
            Section {
                Label {
                    Text("Brev could not open this shared draft. Please try again.", bundle: .main)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                }
            }
        }

        if let message = content.message {
            Section {
                Label {
                    Text(message)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
        }

        if content.text != nil || !content.urls.isEmpty || !content.attachmentNames.isEmpty {
            Section {
                if let text = content.text {
                    row(systemImage: "text.alignleft") {
                        Text(text).lineLimit(5)
                    }
                }
                ForEach(content.urls, id: \.self) { url in
                    row(systemImage: "link") {
                        Text(url).lineLimit(2).truncationMode(.middle)
                    }
                }
                ForEach(content.attachmentNames, id: \.self) { name in
                    row(systemImage: "paperclip") {
                        Text(name).lineLimit(2).truncationMode(.middle)
                    }
                }
            } footer: {
                if !content.notes.isEmpty {
                    Text(content.notes.joined(separator: " · "))
                }
            }
        } else if !content.notes.isEmpty {
            Section {
                Text(content.notes.joined(separator: " · "))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row(systemImage: String, @ViewBuilder _ label: () -> some View) -> some View {
        Label {
            label()
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}
