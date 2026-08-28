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
import SwiftUI

/// Cross-platform menu commands shared by macOS and iOS.
/// Platform-specific additions (Import/Export, Keyboard Shortcuts window)
/// are defined separately in each app target. `MailCommandPlatformPolicy`
/// captures the platform capability matrix this split reflects; it is a
/// test-only record of intent, not a runtime gate — the macOS-only groups
/// are separated at compile time by living in the macOS app target.
public struct MailCommands: Commands {
    @FocusedValue(\.mailNavigation) private var navigation
    @FocusedValue(\.mailBackend) private var messageBackend
    @FocusedValue(\.mailFolders) private var folders
    @FocusedValue(\.refreshSelectedMailFolder) private var refreshSelectedFolder
    @FocusedValue(\.mailMessageCommandActions) private var messageActions
    @FocusedValue(\.mailComposePresentationActions) private var composeActions
    @FocusedValue(\.mailPrintExportActions) private var printExportActions
    @FocusedValue(\.mailContextColumnAction) private var mailContextColumnAction

    /// Creates the cross-platform command set.
    public init() {}

    public var body: some Commands {
        // MARK: - File menu additions

        CommandGroup(after: .newItem) {
            Button(String(localized: "New Message", bundle: .module)) {
                composeActions?.newMessage()
            }
            .keyboardShortcut("n")
            .disabled(!isComposePresentationAvailable)

            Button(String(localized: "Get New Mail", bundle: .module)) {
                guard isRefreshSelectedFolderAvailable else { return }
                Task {
                    await refreshSelectedFolder?()
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(
                navigation?.selectedFolderID == nil
                    || refreshSelectedFolder == nil
                    || !isRefreshSelectedFolderAvailable
                    || folders?.contains { $0.id == navigation?.selectedFolderID } != true
            )
        }

        CommandGroup(replacing: .printItem) {
            Button(String(localized: "Print…", bundle: .module)) {
                printExportActions?.print()
            }
            .keyboardShortcut("p")
            .disabled(printExportActions?.isAvailable != true)

            Button(String(localized: "Export as PDF…", bundle: .module)) {
                printExportActions?.exportPDF()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(printExportActions?.isAvailable != true)
        }

        // MARK: - Message menu

        CommandMenu("Message") {
            Button(String(localized: "Previous Message", bundle: .module)) {
                navigation?.selectPreviousHeader()
            }
            .keyboardShortcut(.upArrow, modifiers: [.command])
            .disabled(navigation?.currentFolderHeaders.isEmpty != false)

            Button(String(localized: "Next Message", bundle: .module)) {
                navigation?.selectNextHeader()
            }
            .keyboardShortcut(.downArrow, modifiers: [.command])
            .disabled(navigation?.currentFolderHeaders.isEmpty != false)

            Divider()

            Button(String(localized: "Reply", bundle: .module)) {
                guard isComposePresentationAvailable,
                      let header = navigation?.selectedHeader else { return }
                composeActions?.reply(header)
            }
            .keyboardShortcut("r")
            .disabled(!messageCommandState.canReply)

            Button(String(localized: "Reply All", bundle: .module)) {
                guard isComposePresentationAvailable,
                      let header = navigation?.selectedHeader else { return }
                composeActions?.replyAll(header)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!messageCommandState.canReplyAll)

            Button(String(localized: "Forward", bundle: .module)) {
                guard isComposePresentationAvailable,
                      let header = navigation?.selectedHeader else { return }
                composeActions?.forward(header)
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(!messageCommandState.canForward)

            Divider()

            Button(readToggleTitle) {
                guard isMessageActionAvailable,
                      let header = navigation?.selectedHeader else { return }
                Task {
                    await messageActions?.toggleRead(header)
                }
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(!messageCommandState.canToggleRead)

            Button(flagToggleTitle) {
                guard isMessageActionAvailable,
                      let header = navigation?.selectedHeader else { return }
                Task {
                    await messageActions?.toggleStar(header)
                }
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(!messageCommandState.canToggleFlag)

            Divider()

            Button(String(localized: "Archive", bundle: .module)) {
                guard isMessageActionAvailable,
                      let header = navigation?.selectedHeader else { return }
                Task {
                    await messageActions?.archive(header)
                }
            }
            .keyboardShortcut("e")
            .disabled(!messageCommandState.canArchive)

            let moveFolderCandidates = MessageCommandPresentation.moveFolderCandidates(
                from: folders ?? [],
                currentFolderID: navigation?.selectedHeader?.folderID
            )
            if !moveFolderCandidates.isEmpty {
                Menu(String(localized: "Move", bundle: .module)) {
                    ForEach(moveFolderCandidates) { destination in
                        Button(destination.name) {
                            guard isMessageActionAvailable,
                                  let header = navigation?.selectedHeader else { return }
                            Task {
                                await messageActions?.move(header, to: destination)
                            }
                        }
                        .disabled(!messageCommandState.canMove)
                    }
                }
                .disabled(!messageCommandState.canMove)
            }

            if let junkActionTitle = messageCommandState.junkActionTitle {
                Button(junkActionTitle) {
                    guard isMessageActionAvailable,
                          let header = navigation?.selectedHeader else { return }
                    Task {
                        await messageActions?.setJunk(currentFolder?.role != .spam, for: header)
                    }
                }
                .keyboardShortcut("j", modifiers: [.command, .shift])
                .disabled(!messageCommandState.canSetJunk)
            }

            Button(String(localized: "Delete", bundle: .module)) {
                guard isMessageActionAvailable,
                      let header = navigation?.selectedHeader else { return }
                Task {
                    await messageActions?.delete(header)
                }
            }
            .keyboardShortcut(.delete)
            .disabled(!messageCommandState.canDelete)

            Divider()

            // -- Additional / alternative shortcuts --------------------------
            // These parallel the shortcuts above but use the bindings that
            // experienced users of Apple Mail, Thunderbird, and Gmail expect.

            Button(readToggleTitle) {
                guard isMessageActionAvailable,
                      let header = navigation?.selectedHeader else { return }
                Task {
                    await messageActions?.toggleRead(header)
                }
            }
            // Cmd+U — alternate for toggle read (Apple Mail binding)
            .keyboardShortcut("u")
            .disabled(!messageCommandState.canToggleRead)

            Button(flagToggleTitle) {
                guard isMessageActionAvailable,
                      let header = navigation?.selectedHeader else { return }
                Task {
                    await messageActions?.toggleStar(header)
                }
            }
            // Cmd+S — alternate for toggle flag
            .keyboardShortcut("s")
            .disabled(!messageCommandState.canToggleFlag)

            Button(String(localized: "Forward", bundle: .module)) {
                guard isComposePresentationAvailable,
                      let header = navigation?.selectedHeader else { return }
                composeActions?.forward(header)
            }
            // Cmd+F — alternate for forward (Apple Mail binding)
            .keyboardShortcut("f")
            .disabled(!messageCommandState.canForward)

            Button(String(localized: "Previous Message", bundle: .module)) {
                navigation?.selectPreviousHeader()
            }
            // Cmd+[ — Gmail-style previous-message shortcut
            .keyboardShortcut("[")
            .disabled(navigation?.currentFolderHeaders.isEmpty != false)

            Button(String(localized: "Next Message", bundle: .module)) {
                navigation?.selectNextHeader()
            }
            // Cmd+] — Gmail-style next-message shortcut
            .keyboardShortcut("]")
            .disabled(navigation?.currentFolderHeaders.isEmpty != false)

            Button(String(localized: "Focus Search", bundle: .module)) {
                navigation?.requestSearchFocus()
            }
            .keyboardShortcut("/")

            #if os(macOS)
            Divider()

            Button(mailContextColumnAction?.label ?? MailContextColumnVisibility.toolbarLabel) {
                mailContextColumnAction?.toggle()
            }
            .keyboardShortcut(
                KeyEquivalent(MailContextColumnVisibility.keyboardShortcutKey),
                modifiers: MailContextColumnVisibility.keyboardShortcutModifiers
            )
            .disabled(mailContextColumnAction?.isAvailable != true)
            #endif
        }
    }

    // MARK: - Supporting computed properties

    private var readToggleTitle: String {
        messageCommandState.readToggleTitle
    }

    private var flagToggleTitle: String {
        messageCommandState.flagToggleTitle
    }

    private var messageCommandState: MailMessageCommandState {
        MailMessageCommandStatePolicy.state(
            selectedHeader: navigation?.selectedHeader,
            folders: folders,
            backendCapabilities: mailBackendCapabilities,
            messageActionsAvailable: isMessageActionAvailable,
            composePresentationAvailable: isComposePresentationAvailable
        )
    }

    private var currentFolder: Folder? {
        guard let folderID = navigation?.selectedHeader?.folderID else { return nil }
        return folders?.first { $0.id == folderID }
    }

    private var mailBackendCapabilities: BackendCapabilities {
        guard let backend = messageBackend else { return [] }
        return backend.capabilities
    }

    private var isMessageActionAvailable: Bool {
        messageActions?.isAvailable == true
    }

    private var isRefreshSelectedFolderAvailable: Bool {
        refreshSelectedFolder?.isAvailable == true
    }

    private var isComposePresentationAvailable: Bool {
        composeActions?.isAvailable == true
    }
}
