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
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A drag payload carrying one or more message IDs with optional source context.
///
/// Used when dragging messages from `MessageListView` onto folder rows in
/// `FolderSidebar`. When a bulk selection is active, all selected IDs are
/// bundled into a single drag gesture. When a single message is dragged
/// the `ids` array contains exactly one element.
struct DraggableMessageID: Transferable, Codable, Sendable, Hashable {
    // swiftlint:disable:next force_unwrapping
    static let contentType = UTType(exportedAs: "io.brev.draggable-message-ids.v1")

    /// One or more message IDs to move.
    let ids: [String]

    /// The source account context, present when the drag originates from a
    /// source-scoped list (multi-mailbox unified inbox view).
    let sourceID: MailSourceID?

    init(ids: [String], sourceID: MailSourceID? = nil) {
        self.ids = ids
        self.sourceID = sourceID
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: contentType)
    }
}

// MARK: - Search scope

/// Scope filter applied on top of the free-text search query.
///
/// Displayed as horizontally-scrolling chip buttons below the search
/// field when the user has entered search text.
enum SearchScope: String, CaseIterable, Identifiable {
    case all
    case from
    case subject
    case hasAttachment
    case unread

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .from: return "From"
        case .subject: return "Subject"
        case .hasAttachment: return "Attachment"
        case .unread: return "Unread"
        }
    }

    var symbolName: String {
        switch self {
        case .all: return "magnifyingglass"
        case .from: return "person"
        case .subject: return "text.alignleft"
        case .hasAttachment: return "paperclip"
        case .unread: return "envelope.badge"
        }
    }
}

extension SearchExecution {
    var messageListTitle: String {
        switch self {
        case .cacheOnly:
            return "Local"
        case .cacheThenServer:
            return "Auto"
        case .serverOnly:
            return "Server"
        }
    }

    var messageListSymbolName: String {
        switch self {
        case .cacheOnly:
            return "internaldrive"
        case .cacheThenServer:
            return "arrow.triangle.2.circlepath"
        case .serverOnly:
            return "network"
        }
    }
}
