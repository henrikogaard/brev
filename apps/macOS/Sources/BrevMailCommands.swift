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
import BrevMail
import SwiftUI

/// macOS menu-bar commands. Keyboard shortcuts follow Apple's HIG
/// and draw from conventional mail-client bindings (Apple Mail,
/// Outlook, Thunderbird) so muscle memory transfers.
///
/// Cross-platform groups (New Message, Get New Mail, Print, Message menu)
/// are provided by `MailCommands`. This struct adds macOS-only additions:
/// Import/Export and the Keyboard Shortcuts window command.
struct BrevMailCommands: Commands {
    @FocusedValue(\.mailImportAction) private var importAction
    @FocusedValue(\.mailNavigation) private var navigation
    @FocusedValue(\.mailFolders) private var folders
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        MailCommands()

        // MARK: - macOS-only File menu additions

        // Appended after MailCommands' own `.newItem` group; SwiftUI merges
        // same-anchor insertions in declaration order, so the leading Divider
        // separates these from New Message / Get New Mail above.
        CommandGroup(after: .newItem) {
            Divider()

            Button(String(localized: "Import Mail…")) {
                guard let importAction, importAction.isAvailable else { return }
                presentImportMailPanel { request in
                    importAction(request)
                }
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .disabled(importAction?.isAvailable != true)

            Button(String(localized: "Export Mail…")) {
                let folderName = exportSelectedFolderName
                let currentHeaders = navigation?.currentFolderHeaders ?? []
                presentExportMailPanel(suggestedFolderName: folderName) {
                    // Convert MessageHeader metadata to ImportedMessage stubs so
                    // MBOXExporter can produce a valid skeleton archive. Full
                    // body export requires a backend raw-fetch method that will
                    // be added in a future milestone (ADR-0001).
                    currentHeaders.map { header in
                        ImportedMessage(
                            headers: exportHeaders(for: header),
                            bodyData: Data()
                        )
                    }
                }
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(!isExportAvailable)
        }

        // MARK: - Edit menu search

        // The message list search field is an in-pane `NSSearchField` rather
        // than a `.searchable` toolbar item, so it carries no shortcut of its
        // own. Option-Command-F matches Apple Mail's mailbox search binding;
        // plain Command-F is already Message > Forward here, and SwiftUI
        // silently drops a duplicate key equivalent rather than reassigning it.
        CommandGroup(after: .pasteboard) {
            Divider()

            Button(String(localized: "Search Mail")) {
                navigation?.requestSearchFocus()
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
            .disabled(navigation == nil)
        }

        // MARK: - macOS-only Help menu

        CommandGroup(replacing: .help) {
            Button(String(localized: "Keyboard Shortcuts…")) {
                openWindow(id: BrevWindowID.keyboardShortcuts)
            }
        }
    }

    // MARK: - Export helpers

    /// The name of the currently selected folder, used as the suggested
    /// filename stem for the save panel (e.g. "Inbox.mbox").
    private var exportSelectedFolderName: String? {
        guard let folderID = navigation?.selectedFolderID else { return nil }
        return folders?.first { $0.id == folderID }?.name
    }

    /// Export is available when a folder is selected and at least one
    /// header is loaded in the current folder view.
    private var isExportAvailable: Bool {
        MailCommandPlatformPolicy.current.includesFolderMBOXExportCommand
            && navigation?.selectedFolderID != nil
            && navigation?.currentFolderHeaders.isEmpty == false
    }

    /// Derive RFC 2822 header tuples from a `MessageHeader` so
    /// `MBOXExporter` can produce a structurally valid skeleton archive.
    /// Body bytes are intentionally empty until the backend gains a
    /// raw-fetch capability (ADR-0001 phased hook-up).
    ///
    /// `nonisolated` because it is a pure transform over its argument and is
    /// invoked from the export panel's `@Sendable` completion closure; under
    /// strict concurrency a MainActor-isolated method couldn't be called there.
    private nonisolated func exportHeaders(for header: MessageHeader) -> [(name: String, value: String)] {
        let fromValue: String = {
            let name = header.from.name ?? ""
            let email = header.from.email
            return name.isEmpty ? email : "\(name) <\(email)>"
        }()
        let dateValue: String = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss +0000"
            return formatter.string(from: header.date)
        }()
        return [
            (name: "From", value: fromValue),
            (name: "Subject", value: header.subject),
            (name: "Date", value: dateValue),
            (name: "Message-ID", value: header.id)
        ]
    }
}
