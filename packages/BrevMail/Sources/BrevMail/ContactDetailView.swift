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
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Read-only detail pane for one cached contact (ADR-0072).
///
/// Shows every field the shared model carries: monogram or photo, name,
/// nickname, job title and organization, labeled emails/phones/URLs/
/// addresses/dates, note, and group memberships. Source and collection
/// provenance close the pane so ownership stays visible. Photos render
/// only when Brev holds the bytes — remote photoURLs stay unfetched
/// (ADR-0006) and fall back to the monogram. When the parent supplies
/// edit or delete actions (writable source, issue #9) an action row
/// appears under the header; the delete confirmation names the provider
/// impact so remote deletion is never mistaken for a local cache clear.
/// Duplicate suggestions, when supplied, are review-only — each row
/// navigates to the candidate and nothing ever merges automatically.
public struct ContactDetailView: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.openURL) private var openURL

    let contact: PIMContact
    let collection: PIMCollection?
    let source: PIMSource?
    /// Group display names the contact belongs to (resolved by the
    /// caller from the source's collections).
    let groupNames: [String]
    /// Opens the editor for this contact; nil hides the Edit action.
    let onEdit: (() -> Void)?
    /// Deletes the contact remotely and from the cache; nil hides the
    /// Delete action.
    let onDelete: (() -> Void)?
    /// Review-first duplicate suggestions; empty hides the section.
    let duplicates: [ContactDuplicateSuggestions.Candidate]
    /// Opens a suggested candidate for review; nil keeps rows read-only.
    let onReviewDuplicate: ((PIMContact) -> Void)?

    @State private var showsDeleteConfirmation = false

    public init(
        contact: PIMContact,
        collection: PIMCollection? = nil,
        source: PIMSource? = nil,
        groupNames: [String] = [],
        onEdit: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        duplicates: [ContactDuplicateSuggestions.Candidate] = [],
        onReviewDuplicate: ((PIMContact) -> Void)? = nil
    ) {
        self.contact = contact
        self.collection = collection
        self.source = source
        self.groupNames = groupNames
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.duplicates = duplicates
        self.onReviewDuplicate = onReviewDuplicate
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrevSpacing.lg) {
                header
                if onEdit != nil || onDelete != nil || deepLinkURL != nil {
                    actionRow
                }
                if !contact.emails.isEmpty {
                    detailSection(
                        title: String(localized: "Email", bundle: .module),
                        symbol: "envelope"
                    ) {
                        ForEach(
                            Array(contact.emails.enumerated()),
                            id: \.offset
                        ) { _, field in
                            VStack(
                                alignment: .leading,
                                spacing: BrevSpacing.xxs
                            ) {
                                if let url = URL(
                                    string: "mailto:\(field.value)"
                                ) {
                                    Button {
                                        openURL(url)
                                    } label: {
                                        Text(field.value)
                                            .brevFont(.body)
                                            .foregroundStyle(
                                                theme.accent.color
                                            )
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    fieldText(field.value)
                                }
                                fieldLabel(
                                    field.label,
                                    fallback: String(
                                        localized: "Email",
                                        bundle: .module
                                    )
                                )
                            }
                        }
                    }
                }
                if !contact.phones.isEmpty {
                    detailSection(
                        title: String(localized: "Phone", bundle: .module),
                        symbol: "phone"
                    ) {
                        ForEach(
                            Array(contact.phones.enumerated()),
                            id: \.offset
                        ) { _, field in
                            VStack(
                                alignment: .leading,
                                spacing: BrevSpacing.xxs
                            ) {
                                fieldText(field.value)
                                fieldLabel(
                                    field.label,
                                    fallback: String(
                                        localized: "Phone",
                                        bundle: .module
                                    )
                                )
                            }
                        }
                    }
                }
                if !contact.urls.isEmpty {
                    urlsSection
                }
                if !contact.dates.isEmpty {
                    datesSection
                }
                if !contact.addresses.isEmpty {
                    addressesSection
                }
                if let note = contact.note, !note.isEmpty {
                    detailSection(
                        title: String(localized: "Notes", bundle: .module),
                        symbol: "text.alignleft"
                    ) {
                        Text(note)
                            .brevFont(.body)
                            .foregroundStyle(theme.textPrimary.color)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if !groupNames.isEmpty {
                    detailSection(
                        title: String(localized: "Groups", bundle: .module),
                        symbol: "person.3"
                    ) {
                        Text(groupNames.joined(separator: ", "))
                            .brevFont(.body)
                            .foregroundStyle(theme.textPrimary.color)
                    }
                }
                if !duplicates.isEmpty {
                    duplicatesSection
                }
                provenanceFooter
            }
            .padding(BrevSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.bgPrimary.color)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            String(localized: "Contact details", bundle: .module)
        )
        .confirmationDialog(
            String(localized: "Delete this contact?", bundle: .module),
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                String(localized: "Delete Contact", bundle: .module),
                role: .destructive
            ) {
                onDelete?()
            }
            Button(
                String(localized: "Cancel", bundle: .module),
                role: .cancel
            ) {}
        } message: {
            Text(String(
                localized:
                "This permanently deletes the contact from \(source?.displayName ?? String(localized: "the provider", bundle: .module)) and removes it from the local cache.",
                bundle: .module
            ))
        }
    }

    // MARK: - Actions

    /// Edit/Delete affordances for writable sources — plain buttons so
    /// the row reads as inline text actions, not chrome.
    private var actionRow: some View {
        HStack(spacing: BrevSpacing.lg) {
            if let onEdit {
                Button {
                    onEdit()
                } label: {
                    Label(
                        String(localized: "Edit", bundle: .module),
                        systemImage: "pencil"
                    )
                    .brevFont(.subheadline)
                    .foregroundStyle(theme.accent.color)
                }
                .buttonStyle(.plain)
            }
            if onDelete != nil {
                Button(role: .destructive) {
                    showsDeleteConfirmation = true
                } label: {
                    Label(
                        String(localized: "Delete", bundle: .module),
                        systemImage: "trash"
                    )
                    .brevFont(.subheadline)
                    .foregroundStyle(theme.danger.color)
                }
                .buttonStyle(.plain)
            }
            if let deepLinkURL {
                Button {
                    PIMDeepLinkCopy.copy(deepLinkURL)
                } label: {
                    Label(
                        String(localized: "Copy Link", bundle: .module),
                        systemImage: "link"
                    )
                    .brevFont(.subheadline)
                    .foregroundStyle(theme.accent.color)
                }
                .buttonStyle(.plain)
                .accessibilityHint(
                    String(
                        localized: "Copies a link that reopens this contact in Brev",
                        bundle: .module
                    )
                )
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// The brev:// link that reopens this cached contact (#10).
    private var deepLinkURL: URL? {
        PIMDeepLinkPolicy.url(forContactID: contact.id)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: BrevSpacing.md) {
            if let data = contact.photoData,
               let image = photoImage(data) {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
                    .accessibilityHidden(true)
            } else {
                Text(ContactPresentation.initials(for: contact))
                    .brevFont(.title)
                    .foregroundStyle(theme.bgPrimary.color)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(theme.accentMuted.color))
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                Text(contact.displayName)
                    .brevFont(.title)
                    .foregroundStyle(theme.textPrimary.color)
                if let nickname = contact.nickname, !nickname.isEmpty {
                    Text(String(
                        localized: "\u{201C}\(nickname)\u{201D}",
                        bundle: .module
                    ))
                    .brevFont(.callout)
                    .foregroundStyle(theme.textSecondary.color)
                }
                if let subtitle = ContactPresentation.subtitle(
                    for: contact
                ) {
                    Text(subtitle)
                        .brevFont(.callout)
                        .foregroundStyle(theme.textSecondary.color)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Field sections

    private func fieldLabel(_ label: String?, fallback: String) -> some View {
        Text(ContactPresentation.fieldLabel(label, fallback: fallback))
            .brevFont(.caption)
            .foregroundStyle(theme.textTertiary.color)
    }

    private var addressesSection: some View {
        detailSection(
            title: String(localized: "Addresses", bundle: .module),
            symbol: "mappin"
        ) {
            ForEach(
                Array(contact.addresses.enumerated()),
                id: \.offset
            ) { _, address in
                VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                    Text(ContactPresentation.addressText(for: address))
                        .brevFont(.body)
                        .foregroundStyle(theme.textPrimary.color)
                    fieldLabel(
                        address.label,
                        fallback: String(
                            localized: "Address",
                            bundle: .module
                        )
                    )
                }
            }
        }
    }

    private func fieldText(_ value: String) -> some View {
        Text(value)
            .brevFont(.body)
            .foregroundStyle(theme.textPrimary.color)
            .textSelection(.enabled)
    }

    /// Labeled URLs — tapping opens the link via the system.
    private var urlsSection: some View {
        detailSection(
            title: String(localized: "URLs", bundle: .module),
            symbol: "link"
        ) {
            ForEach(
                Array(contact.urls.enumerated()),
                id: \.offset
            ) { _, field in
                VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                    if let url = URL(string: field.value),
                       url.scheme?.hasPrefix("http") == true {
                        Button {
                            openURL(url)
                        } label: {
                            Text(field.value)
                                .brevFont(.body)
                                .foregroundStyle(theme.accent.color)
                        }
                        .buttonStyle(.plain)
                    } else {
                        fieldText(field.value)
                    }
                    fieldLabel(
                        field.label,
                        fallback: String(
                            localized: "URL",
                            bundle: .module
                        )
                    )
                }
            }
        }
    }

    /// Labeled dates — birthday/anniversary/custom rendered locally.
    private var datesSection: some View {
        detailSection(
            title: String(localized: "Dates", bundle: .module),
            symbol: "calendar"
        ) {
            ForEach(
                Array(contact.dates.enumerated()),
                id: \.offset
            ) { _, date in
                VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                    fieldText(ContactPresentation.dateText(for: date))
                    fieldLabel(
                        date.label,
                        fallback: String(
                            localized: "Birthday",
                            bundle: .module
                        )
                    )
                }
            }
        }
    }

    /// Review-first duplicate suggestions — a candidate row opens the
    /// other record so the user compares; nothing merges itself.
    private var duplicatesSection: some View {
        detailSection(
            title: String(
                localized: "Possible Duplicates",
                bundle: .module
            ),
            symbol: "person.2"
        ) {
            ForEach(duplicates) { candidate in
                HStack(spacing: BrevSpacing.sm) {
                    VStack(
                        alignment: .leading,
                        spacing: BrevSpacing.xxs
                    ) {
                        Text(candidate.contact.displayName)
                            .brevFont(.body)
                            .foregroundStyle(theme.textPrimary.color)
                        Text(candidate.reasons.joined(separator: " · "))
                            .brevFont(.caption)
                            .foregroundStyle(theme.textSecondary.color)
                    }
                    Spacer(minLength: BrevSpacing.sm)
                    if let onReviewDuplicate {
                        Button {
                            onReviewDuplicate(candidate.contact)
                        } label: {
                            Text(
                                String(
                                    localized: "Review",
                                    bundle: .module
                                )
                            )
                            .brevFont(.caption)
                            .foregroundStyle(theme.accent.color)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text(String(
                localized:
                "Suggestions never merge contacts — review each record yourself.",
                bundle: .module
            ))
            .brevFont(.caption)
            .foregroundStyle(theme.textTertiary.color)
        }
    }

    private func photoImage(_ data: Data) -> Image? {
        #if os(macOS)
        NSImage(data: data).map { Image(nsImage: $0) }
        #else
        UIImage(data: data).map { Image(uiImage: $0) }
        #endif
    }

    // MARK: - Provenance

    private var provenanceFooter: some View {
        HStack(spacing: BrevSpacing.xs) {
            if let collection {
                Text(collection.displayName)
            }
            if collection != nil, source != nil {
                Text(verbatim: " · ")
            }
            if let source {
                Text(source.displayName)
            }
            if let providerUpdatedAt = contact.providerUpdatedAt {
                Text(verbatim: " · ")
                Text(String(
                    localized:
                    "Updated \(providerUpdatedAt.formatted(.dateTime.month().day().hour().minute()))",
                    bundle: .module
                ))
            }
        }
        .brevFont(.caption)
        .foregroundStyle(theme.textTertiary.color)
    }

    // MARK: - Building blocks

    private func detailSection<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            Label(title, systemImage: symbol)
                .brevFont(.subheadline)
                .foregroundStyle(theme.textSecondary.color)
            VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                content()
            }
            .padding(.leading, BrevSpacing.xs)
        }
    }
}
