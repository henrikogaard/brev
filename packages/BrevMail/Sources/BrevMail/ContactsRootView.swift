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

/// The Contacts browsing surface (ADR-0072, issue #8).
///
/// A two-column split: the alphabetically-sectioned contact list
/// (searchable, group-filterable) on the leading side and the read-only
/// contact detail on the trailing side. On iOS the split collapses into
/// push navigation. All content comes from the local sync cache — the
/// view never issues provider requests on its own; the only
/// provider-adjacent actions are the explicit Sync Now toolbar item
/// and, when an editing model is wired (issue #9), the New Contact /
/// Edit / Delete affordances that run through ContactsEditingModel.
public struct ContactsRootView: View {
    @Environment(\.brevTheme) private var theme

    @State private var model: ContactsBrowsingModel
    /// Contact authoring; nil keeps the surface read-only.
    private let editing: ContactsEditingModel?
    @State private var columnVisibility = NavigationSplitViewVisibility
        .automatic
    /// Drives iOS push navigation onto the detail column on selection.
    @State private var preferredCompactColumn = NavigationSplitViewColumn
        .sidebar
    /// The sheet request: a new contact, or an edit of the cached one.
    @State private var editorRequest: EditorRequest?

    /// Identifiable sheet payload for the contact editor.
    private enum EditorRequest: Identifiable {
        case create
        case edit(PIMContact)

        var id: String {
            switch self {
            case .create: "create"
            case .edit(let contact): "edit-\(contact.id)"
            }
        }
    }

    /// - Parameter model: The browsing model; the app shell builds it
    ///   over the session's PIM services.
    /// - Parameter editing: The authoring model; pass nil (default) for
    ///   a read-only contacts list.
    public init(
        model: ContactsBrowsingModel,
        editing: ContactsEditingModel? = nil
    ) {
        _model = State(initialValue: model)
        self.editing = editing
    }

    public var body: some View {
        NavigationSplitView(
            columnVisibility: $columnVisibility,
            preferredCompactColumn: $preferredCompactColumn
        ) {
            listColumn
                .navigationTitle(
                    String(localized: "Contacts", bundle: .module)
                )
        } detail: {
            detailColumn
        }
        .searchable(
            text: Bindable(model).searchText,
            prompt: String(
                localized: "Search contacts",
                bundle: .module
            )
        )
        .task { await model.load() }
        .task { await editing?.load() }
        .onChange(of: model.selectedContactID) { _, newValue in
            if newValue != nil {
                preferredCompactColumn = .detail
            }
        }
        .sheet(item: $editorRequest) { request in
            if let editing {
                editorSheet(for: request, editing: editing)
            }
        }
    }

    // MARK: - List column

    private var listColumn: some View {
        VStack(spacing: 0) {
            if !model.staleSources.isEmpty {
                staleBanner
            }
            if let lastError = model.lastError {
                errorBanner(lastError)
            }
            if let lastError = editing?.lastError {
                errorBanner(lastError)
            }
            if let deepLinkNotice = model.deepLinkNotice {
                errorBanner(deepLinkNotice)
            }
            content
        }
        .toolbar { toolbarContent }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading, model.contacts.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(
                    String(localized: "Loading contacts", bundle: .module)
                )
        } else if !model.hasSources {
            emptyState(
                symbol: "person.crop.circle.badge.plus",
                title: String(
                    localized: "No contacts sources connected",
                    bundle: .module
                ),
                message: String(
                    localized:
                    "Connect a contacts source in Settings → Calendar & Contacts to see people here.",
                    bundle: .module
                )
            )
        } else if model.sections.isEmpty {
            emptyState(
                symbol: "person.crop.circle",
                title: String(
                    localized: "No contacts",
                    bundle: .module
                ),
                message: model.searchText.isEmpty
                    ? String(
                        localized:
                        "Synced contacts will appear here. Use Sync Now to refresh the cache.",
                        bundle: .module
                    )
                    : String(
                        localized: "No contacts match your search.",
                        bundle: .module
                    )
            )
        } else {
            ContactsListView(
                sections: model.sections,
                selectedContactID: Bindable(model).selectedContactID
            )
        }
    }

    // MARK: - Detail column

    @ViewBuilder
    private var detailColumn: some View {
        if let contact = model.contact(id: model.selectedContactID) {
            ContactDetailView(
                contact: contact,
                collection: model.collection(for: contact),
                source: model.source(for: contact),
                groupNames: groupNames(for: contact),
                onEdit: editAction(for: contact),
                onDelete: deleteAction(for: contact)
            )
        } else {
            ContentUnavailableView(
                String(localized: "No contact selected", bundle: .module),
                systemImage: "person.crop.circle",
                description: Text(String(
                    localized: "Pick a contact from the list.",
                    bundle: .module
                ))
            )
            .foregroundStyle(theme.textSecondary.color)
        }
    }

    /// Resolves a contact's group keys to display names from the
    /// source's discovered collections; unknown keys are dropped. Keys
    /// are provider keys (Google resourceNames, CardDAV CATEGORIES), so
    /// the match is on providerKey, not the composite collection id.
    private func groupNames(for contact: PIMContact) -> [String] {
        let collections = model.collectionsBySource[contact.sourceID] ?? []
        return contact.groupKeys.compactMap { key in
            collections.first { $0.providerKey == key }?.displayName
        }
    }

    /// The Edit action for the detail pane — present only while the
    /// contact's source is writable.
    private func editAction(for contact: PIMContact) -> (() -> Void)? {
        guard let editing, editing.canEdit(contact) else { return nil }
        return {
            Task { await presentEditor(for: contact) }
        }
    }

    /// The Delete action for the detail pane — same writability gate.
    private func deleteAction(for contact: PIMContact) -> (() -> Void)? {
        guard let editing, editing.canEdit(contact) else { return nil }
        return {
            Task { await delete(contact) }
        }
    }

    /// Refreshes writable targets before presenting so the picker never
    /// offers a stale (or misses a newly enabled) address book.
    private func presentEditor(for contact: PIMContact) async {
        await editing?.load()
        editorRequest = .edit(contact)
    }

    private func presentNewContact() async {
        await editing?.load()
        editorRequest = .create
    }

    private func delete(_ contact: PIMContact) async {
        do {
            try await editing?.delete(contact)
            model.selectedContactID = nil
            await model.load()
        } catch {
            // The editing model carries the displayable error.
        }
    }

    @ViewBuilder
    private func editorSheet(
        for request: EditorRequest,
        editing: ContactsEditingModel
    ) -> some View {
        let onSaved: () async -> Void = {
            await editing.load()
            await model.load()
        }
        switch request {
        case .create:
            ContactEditorView(
                editing: editing,
                source: editing.defaultTarget?.source,
                onSaved: onSaved
            )
        case .edit(let contact):
            ContactEditorView(
                editing: editing,
                contact: contact,
                source: model.source(for: contact),
                onSaved: onSaved
            )
        }
    }

    // MARK: - Banners

    /// Kept-cache warning: a failed/disconnected/auth-required source
    /// still renders its last snapshot, flagged so the data's age is
    /// never ambiguous (ADR-0072 staleness contract).
    private var staleBanner: some View {
        HStack(spacing: BrevSpacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                Text(String(
                    localized: "Showing cached data",
                    bundle: .module
                ))
                .brevFont(.subheadline)
                if let lastSyncAt = model.lastSyncAt {
                    Text(String(
                        localized:
                        "Last updated \(lastSyncAt.formatted(.relative(presentation: .named)))",
                        bundle: .module
                    ))
                    .brevFont(.caption)
                }
            }
            Spacer(minLength: BrevSpacing.sm)
        }
        .foregroundStyle(theme.warning.color)
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.sm)
        .background(theme.bgSecondary.color)
        .accessibilityElement(children: .combine)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: BrevSpacing.sm) {
            Image(systemName: "exclamationmark.circle")
                .accessibilityHidden(true)
            Text(message)
                .brevFont(.caption)
            Spacer(minLength: BrevSpacing.sm)
        }
        .foregroundStyle(theme.danger.color)
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.sm)
        .background(theme.bgSecondary.color)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Empty state + toolbar

    private func emptyState(
        symbol: String,
        title: String,
        message: String
    ) -> some View {
        ContentUnavailableView(
            title,
            systemImage: symbol,
            description: Text(message)
        )
        .foregroundStyle(theme.textSecondary.color)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !model.allCollections.isEmpty {
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Button {
                        model.selectedCollectionID = nil
                    } label: {
                        if model.selectedCollectionID == nil {
                            Label(
                                String(
                                    localized: "All contacts",
                                    bundle: .module
                                ),
                                systemImage: "checkmark"
                            )
                        } else {
                            Text(String(
                                localized: "All contacts",
                                bundle: .module
                            ))
                        }
                    }
                    ForEach(model.allCollections) { collection in
                        Button {
                            model.selectedCollectionID = collection.id
                        } label: {
                            if model.selectedCollectionID == collection.id {
                                Label(
                                    collection.displayName,
                                    systemImage: "checkmark"
                                )
                            } else {
                                Text(collection.displayName)
                            }
                        }
                    }
                } label: {
                    Label(
                        String(localized: "Filter", bundle: .module),
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                }
                .accessibilityLabel(
                    String(
                        localized: "Filter by group",
                        bundle: .module
                    )
                )
            }
        }
        if let editing,
           editing.canAuthor, editing.defaultTarget != nil {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await presentNewContact() }
                } label: {
                    Label(
                        String(
                            localized: "New Contact",
                            bundle: .module
                        ),
                        systemImage: "plus"
                    )
                }
                .accessibilityLabel(
                    String(localized: "New contact", bundle: .module)
                )
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await model.syncAll() }
            } label: {
                if model.syncingSourceIDs.isEmpty {
                    Label(
                        String(localized: "Sync Now", bundle: .module),
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .disabled(!model.canSyncAny)
            .accessibilityLabel(
                String(localized: "Sync contacts now", bundle: .module)
            )
        }
    }
}
