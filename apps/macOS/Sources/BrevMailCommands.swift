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
    @FocusedValue(\.mailFolderExportAction) private var exportAction
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        MailCommands()
        MailUndoCommands()

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
                guard let exportAction, exportAction.isAvailable else { return }
                presentExportMailPanel(suggestedFolderName: exportAction.folderName,
                                       sourceTitle: exportAction.sourceTitle) { url in
                    exportAction(url)
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

    private var isExportAvailable: Bool {
        MailCommandPlatformPolicy.current.includesFolderMBOXExportCommand && exportAction?.isAvailable == true
    }
}
