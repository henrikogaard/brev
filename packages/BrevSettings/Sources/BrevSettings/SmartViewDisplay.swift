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

import Foundation

/// One built-in or custom Smart View in the shared Settings and sidebar order.
public struct SmartViewDisplayEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let symbolName: String
    public let isEnabled: Bool
    public let builtInID: String?
    public let mailbox: SmartMailbox?
}

public extension SmartMailboxSettings {
    /// All entries, including hidden ones, in persisted display order.
    var orderedEntries: [SmartViewDisplayEntry] {
        let builtIns: [(String, String, String)] = [
            ("today", String(localized: "Today", bundle: .module), "calendar"),
            ("flagged", String(localized: "Flagged", bundle: .module), "flag"),
            ("snoozed", String(localized: "Snoozed", bundle: .module), "clock"),
            ("done", String(localized: "Done", bundle: .module), "checkmark.circle"),
            ("vip", String(localized: "VIP", bundle: .module), "star"),
            ("all-attachments", String(localized: "All Attachments", bundle: .module), "paperclip")
        ]
        let entries = builtIns.map { id, title, symbol in
            SmartViewDisplayEntry(id: "builtin:" + id, title: title, symbolName: symbol,
                                  isEnabled: isBuiltInEnabled(id), builtInID: id, mailbox: nil)
        } + mailboxes.map {
            SmartViewDisplayEntry(id: "custom:" + $0.id, title: $0.name,
                                  symbolName: $0.kind == .attachmentSearch ? "paperclip" : "magnifyingglass",
                                  isEnabled: $0.isEnabled, builtInID: nil, mailbox: $0)
        }
        let byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        return (displayOrder + entries.map(\.id)).compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return byID[id]
        }
    }

    /// Changes one entry's visibility without deleting its definition or order.
    mutating func setEntry(_ entry: SmartViewDisplayEntry, isEnabled: Bool) {
        if let builtInID = entry.builtInID {
            setBuiltIn(builtInID, isEnabled: isEnabled)
        } else if var mailbox = entry.mailbox {
            mailbox.isEnabled = isEnabled
            update(mailbox)
        }
    }

    /// Moves a view one row while preserving hidden entries and mixed built-in/custom order.
    mutating func moveEntry(id: String, by offset: Int) {
        var ids = orderedEntries.map(\.id)
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return }
        ids.swapAt(index, index + offset)
        displayOrder = ids
    }
}

extension SmartViewCondition.Field {
    var title: String {
        switch self {
        case .text: return String(localized: "Message preview", bundle: .module)
        case .from: return String(localized: "From", bundle: .module)
        case .recipients: return String(localized: "Any recipient", bundle: .module)
        case .subject: return String(localized: "Subject", bundle: .module)
        case .received: return String(localized: "Date received", bundle: .module)
        case .isRead: return String(localized: "Is read", bundle: .module)
        case .isFlagged: return String(localized: "Is flagged", bundle: .module)
        case .isAnswered: return String(localized: "Is replied to", bundle: .module)
        case .hasAttachments: return String(localized: "Has attachments", bundle: .module)
        case .mailbox: return String(localized: "Mailbox", bundle: .module)
        case .folder: return String(localized: "Folder", bundle: .module)
        }
    }
}

extension SmartViewCondition.Comparison {
    var title: String {
        switch self {
        case .contains: return String(localized: "contains", bundle: .module)
        case .doesNotContain: return String(localized: "does not contain", bundle: .module)
        case .beginsWith: return String(localized: "begins with", bundle: .module)
        case .endsWith: return String(localized: "ends with", bundle: .module)
        case .equals: return String(localized: "is", bundle: .module)
        case .notEquals: return String(localized: "is not", bundle: .module)
        case .isTrue: return String(localized: "yes", bundle: .module)
        case .isFalse: return String(localized: "no", bundle: .module)
        case .before: return String(localized: "before", bundle: .module)
        case .after: return String(localized: "after", bundle: .module)
        case .onDate: return String(localized: "on", bundle: .module)
        case .inLastDays: return String(localized: "in the last", bundle: .module)
        }
    }
}
