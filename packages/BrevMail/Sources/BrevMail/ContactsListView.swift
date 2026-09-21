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

/// The alphabetically-sectioned contacts list inside the Contacts
/// surface (ADR-0072).
///
/// Renders pre-grouped `LetterSection`s — already filtered for hidden
/// collections, the group filter, and the local search query — with a
/// monogram avatar, name, and org/email subtitle per row.
public struct ContactsListView: View {
    @Environment(\.brevTheme) private var theme

    /// Letter buckets in alphabetical order ("#" trails).
    let sections: [ContactsBrowsingModel.LetterSection]
    /// Selection shared with the detail pane.
    @Binding var selectedContactID: PIMContact.ID?

    public init(
        sections: [ContactsBrowsingModel.LetterSection],
        selectedContactID: Binding<PIMContact.ID?>
    ) {
        self.sections = sections
        _selectedContactID = selectedContactID
    }

    public var body: some View {
        List(selection: $selectedContactID) {
            ForEach(sections) { section in
                Section {
                    ForEach(section.contacts) { contact in
                        ContactRowView(contact: contact)
                            .tag(contact.id)
                    }
                } header: {
                    Text(section.letter)
                        .brevFont(.subheadline)
                        .foregroundStyle(theme.textSecondary.color)
                }
            }
        }
        .listStyle(.plain)
        .accessibilityLabel(
            String(localized: "Contacts", bundle: .module)
        )
    }
}

/// One contact row in the list — monogram, display name, and a
/// secondary line (title · organization, else first email/phone).
/// Extracted so the row renders identically in the List and in
/// snapshot fixtures (List cells never materialize inside a bare
/// hosting controller).
public struct ContactRowView: View {
    @Environment(\.brevTheme) private var theme

    let contact: PIMContact

    public init(contact: PIMContact) {
        self.contact = contact
    }

    public var body: some View {
        HStack(spacing: BrevSpacing.md) {
            Text(ContactPresentation.initials(for: contact))
                .brevFont(.subheadline)
                .foregroundStyle(theme.bgPrimary.color)
                .frame(width: 32, height: 32)
                .background(
                    Circle().fill(theme.accentMuted.color)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                Text(contact.displayName)
                    .brevFont(.subheadline)
                    .foregroundStyle(theme.textPrimary.color)
                    .lineLimit(1)
                if let subtitle = ContactPresentation.subtitle(
                    for: contact
                ) {
                    Text(subtitle)
                        .brevFont(.caption)
                        .foregroundStyle(theme.textSecondary.color)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, BrevSpacing.xxs)
        .accessibilityElement(children: .combine)
    }
}
