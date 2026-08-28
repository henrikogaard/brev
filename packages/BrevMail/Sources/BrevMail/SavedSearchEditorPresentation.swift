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

import BrevSettings
import Foundation

struct SavedSearchEditorPresentation: Equatable, Sendable {
    var name = ""
    var kind: SmartMailboxKind
    var queryText = ""
    var fromText = ""
    var toText = ""
    var hasAttachment = false
    var isUnread = false
    var isStarred = false
    var isEnabled = true

    private var editingID: SmartMailbox.ID?

    init(kind: SmartMailboxKind) {
        self.kind = kind
    }

    init(editing mailbox: SmartMailbox) {
        name = mailbox.name
        kind = mailbox.kind
        queryText = mailbox.query.text
        fromText = mailbox.query.from ?? ""
        toText = mailbox.query.to ?? ""
        hasAttachment = mailbox.query.hasAttachment == true
        isUnread = mailbox.query.isUnread == true
        isStarred = mailbox.query.isStarred == true
        editingID = mailbox.id
        isEnabled = mailbox.isEnabled
    }

    var isValid: Bool {
        let hasTextPredicate = [queryText, fromText, toText].contains { !trimmed($0).isEmpty }
        let hasTogglePredicate = hasAttachment || isUnread || isStarred
        return !trimmed(name).isEmpty
            && (kind == .attachmentSearch || hasTextPredicate || hasTogglePredicate)
    }

    func makeSmartMailbox() -> SmartMailbox {
        SmartMailbox(
            id: editingID ?? UUID().uuidString,
            name: trimmed(name),
            kind: kind,
            query: SmartMailbox.SavedQuery(
                text: trimmed(queryText),
                from: nilIfEmpty(fromText),
                to: kind == .messageSearch ? nilIfEmpty(toText) : nil,
                hasAttachment: kind == .attachmentSearch || hasAttachment ? true : nil,
                isUnread: kind == .messageSearch && isUnread ? true : nil,
                isStarred: kind == .messageSearch && isStarred ? true : nil
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
