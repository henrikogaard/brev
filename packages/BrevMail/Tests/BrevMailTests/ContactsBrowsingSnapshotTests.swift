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

#if os(macOS)
import AppKit
import BrevCalendar
@testable import BrevMail
import BrevThemes
import Foundation
import SnapshotTesting
import SwiftUI
import Testing

/// Snapshot coverage for the Contacts browsing surface (ADR-0072 #8).
/// Set RECORD_SNAPSHOTS=YES to record or refresh the baselines.
@Suite("Contacts browsing snapshots")
@MainActor
struct ContactsBrowsingSnapshotTests {
    private static let syncedAt = Date(timeIntervalSince1970: 1_800_000_000)

    private static func contact(
        id: String,
        displayName: String,
        givenName: String? = nil,
        familyName: String? = nil,
        organization: String? = nil,
        jobTitle: String? = nil,
        emails: [PIMContactField] = []
    ) -> PIMContact {
        PIMContact(
            id: id,
            sourceID: "s1",
            collectionID: "c1",
            providerItemKey: id,
            displayName: displayName,
            givenName: givenName,
            familyName: familyName,
            organization: organization,
            jobTitle: jobTitle,
            emails: emails,
            syncedAt: syncedAt
        )
    }

    @Test(
        "contact rows render monogram, name, and subtitle",
        arguments: ["light", "dark"]
    )
    func contactRow(mode: String) {
        // Rows render standalone — List cells never materialize inside a
        // bare NSHostingController, so the suite snapshots the row view
        // the List reuses (same convention as MessageListRowSnapshotTests).
        let rows = VStack(alignment: .leading, spacing: 0) {
            ContactRowView(
                contact: Self.contact(
                    id: "c1",
                    displayName: "Ada Lovelace",
                    givenName: "Ada",
                    familyName: "Lovelace",
                    organization: "Ogard Labs",
                    jobTitle: "Engineer"
                )
            )
            ContactRowView(
                contact: Self.contact(
                    id: "c2",
                    displayName: "Bo",
                    emails: [
                        PIMContactField(
                            label: "work",
                            value: "bo@example.com"
                        ),
                    ]
                )
            )
        }

        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let view = rows
            .frame(width: 360, height: 200)
            .brevTheme(theme)
            .environment(\.colorScheme, theme.mode.colorScheme)

        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 360, height: 200)

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 360, height: 200)),
            named: "row-\(mode)",
            record: ProcessInfo.processInfo
                .environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("contact detail renders all fields", arguments: ["light", "dark"])
    func contactDetail(mode: String) {
        var contact = Self.contact(
            id: "c1",
            displayName: "Ada Lovelace",
            givenName: "Ada",
            familyName: "Lovelace",
            organization: "Ogard Labs",
            jobTitle: "Engineer",
            emails: [
                PIMContactField(label: "work", value: "ada@ogard.cloud"),
                PIMContactField(label: "home", value: "ada@example.com"),
            ]
        )
        contact.nickname = "Ada"
        contact.phones = [
            PIMContactField(label: "mobile", value: "+47 999 00 111")
        ]
        contact.addresses = [
            PIMContactAddress(
                label: "work",
                street: "Storgata 1",
                city: "Oslo",
                country: "Norway"
            ),
        ]
        contact.note = "Met at the launch."
        contact.providerUpdatedAt = Self.syncedAt

        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let view = ContactDetailView(
            contact: contact,
            collection: PIMCollection(
                id: "c1",
                sourceID: "s1",
                kind: .contacts,
                displayName: "Address book",
                colorHex: nil,
                isReadOnly: false,
                isPrimary: true,
                supportsSyncToken: true,
                providerKey: "c1",
                providerVersion: nil,
                isVisible: true,
                updatedAt: Self.syncedAt
            ),
            source: PIMSource(
                id: "s1",
                kind: .contacts,
                provider: .cardDAV,
                displayName: "CardDAV",
                syncEnabled: true,
                status: .ready,
                createdAt: Self.syncedAt,
                updatedAt: Self.syncedAt
            ),
            groupNames: ["Team"]
        )
        .frame(width: 420, height: 620)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)

        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 420, height: 620)

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 420, height: 620)),
            named: "detail-\(mode)",
            record: ProcessInfo.processInfo
                .environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}
#endif
