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

import AppKit
import BrevBackend
import BrevMail
import Foundation
import UniformTypeIdentifiers

// MARK: - Export

/// Chooses the archive path; the root-owned action handles export and progress.
@MainActor
func presentExportMailPanel(suggestedFolderName: String, sourceTitle: String,
                            onPick: @escaping @MainActor (URL) -> Void) {
    let panel = NSSavePanel()
    panel.title = String(localized: "Export Mail")
    panel.prompt = String(localized: "Export")
    panel.message = String(localized: "Export every message from \(sourceTitle) as an MBOX archive.")
    panel.nameFieldStringValue = MailFolderExporter.suggestedArchiveName(for: suggestedFolderName)
    panel.allowedContentTypes = [.mbox]
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let url = panel.url else { return }
    onPick(url)
}

// MARK: - Import

/// Runs an `NSOpenPanel` that accepts `.mbox` archives, `.eml` files, and
/// Maildir directories, then invokes `onPick` with the chosen import request.
///
/// The actual import is performed by the BrevMail layer via a
/// `FocusedValue` so AppKit stays out of the cross-platform packages.
@MainActor
func presentImportMailPanel(onPick: @escaping @MainActor (MailImportRequest) -> Void) {
    let panel = NSOpenPanel()
    panel.title = String(localized: "Import Mail")
    panel.prompt = String(localized: "Import")
    panel.message = String(localized: "Choose an .mbox archive, .eml file, or Maildir folder to import.")
    panel.allowedContentTypes = [.mbox, .eml]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = true
    panel.canChooseFiles = true

    guard panel.runModal() == .OK, let url = panel.url else { return }
    onPick(mailImportRequest(for: url))
}

private func mailImportRequest(for url: URL) -> MailImportRequest {
    if isDirectory(url) {
        return MailImportRequest(url: url, format: .maildir)
    }
    switch url.pathExtension.lowercased() {
    case "eml":
        return MailImportRequest(url: url, format: .eml)
    default:
        return MailImportRequest(url: url, format: .mbox)
    }
}

private func isDirectory(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
}

// MARK: - UTType extensions

private extension UTType {
    /// Unix MBOX mail archive format (RFC 4155).
    static let mbox = UTType(filenameExtension: "mbox") ?? .data
    /// Individual RFC 2822 message file.
    static let eml = UTType(filenameExtension: "eml") ?? .data
}
