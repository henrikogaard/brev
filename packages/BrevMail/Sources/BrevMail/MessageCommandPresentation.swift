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
import Foundation

enum MessageContextMenuAction: CaseIterable, Hashable, Sendable {
    case openInNewWindow
    case select
    case pinToTop
    case toggleRead
    case toggleFlag
    case toggleSnooze
    case toggleDone
    case reply
    case replyAll
    case forward
    case archive
    case move
    case copyToFolder
    case copyToLocalFolder
    case moveToLocalFolder
    case setJunk
    case blockSender
    case delete
    case print
    case exportPDF
    case saveAs
    case createMeeting
    case createTask
    case createRule
    case addNote
    case followUp
    case downloadOffline
    case properties
    case showHeaders
    case viewSource
}

enum MessageContextMenuRole: Equatable, Sendable {
    case destructive
}

enum MessageContextMenuActionWiring: Equatable, Sendable {
    case visible(handler: String, dependency: String, platforms: String)
    case hiddenUntilImplemented(reason: String)
}

struct MessageContextMenuActionInventory: Equatable, Sendable {
    let action: MessageContextMenuAction
    let title: String
    let enabledCondition: String
    let wiring: MessageContextMenuActionWiring
}

struct MessageContextMenuActionPresentation: Equatable, Sendable {
    let action: MessageContextMenuAction
    let title: String
    let symbolName: String
    let isEnabled: Bool
    let role: MessageContextMenuRole?

    init(
        action: MessageContextMenuAction,
        title: String,
        symbolName: String,
        isEnabled: Bool = true,
        role: MessageContextMenuRole? = nil
    ) {
        self.action = action
        self.title = title
        self.symbolName = symbolName
        self.isEnabled = isEnabled
        self.role = role
    }
}

struct MessageContextMenuSection: Equatable, Sendable {
    let actions: [MessageContextMenuActionPresentation]
}

struct MessageContextMenuPresentation: Equatable, Sendable {
    let sections: [MessageContextMenuSection]

    func action(_ action: MessageContextMenuAction) -> MessageContextMenuActionPresentation? {
        for section in sections {
            if let match = section.actions.first(where: { $0.action == action }) {
                return match
            }
        }
        return nil
    }
}

public enum MessageCommandPresentation {
    enum DirectAction: Hashable {
        case toggleRead
        case toggleFlag
        case archive
        case move
        case delete
    }

    enum DetailContextAction: Hashable {
        case createTask
        case addNote
        case followUp
        case move
    }

    enum DirectActionFeedback: Equatable {
        case impact
        case warning
    }

    public static func readToggleTitle(for header: MessageHeader) -> String {
        header.isRead
            ? String(localized: "Mark as Unread", bundle: .module)
            : String(localized: "Mark as Read", bundle: .module)
    }

    public static func flagToggleTitle(for header: MessageHeader) -> String {
        header.isFlagged
            ? String(localized: "Unflag", bundle: .module)
            : String(localized: "Flag", bundle: .module)
    }

    public static func flagToggleSymbolName(for header: MessageHeader) -> String {
        header.isFlagged ? "flag.slash" : "flag"
    }

    public static func moveFolderCandidates(
        from folders: [Folder],
        currentFolderID: Folder.ID?
    ) -> [Folder] {
        folders.filter { $0.id != currentFolderID }
    }

    static let contextMenuActionInventory: [MessageContextMenuActionInventory] = [
        .init(
            action: .openInNewWindow,
            title: "Open in New Window",
            enabledCondition: "message row has onOpenInNewWindow",
            wiring: .visible(handler: "onOpenInNewWindow", dependency: "macOS auxiliary message window", platforms: "macOS")
        ),
        .init(
            action: .select,
            title: "Select / Deselect",
            enabledCondition: "not applying a row mutation",
            wiring: .visible(handler: "toggleSelection", dependency: "MailNavigationState.bulkSelection", platforms: "macOS, iOS")
        ),
        .init(
            action: .pinToTop,
            title: "Pin to Top / Unpin",
            enabledCondition: "always available",
            wiring: .visible(handler: "togglePinned", dependency: MailPinnedMessages.storageKey, platforms: "macOS, iOS")
        ),
        .init(
            action: .toggleRead,
            title: "Mark as Read / Mark as Unread",
            enabledCondition: "not applying a row mutation",
            wiring: .visible(handler: "setRead / toggleRead", dependency: "MailBackend.setRead", platforms: "macOS, iOS")
        ),
        .init(
            action: .toggleFlag,
            title: "Flag / Unflag",
            enabledCondition: "not applying a row mutation",
            wiring: .visible(handler: "setFlagged / toggleFlag", dependency: "MailBackend.setFlagged", platforms: "macOS, iOS")
        ),
        .init(
            action: .toggleSnooze,
            title: "Snooze / Unsnooze",
            enabledCondition: "not applying a row mutation",
            wiring: .visible(
                handler: "snooze / clearSnooze",
                dependency: "LocalMessageWorkflowStateStorage",
                platforms: "macOS, iOS"
            )
        ),
        .init(
            action: .toggleDone,
            title: "Mark as Done / Mark as Not Done",
            enabledCondition: "not applying a row mutation",
            wiring: .visible(
                handler: "markDone / clearDone",
                dependency: "LocalMessageWorkflowStateStorage",
                platforms: "macOS, iOS"
            )
        ),
        .init(
            action: .reply,
            title: "Reply",
            enabledCondition: "compose actions are available",
            wiring: .visible(
                handler: "MailComposePresentationActions.reply",
                dependency: "compose presentation",
                platforms: "macOS, iOS"
            )
        ),
        .init(
            action: .replyAll,
            title: "Reply All",
            enabledCondition: "compose actions are available",
            wiring: .visible(
                handler: "MailComposePresentationActions.replyAll",
                dependency: "compose presentation",
                platforms: "macOS, iOS"
            )
        ),
        .init(
            action: .forward,
            title: "Forward",
            enabledCondition: "compose actions are available",
            wiring: .visible(
                handler: "MailComposePresentationActions.forward",
                dependency: "compose presentation",
                platforms: "macOS, iOS"
            )
        ),
        .init(
            action: .archive,
            title: "Archive",
            enabledCondition: "archive folder exists",
            wiring: .visible(
                handler: "archiveRow / archive",
                dependency: "MailBackend.move to archive folder",
                platforms: "macOS, iOS"
            )
        ),
        .init(
            action: .move,
            title: "Move",
            enabledCondition: "at least one destination folder exists for the row source",
            wiring: .visible(handler: "MoveToSheet", dependency: "MailBackend.move", platforms: "macOS, iOS")
        ),
        .init(
            action: .copyToFolder,
            title: "Copy to Folder",
            enabledCondition: "at least one destination folder exists for the row source",
            wiring: .visible(handler: "MoveToSheet copy mode", dependency: "MailBackend.copy", platforms: "macOS, iOS")
        ),
        .init(
            action: .copyToLocalFolder,
            title: "Copy to Local Folder",
            enabledCondition: "local backend is present and the row source is not the local account",
            wiring: .visible(
                handler: "LocalFolderDestinationSheet copy mode",
                dependency: "LocalMailBackend.importRaw",
                platforms: "macOS, iOS"
            )
        ),
        .init(
            action: .moveToLocalFolder,
            title: "Move to Local Folder",
            enabledCondition: "local backend is present and the row source is not the local account",
            wiring: .visible(
                handler: "LocalFolderDestinationSheet move mode",
                dependency: "LocalMailBackend.importRaw + undoable source delete",
                platforms: "macOS, iOS"
            )
        ),
        .init(
            action: .setJunk,
            title: "Report Junk / Not Junk",
            enabledCondition: "junk API or spam/inbox fallback folder exists",
            wiring: .visible(
                handler: "setJunk",
                dependency: "MailBackend.setJunk or folder move fallback",
                platforms: "macOS, iOS"
            )
        ),
        .init(
            action: .blockSender,
            title: "Block Sender",
            enabledCondition: "backend advertises blockSender capability",
            wiring: .visible(handler: "blockSender", dependency: "MailBackend.blockSender", platforms: "macOS, iOS")
        ),
        .init(
            action: .delete,
            title: "Delete",
            enabledCondition: "not applying a row mutation",
            wiring: .visible(handler: "deleteRow / delete", dependency: "MailBackend.delete", platforms: "macOS, iOS")
        ),
        .init(
            action: .print,
            title: "Print",
            enabledCondition: "macOS row printing is available",
            wiring: .visible(handler: "printMessage", dependency: "MessagePrintExportRenderer", platforms: "macOS")
        ),
        .init(
            action: .exportPDF,
            title: "Export as PDF",
            enabledCondition: "macOS row printing is available",
            wiring: .visible(handler: "exportMessagePDF", dependency: "MessagePrintExportRenderer", platforms: "macOS")
        ),
        .init(
            action: .saveAs,
            title: "Save As",
            enabledCondition: "macOS raw message source export is available",
            wiring: .visible(
                handler: "saveMessageAsEML",
                dependency: "MailBackend.rawSource + NSSavePanel",
                platforms: "macOS"
            )
        ),
        .init(
            action: .createMeeting,
            title: "Create Meeting from Message",
            enabledCondition: "no other sheet is presented",
            wiring: .visible(
                handler: "MessageEventSheet",
                dependency: "MessageEventDraftBuilder + EventKit calendar",
                platforms: "macOS, iOS"
            )
        ),
        .init(
            action: .createTask,
            title: "Create Task",
            enabledCondition: "no other sheet is presented",
            wiring: .visible(handler: "MessageTaskSheet", dependency: "MessageTaskDraftBuilder", platforms: "macOS, iOS")
        ),
        .init(
            action: .createRule,
            title: "Create Rule from Message",
            enabledCondition: "no other sheet is presented",
            wiring: .visible(
                handler: "LocalRuleEditorSheet",
                dependency: "MessageRuleDraftBuilder + LocalRulesSettings",
                platforms: "macOS, iOS"
            )
        ),
        .init(
            action: .addNote,
            title: "Add Note / Edit Note",
            enabledCondition: "no other sheet is presented",
            wiring: .visible(
                handler: "MessageNoteSheet",
                dependency: "LocalMessageWorkflowStateStorage",
                platforms: "macOS, iOS"
            )
        ),
        .init(
            action: .followUp,
            title: String(localized: "Set Follow-Up Reminder", bundle: .module),
            enabledCondition: "no other sheet is presented",
            wiring: .visible(
                handler: "FollowUpDatePickerView",
                dependency: "FollowUpSettings + local notification",
                platforms: "macOS, iOS"
            )
        ),
        .init(
            action: .downloadOffline,
            title: "Keep Offline",
            enabledCondition: "a source context is available",
            wiring: .visible(
                handler: "toggleKeepOffline",
                dependency: "MessageOfflineRetentionOverrideStore + applyRetention exemption",
                platforms: "macOS, iOS"
            )
        ),
        .init(
            action: .properties,
            title: "Properties",
            enabledCondition: "header metadata is loaded",
            wiring: .visible(handler: "messageProperties sheet", dependency: "MessageHeader", platforms: "macOS, iOS")
        ),
        .init(
            action: .showHeaders,
            title: "Show Headers",
            enabledCondition: "backend raw message source is available",
            wiring: .visible(
                handler: "MessageRawSourceSheet.headersOnly",
                dependency: "MailBackend.rawSource",
                platforms: "macOS, iOS"
            )
        ),
        .init(
            action: .viewSource,
            title: "View Source",
            enabledCondition: "backend raw message source is available",
            wiring: .visible(
                handler: "MessageRawSourceSheet.fullSource",
                dependency: "MailBackend.rawSource",
                platforms: "macOS, iOS"
            )
        ),
    ]

    public static func junkActionTitle(
        currentFolder: Folder?,
        capabilities: BackendCapabilities,
        folders: [Folder]
    ) -> String? {
        let isInSpam = currentFolder?.role == .spam
        let title = isInSpam
            ? String(localized: "Not Junk", bundle: .module)
            : String(localized: "Report Junk", bundle: .module)
        if capabilities.contains(.junkAPI) {
            return title
        }
        return junkFallbackFolder(isJunk: !isInSpam, folders: folders) == nil
            ? nil
            : title
    }

    public static func junkFallbackFolder(
        isJunk: Bool,
        folders: [Folder]
    ) -> Folder? {
        folders.first { $0.role == (isJunk ? .spam : .inbox) }
    }

    static func contextMenu(
        for header: MessageHeader,
        isSelected: Bool,
        isPinned: Bool,
        isSnoozed: Bool,
        isDone: Bool,
        isKeptOffline: Bool = false,
        hasNote: Bool = false,
        canOpenInNewWindow: Bool,
        canArchive: Bool,
        canMove: Bool,
        canCopyToFolder: Bool = false,
        canFileLocally: Bool = false,
        junkActionTitle: String?,
        canBlockSender: Bool,
        canDelete: Bool,
        canCreateTask: Bool = true,
        canCreateRule: Bool = true,
        canCreateMeeting: Bool = true,
        canAddNote: Bool = true,
        canFollowUp: Bool = true,
        hasFollowUp: Bool = false,
        canReply: Bool = true,
        canPrint: Bool = false,
        canExportPDF: Bool = false,
        canShowProperties: Bool = false,
        extendedCapabilities: BackendExtendedCapabilities = [],
        canExportEML: Bool = false
    ) -> MessageContextMenuPresentation {
        messageMenu(
            for: header,
            includesRowActions: true,
            isSelected: isSelected,
            isPinned: isPinned,
            isSnoozed: isSnoozed,
            isDone: isDone,
            isKeptOffline: isKeptOffline,
            hasNote: hasNote,
            canOpenInNewWindow: canOpenInNewWindow,
            canArchive: canArchive,
            canMove: canMove,
            canCopyToFolder: canCopyToFolder,
            canFileLocally: canFileLocally,
            junkActionTitle: junkActionTitle,
            canBlockSender: canBlockSender,
            canDelete: canDelete,
            canCreateTask: canCreateTask,
            canCreateRule: canCreateRule,
            canCreateMeeting: canCreateMeeting,
            canAddNote: canAddNote,
            canFollowUp: canFollowUp,
            hasFollowUp: hasFollowUp,
            canReply: canReply,
            canPrint: canPrint,
            canExportPDF: canExportPDF,
            canShowProperties: canShowProperties,
            extendedCapabilities: extendedCapabilities,
            canExportEML: canExportEML
        )
    }

    /// The reader-surface menu (reader overflow, body context menu, detached
    /// windows): the same capability-gated message inventory as the row context
    /// menu minus row-only actions (`Select`, `Pin to Top`). Every action must
    /// be reachable by the surface that renders it — pass `false` for any
    /// capability with no handler so the item is omitted rather than dead.
    static func readerMenu(
        for header: MessageHeader,
        isSnoozed: Bool,
        isDone: Bool,
        isKeptOffline: Bool = false,
        hasNote: Bool = false,
        canOpenInNewWindow: Bool = false,
        canArchive: Bool,
        canMove: Bool,
        canCopyToFolder: Bool = false,
        canFileLocally: Bool = false,
        junkActionTitle: String?,
        canBlockSender: Bool,
        canDelete: Bool,
        canCreateTask: Bool = true,
        canCreateRule: Bool = true,
        canCreateMeeting: Bool = true,
        canAddNote: Bool = true,
        canFollowUp: Bool = true,
        hasFollowUp: Bool = false,
        canReply: Bool = true,
        canPrint: Bool = false,
        canExportPDF: Bool = false,
        canShowProperties: Bool = false,
        extendedCapabilities: BackendExtendedCapabilities = [],
        canExportEML: Bool = false
    ) -> MessageContextMenuPresentation {
        messageMenu(
            for: header,
            includesRowActions: false,
            isSelected: false,
            isPinned: false,
            isSnoozed: isSnoozed,
            isDone: isDone,
            isKeptOffline: isKeptOffline,
            hasNote: hasNote,
            canOpenInNewWindow: canOpenInNewWindow,
            canArchive: canArchive,
            canMove: canMove,
            canCopyToFolder: canCopyToFolder,
            canFileLocally: canFileLocally,
            junkActionTitle: junkActionTitle,
            canBlockSender: canBlockSender,
            canDelete: canDelete,
            canCreateTask: canCreateTask,
            canCreateRule: canCreateRule,
            canCreateMeeting: canCreateMeeting,
            canAddNote: canAddNote,
            canFollowUp: canFollowUp,
            hasFollowUp: hasFollowUp,
            canReply: canReply,
            canPrint: canPrint,
            canExportPDF: canExportPDF,
            canShowProperties: canShowProperties,
            extendedCapabilities: extendedCapabilities,
            canExportEML: canExportEML
        )
    }

    // swiftlint:disable:next function_parameter_count
    private static func messageMenu(
        for header: MessageHeader,
        includesRowActions: Bool,
        isSelected: Bool,
        isPinned: Bool,
        isSnoozed: Bool,
        isDone: Bool,
        isKeptOffline: Bool,
        hasNote: Bool,
        canOpenInNewWindow: Bool,
        canArchive: Bool,
        canMove: Bool,
        canCopyToFolder: Bool,
        canFileLocally: Bool,
        junkActionTitle: String?,
        canBlockSender: Bool,
        canDelete: Bool,
        canCreateTask: Bool,
        canCreateRule: Bool,
        canCreateMeeting: Bool,
        canAddNote: Bool,
        canFollowUp: Bool,
        hasFollowUp: Bool,
        canReply: Bool,
        canPrint: Bool,
        canExportPDF: Bool,
        canShowProperties: Bool,
        extendedCapabilities: BackendExtendedCapabilities,
        canExportEML: Bool
    ) -> MessageContextMenuPresentation {
        // Capability-driven gates (ADR-0045): actions backed by the message-copy
        // and raw-source seams appear only when the active backend advertises
        // them. Unsupported actions are HIDDEN, not shown disabled — disabling is
        // reserved for "supported but not available in this context" (e.g. Move
        // with no candidate folders). Copy to Folder additionally needs a move
        // target; Save As additionally needs the platform .eml export gate.
        let canCopyToFolder = extendedCapabilities.contains(.messageCopy) && canMove
        let canViewSource = extendedCapabilities.contains(.rawMessageSource)
        let canShowHeaders = extendedCapabilities.contains(.rawMessageSource)
        let canSaveAs = extendedCapabilities.contains(.rawMessageBytes) && canExportEML
        var sections: [MessageContextMenuSection] = []
        appendSection(
            &sections,
            actions: canOpenInNewWindow ? [
                .init(
                    action: .openInNewWindow,
                    title: String(localized: "Open in New Window", bundle: .module),
                    symbolName: "macwindow.on.rectangle"
                )
            ] : []
        )
        if includesRowActions {
            appendSection(
                &sections,
                actions: [
                    .init(
                        action: .select,
                        title: isSelected
                            ? String(localized: "Deselect", bundle: .module)
                            : String(localized: "Select", bundle: .module),
                        symbolName: "checkmark.circle"
                    ),
                    .init(
                        action: .pinToTop,
                        title: isPinned
                            ? String(localized: "Unpin", bundle: .module)
                            : String(localized: "Pin to Top", bundle: .module),
                        symbolName: "pin"
                    )
                ]
            )
        }
        appendSection(
            &sections,
            actions: [
                .init(
                    action: .toggleRead,
                    title: readToggleTitle(for: header),
                    symbolName: header.isRead ? "envelope.badge" : "envelope.open"
                ),
                .init(action: .toggleFlag, title: flagToggleTitle(for: header), symbolName: flagToggleSymbolName(for: header)),
                .init(
                    action: .toggleSnooze,
                    title: isSnoozed
                        ? String(localized: "Unsnooze", bundle: .module)
                        : String(localized: "Snooze…", bundle: .module),
                    symbolName: isSnoozed ? "alarm.waves.left.and.right" : "clock"
                ),
                .init(
                    action: .toggleDone,
                    title: isDone
                        ? String(localized: "Mark as Not Done", bundle: .module)
                        : String(localized: "Mark as Done", bundle: .module),
                    symbolName: isDone ? "checkmark.circle.badge.xmark" : "checkmark.circle"
                )
            ]
        )
        appendSection(
            &sections,
            actions: [
                .init(
                    action: .reply,
                    title: String(localized: "Reply", bundle: .module),
                    symbolName: "arrowshape.turn.up.left",
                    isEnabled: canReply
                ),
                .init(
                    action: .replyAll,
                    title: String(localized: "Reply All", bundle: .module),
                    symbolName: "arrowshape.turn.up.left.2",
                    isEnabled: canReply
                ),
                .init(
                    action: .forward,
                    title: String(localized: "Forward", bundle: .module),
                    symbolName: "arrowshape.turn.up.right",
                    isEnabled: canReply
                )
            ]
        )
        var filingActions: [MessageContextMenuActionPresentation] = []
        if canArchive {
            filingActions.append(.init(
                action: .archive,
                title: String(localized: "Archive", bundle: .module),
                symbolName: "archivebox"
            ))
        }
        filingActions.append(.init(
            action: .move,
            title: String(localized: "Move…", bundle: .module),
            symbolName: "folder",
            isEnabled: canMove
        ))
        if canCopyToFolder {
            filingActions.append(.init(
                action: .copyToFolder,
                title: String(localized: "Copy to Folder…", bundle: .module),
                symbolName: "folder.badge.plus"
            ))
        }
        // ADR-0077 decision 8: local-folder writes run on both platforms.
        if canFileLocally {
            filingActions.append(.init(
                action: .copyToLocalFolder,
                title: String(localized: "Copy to Local Folder…", bundle: .module),
                symbolName: "externaldrive"
            ))
            filingActions.append(.init(
                action: .moveToLocalFolder,
                title: String(localized: "Move to Local Folder…", bundle: .module),
                symbolName: "externaldrive.fill"
            ))
        }
        if let junkActionTitle {
            filingActions.append(.init(action: .setJunk, title: junkActionTitle, symbolName: "xmark.octagon"))
        }
        if canBlockSender {
            filingActions.append(.init(
                action: .blockSender,
                title: String(localized: "Block Sender…", bundle: .module),
                symbolName: "person.crop.circle.badge.xmark",
                role: .destructive
            ))
        }
        if canDelete {
            filingActions.append(.init(
                action: .delete,
                title: String(localized: "Delete", bundle: .module),
                symbolName: "trash",
                role: .destructive
            ))
        }
        appendSection(&sections, actions: filingActions)
        var exportActions: [MessageContextMenuActionPresentation] = []
        // Print/PDF are platform-gated (macOS row surfaces only): an unsupported
        // action is omitted entirely rather than rendered as a dead disabled
        // item — the same honesty rule as the capability gates above.
        if canPrint {
            exportActions.append(.init(
                action: .print,
                title: String(localized: "Print…", bundle: .module),
                symbolName: "printer"
            ))
        }
        if canExportPDF {
            exportActions.append(.init(
                action: .exportPDF,
                title: String(localized: "Export as PDF…", bundle: .module),
                symbolName: "doc.richtext"
            ))
        }
        if canSaveAs {
            exportActions.append(.init(
                action: .saveAs,
                title: String(localized: "Save As…", bundle: .module),
                symbolName: "square.and.arrow.down"
            ))
        }
        exportActions.append(.init(
            action: .downloadOffline,
            title: isKeptOffline
                ? String(localized: "Stop Keeping Offline", bundle: .module)
                : String(localized: "Keep Offline", bundle: .module),
            symbolName: isKeptOffline ? "arrow.down.circle.fill" : "arrow.down.circle"
        ))
        appendSection(&sections, actions: exportActions)
        appendSection(
            &sections,
            actions: [
                .init(
                    action: .createTask,
                    title: String(localized: "Create Task…", bundle: .module),
                    symbolName: "checklist",
                    isEnabled: canCreateTask
                ),
                .init(
                    action: .createRule,
                    title: String(localized: "Create Rule from Message…", bundle: .module),
                    symbolName: "line.3.horizontal.decrease.circle",
                    isEnabled: canCreateRule
                ),
                .init(
                    action: .createMeeting,
                    title: String(localized: "Create Meeting from Message…", bundle: .module),
                    symbolName: "calendar.badge.plus",
                    isEnabled: canCreateMeeting
                ),
                .init(
                    action: .addNote,
                    title: hasNote
                        ? String(localized: "Edit Note…", bundle: .module)
                        : String(localized: "Add Note…", bundle: .module),
                    symbolName: hasNote ? "note.text" : "note.text.badge.plus",
                    isEnabled: canAddNote
                ),
                .init(
                    action: .followUp,
                    title: hasFollowUp
                        ? String(localized: "Change Follow-Up Reminder…", bundle: .module)
                        : String(localized: "Set Follow-Up Reminder…", bundle: .module),
                    symbolName: "flag",
                    isEnabled: canFollowUp
                ),
            ]
        )
        var inspectActions: [MessageContextMenuActionPresentation] = []
        if canShowProperties {
            inspectActions.append(.init(
                action: .properties,
                title: String(localized: "Properties…", bundle: .module),
                symbolName: "info.circle"
            ))
        }
        if canShowHeaders {
            inspectActions.append(.init(
                action: .showHeaders,
                title: String(localized: "Show Headers", bundle: .module),
                symbolName: "list.bullet.rectangle"
            ))
        }
        if canViewSource {
            inspectActions.append(.init(
                action: .viewSource,
                title: String(localized: "View Source", bundle: .module),
                symbolName: "chevron.left.forwardslash.chevron.right"
            ))
        }
        appendSection(&sections, actions: inspectActions)
        return MessageContextMenuPresentation(sections: sections)
    }

    static func feedback(for action: DirectAction) -> DirectActionFeedback {
        switch action {
        case .toggleRead, .toggleFlag, .archive, .move:
            .impact
        case .delete:
            .warning
        }
    }

    static func trailingSwipeActions(hasArchive: Bool) -> [DirectAction] {
        hasArchive ? [.archive, .delete] : [.delete]
    }

    static let leadingSwipeActions: [DirectAction] = [.toggleFlag, .toggleRead]

    static func detailContextActions(
        canPresentSheets: Bool,
        hasMoveTargets: Bool
    ) -> [DetailContextAction] {
        guard canPresentSheets else { return [] }
        var actions: [DetailContextAction] = [.createTask, .addNote, .followUp]
        if hasMoveTargets {
            actions.append(.move)
        }
        return actions
    }

    private static func appendSection(
        _ sections: inout [MessageContextMenuSection],
        actions: [MessageContextMenuActionPresentation]
    ) {
        guard !actions.isEmpty else { return }
        sections.append(MessageContextMenuSection(actions: actions))
    }

    static func mutationErrorStatus(for error: any Error) -> MailRootStatus {
        MailRootStatus(
            message: localizedMessage(for: error, fallback: "Couldn't update message."),
            actionTitle: "Refresh"
        )
    }

    /// Status shown when a mailbox mutation never reports back and the work-block
    /// watchdog had to recover the UI (#192). The action re-syncs so the message
    /// list reflects whatever the server actually applied.
    static func mutationTimeoutStatus() -> MailRootStatus {
        MailRootStatus(
            message: "That action is taking too long. The view has been unblocked — refresh to confirm the result.",
            tone: .warning,
            actionTitle: "Refresh"
        )
    }

    private static func localizedMessage(for error: any Error, fallback: String) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? fallback : message
    }
}
