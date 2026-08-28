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

enum MessageAttachmentActionKind: Equatable, Sendable, Hashable {
    case preview
    case save
    case open
}

struct MessageAttachmentActionPresentation: Equatable, Sendable, Identifiable {
    let kind: MessageAttachmentActionKind
    let title: String
    let systemImage: String
    let isDisabled: Bool

    var id: MessageAttachmentActionKind { kind }

    static func actions(
        resourceAvailable: Bool,
        isDownloading: Bool,
        isWorkBlocked: Bool
    ) -> [MessageAttachmentActionPresentation] {
        let isDisabled = !resourceAvailable || isDownloading || isWorkBlocked
        return [
            MessageAttachmentActionPresentation(
                kind: .preview,
                title: "Preview",
                systemImage: "eye",
                isDisabled: isDisabled
            ),
            MessageAttachmentActionPresentation(
                kind: .save,
                title: "Save",
                systemImage: "arrow.down.circle",
                isDisabled: isDisabled
            ),
            MessageAttachmentActionPresentation(
                kind: .open,
                title: "Open",
                systemImage: "arrow.up.forward",
                isDisabled: isDisabled
            )
        ]
    }

    /// Returns the inline action that makes attachment preview immediately discoverable.
    static func primaryAction(
        in actions: [MessageAttachmentActionPresentation]
    ) -> MessageAttachmentActionPresentation? {
        actions.first { $0.kind == .preview }
    }

    /// Returns file-management actions presented from the compact overflow menu.
    static func overflowActions(
        in actions: [MessageAttachmentActionPresentation]
    ) -> [MessageAttachmentActionPresentation] {
        actions.filter { $0.kind != .preview }
    }
}
