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

struct SavedSearchEditorPresentation: Equatable, Sendable {
    var name = ""
    var kind: SmartMailboxKind
    var queryText = ""
    var fromText = ""
    var isEnabled = true
    var conditions: [SmartViewCondition] = [.init()]
    var matchMode: SmartViewMatchMode = .all
    var includeTrash = false
    var includeSent = false
    var folderID: String?

    private var editingID: SmartMailbox.ID?

    init(kind: SmartMailboxKind) {
        self.kind = kind
    }

    init(editing mailbox: SmartMailbox) {
        name = mailbox.name
        kind = mailbox.kind
        queryText = mailbox.query.text
        fromText = mailbox.query.from ?? ""
        editingID = mailbox.id
        isEnabled = mailbox.isEnabled
        conditions = mailbox.query.editableConditions
        matchMode = mailbox.query.matchMode ?? .all
        includeTrash = mailbox.query.includeTrash ?? true
        includeSent = mailbox.query.includeSent ?? true
        folderID = mailbox.query.folderID
    }

    var isValid: Bool {
        !trimmed(name).isEmpty && (kind == .attachmentSearch
            || (!conditions.isEmpty && conditions.allSatisfy(\.isValid)))
    }

    func makeSmartMailbox() -> SmartMailbox {
        SmartMailbox(
            id: editingID ?? UUID().uuidString,
            name: trimmed(name),
            kind: kind,
            query: SmartMailbox.SavedQuery(
                text: kind == .attachmentSearch ? trimmed(queryText) : "",
                from: kind == .attachmentSearch ? nilIfEmpty(fromText) : nil,
                to: nil,
                hasAttachment: kind == .attachmentSearch ? true : nil,
                isUnread: nil,
                isStarred: nil,
                folderID: kind == .attachmentSearch ? folderID : nil,
                conditions: kind == .messageSearch ? conditions : nil,
                matchMode: kind == .messageSearch ? matchMode : nil,
                includeTrash: kind == .messageSearch ? includeTrash : nil,
                includeSent: kind == .messageSearch ? includeSent : nil
            ),
            isEnabled: isEnabled
        )
    }

    private func nilIfEmpty(_ value: String) -> String? {
        let trimmedValue = trimmed(value)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
