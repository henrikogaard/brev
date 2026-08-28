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

import BrevDesign
import BrevSettings
import BrevThemes
import SwiftUI

/// A sheet form for creating, editing, and deleting saved search mailboxes.
struct SavedSearchEditorView: View {
    @Environment(\.brevTheme) private var theme
    @State private var presentation: SavedSearchEditorPresentation

    private let editingID: SmartMailbox.ID?
    private let onFinished: () -> Void

    init(editing: SmartMailbox? = nil, onFinished: @escaping () -> Void) {
        if let editing {
            _presentation = State(initialValue: SavedSearchEditorPresentation(editing: editing))
            editingID = editing.id
        } else {
            _presentation = State(initialValue: SavedSearchEditorPresentation(kind: .messageSearch))
            editingID = nil
        }
        self.onFinished = onFinished
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Smart View", bundle: .module)) {
                    TextField(String(localized: "Name", bundle: .module), text: $presentation.name)

                    Picker(String(localized: "Kind", bundle: .module), selection: $presentation.kind) {
                        Text("Messages", bundle: .module).tag(SmartMailboxKind.messageSearch)
                        Text("Attachments", bundle: .module).tag(SmartMailboxKind.attachmentSearch)
                    }

                    Toggle(
                        String(localized: "Show in sidebar", bundle: .module),
                        isOn: $presentation.isEnabled
                    )
                }

                Section(String(localized: "Predicates", bundle: .module)) {
                    TextField(String(localized: "Query", bundle: .module), text: $presentation.queryText)
                    TextField(String(localized: "From", bundle: .module), text: $presentation.fromText)
                    if presentation.kind == .messageSearch {
                        TextField(String(localized: "To", bundle: .module), text: $presentation.toText)
                        Toggle(
                            String(localized: "Unread only", bundle: .module),
                            isOn: $presentation.isUnread
                        )
                        Toggle(
                            String(localized: "Starred only", bundle: .module),
                            isOn: $presentation.isStarred
                        )
                        Toggle(
                            String(localized: "Has attachments", bundle: .module),
                            isOn: $presentation.hasAttachment
                        )
                    }
                }

                if editingID != nil {
                    Section {
                        Button(String(localized: "Delete Smart View", bundle: .module), role: .destructive) {
                            delete()
                        }
                    }
                }
            }
            .background(theme.bgPrimary.color)
            .navigationTitle(
                editingID == nil
                    ? String(localized: "New Smart View", bundle: .module)
                    : String(localized: "Edit Smart View", bundle: .module)
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", bundle: .module)) {
                        onFinished()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save", bundle: .module)) {
                        save()
                    }
                    .disabled(!presentation.isValid)
                }
            }
        }
    }

    private func save() {
        var settings = SmartMailboxSettings.load()
        let mailbox = presentation.makeSmartMailbox()
        if editingID == nil {
            settings.add(mailbox)
        } else {
            settings.update(mailbox)
        }
        settings.save()
        onFinished()
    }

    private func delete() {
        guard let editingID else { return }
        var settings = SmartMailboxSettings.load()
        settings.remove(id: editingID)
        settings.save()
        onFinished()
    }
}
