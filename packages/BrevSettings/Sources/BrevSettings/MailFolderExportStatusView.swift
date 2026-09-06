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
#if os(macOS)
import AppKit
#endif

/// Compact export feedback shared by the mailbox workspace and Settings.
public struct MailFolderExportStatusView: View {
    @Environment(\.brevTheme) private var theme
    private let state: MailFolderExportState
    private let sourceTitle: String
    private let onCancel: () -> Void
    private let onDismiss: () -> Void

    /// Shows the captured source, progress, and task controls.
    public init(state: MailFolderExportState, sourceTitle: String,
                onCancel: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.state = state
        self.sourceTitle = sourceTitle
        self.onCancel = onCancel
        self.onDismiss = onDismiss
    }

    public var body: some View {
        if state != .idle {
            HStack(spacing: BrevSpacing.sm) {
                if isRunning {
                    ProgressView().controlSize(.small).tint(theme.accent.color)
                } else {
                    Image(systemName: symbolName).foregroundStyle(theme.textSecondary.color)
                }
                VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                    Text(sourceTitle).id(sourceTitle).brevFont(.caption).fontWeight(.medium)
                        .foregroundStyle(theme.textPrimary.color).lineLimit(1).help(sourceTitle)
                    Text(message).brevFont(.caption).foregroundStyle(theme.textSecondary.color)
                        .lineLimit(3).help(message)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: BrevSpacing.sm)
                if case .exporting = state {
                    Button(action: onCancel) {
                        Text("Cancel", bundle: .module).modifier(ExportControlHitTarget())
                    }
                    .accessibilityLabel(String(localized: "Cancel folder export", bundle: .module))
                } else if !isRunning {
                    #if os(macOS)
                    if case .completed(let url, _) = state {
                        Button(String(localized: "Show in Finder", bundle: .module)) {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                    #endif
                    Button(action: onDismiss) {
                        Image(systemName: "xmark").modifier(ExportControlHitTarget())
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Dismiss", bundle: .module))
                    .accessibilityLabel(String(localized: "Dismiss export status", bundle: .module))
                }
            }
            .controlSize(.small).padding(BrevSpacing.sm)
            .background(theme.bgSecondary.color)
            .clipShape(RoundedRectangle(cornerRadius: BrevRadius.sm))
            .overlay {
                RoundedRectangle(cornerRadius: BrevRadius.sm).stroke(theme.border.color.opacity(0.35), lineWidth: 1)
            }
        }
    }

    private var isRunning: Bool {
        switch state {
        case .exporting, .cancelling: true
        default: false
        }
    }

    private var symbolName: String {
        switch state {
        case .completed: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        default: "tray.and.arrow.up"
        }
    }

    private var message: String {
        switch state {
        case .idle: return ""
        case .exporting(let count):
            return count == 1 ? String(localized: "Exporting… 1 message", bundle: .module)
                : String(localized: "Exporting… \(count) messages", bundle: .module)
        case .cancelling: return String(localized: "Canceling export…", bundle: .module)
        case .completed(_, let count):
            return count == 1 ? String(localized: "Exported 1 message.", bundle: .module)
                : String(localized: "Exported \(count) messages.", bundle: .module)
        case .cancelled: return String(localized: "Export canceled.", bundle: .module)
        case .failed(let reason): return String(localized: "Export failed: \(reason)", bundle: .module)
        }
    }
}

struct ExportControlHitTarget: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        #else
        content
        #endif
    }
}
