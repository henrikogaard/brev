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
/// view never issues provider requests; the only network-adjacent
/// action is the explicit Sync Now toolbar item.
public struct ContactsRootView: View {
    @Environment(\.brevTheme) private var theme

    @State private var model: ContactsBrowsingModel
    @State private var columnVisibility = NavigationSplitViewVisibility
        .automatic
    /// Drives iOS push navigation onto the detail column on selection.
    @State private var preferredCompactColumn = NavigationSplitViewColumn
        .sidebar

    /// - Parameter model: The browsing model; the app shell builds it
    ///   over the session's PIM services.
    public init(model: ContactsBrowsingModel) {
        _model = State(initialValue: model)
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
        .onChange(of: model.selectedContactID) { _, newValue in
            if newValue != nil {
                preferredCompactColumn = .detail
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
                groupNames: groupNames(for: contact)
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
    /// source's discovered collections; unknown keys are dropped.
    private func groupNames(for contact: PIMContact) -> [String] {
        let collections = model.collectionsBySource[contact.sourceID] ?? []
        return contact.groupKeys.compactMap { key in
            collections.first { $0.id == key }?.displayName
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
