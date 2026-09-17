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
@testable import BrevSettings
import Foundation
import Testing

@Suite("Saved Search editor")
struct SavedSearchEditorPresentationTests {
    @Test("editing preserves legacy false filters, folder scope, identity and visibility")
    func legacyEdit() {
        let existing = SmartMailbox(id: "old", name: "Old", query: .init(
            text: "project", from: "boss", isUnread: false, isStarred: false, folderID: "sent"
        ), isEnabled: false)
        var editor = SavedSearchEditorPresentation(editing: existing)
        editor.name = "  Renamed  "
        let saved = editor.makeSmartMailbox()
        #expect(saved.id == existing.id)
        #expect(saved.name == "Renamed")
        #expect(!saved.isEnabled)
        #expect(saved.query.conditions?.count == 5)
        #expect(saved.query.includeSent == true)
        #expect(saved.query.conditions?.contains { $0.field == .folder && $0.value == "sent" } == true)
        #expect(saved.query.conditions?.contains { $0.field == .isRead && $0.comparison == .isTrue } == true)
        #expect(saved.query.conditions?.contains { $0.field == .isFlagged && $0.comparison == .isFalse } == true)
    }

    @Test("new views require a name and every condition to be complete")
    func validation() {
        var editor = SavedSearchEditorPresentation(kind: .messageSearch)
        editor.name = "Projects"
        #expect(!editor.isValid)
        editor.conditions[0].value = "boss"
        #expect(editor.isValid)
        editor.conditions.append(.init(field: .received, comparison: .inLastDays, value: "0"))
        #expect(!editor.isValid)
        editor.conditions[1].value = "7"
        #expect(editor.isValid)
        editor.conditions = []
        #expect(!editor.isValid)
    }

    @Test("attachment editor retains its supported query and folder without message conditions")
    func attachmentScope() {
        let existing = SmartMailbox(id: "files", name: "Files", kind: .attachmentSearch,
                                    query: .init(text: "invoice", from: "billing", folderID: "archive"), isEnabled: true)
        let saved = SavedSearchEditorPresentation(editing: existing).makeSmartMailbox()
        #expect(saved.query.text == "invoice")
        #expect(saved.query.from == "billing")
        #expect(saved.query.folderID == "archive")
        #expect(saved.query.hasAttachment == true)
        #expect(saved.query.conditions == nil)
    }
}
