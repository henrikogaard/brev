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

import BrevCalendar
import BrevDesign
import BrevThemes
import SwiftUI

/// The shared contact card presented from the sender panel (#10).
///
/// Resolves the contact's source, collection, and group names from the
/// cache so the card shows the same provenance the Contacts surface
/// renders. Edit and Delete go through ContactsEditingModel, gated on
/// canEdit, so a read-only or removed source shows a read-only card.
struct SenderContactDetailSheet: View {
    @Environment(\.brevTheme) private var theme

    let contact: PIMContact
    let actions: MailSenderContactActions
    let onClose: () -> Void
    /// Called after a mutation (edit or delete) so the caller reloads.
    let onChanged: () -> Void
    /// Opens the contact in the full Contacts surface via its
    /// brev://contact deep link (#10); nil hides the action.
    let onOpenInContacts: (() -> Void)?

    @State private var source: PIMSource?
    @State private var collection: PIMCollection?
    @State private var groupNames: [String] = []
    @State private var isEditing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ContactDetailView(
                contact: contact,
                collection: collection,
                source: source,
                groupNames: groupNames,
                onEdit: actions.canEdit(contact) ? { isEditing = true } : nil,
                onDelete: actions.canEdit(contact)
                    ? { Task { await delete() } }
                    : nil
            )
            .navigationTitle(
                String(localized: "Contact", bundle: .module)
            )
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done", bundle: .module)) {
                        onClose()
                    }
                }
                if let onOpenInContacts {
                    ToolbarItem(placement: .primaryAction) {
                        Button(
                            String(
                                localized: "Open in Contacts",
                                bundle: .module
                            )
                        ) {
                            onOpenInContacts()
                        }
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let errorMessage {
                    Text(errorMessage)
                        .brevFont(.caption)
                        .foregroundStyle(theme.danger.color)
                        .padding(BrevSpacing.sm)
                }
            }
        }
        .task { await loadProvenance() }
        .sheet(isPresented: $isEditing) {
            if let editing = actions.editing {
                ContactEditorView(
                    editing: editing,
                    contact: contact,
                    source: source,
                    onSaved: { onChanged() }
                )
            }
        }
    }

    private func loadProvenance() async {
        source = await actions.source(for: contact)
        collection = await actions.collection(for: contact)
        groupNames = await actions.groupNames(for: contact)
    }

    private func delete() async {
        guard let editing = actions.editing else { return }
        do {
            try await editing.delete(contact)
            onChanged()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}
