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
@testable import BrevMail
import Foundation
import Testing

@Suite("MessagePropertiesPresentation")
struct MessagePropertiesPresentationTests {
    @Test("rows expose core metadata in order and omit empty recipient lists")
    func rowsExposeCoreMetadataInOrder() {
        let header = Self.makeHeader(
            to: [Correspondent(name: "Bea", email: "bea@example.org")],
            subject: "Lunch?"
        )

        let rows = MessagePropertiesPresentation.rows(for: header, dateText: "June 1, 2026")

        #expect(rows.map(\.label) == ["From", "To", "Date", "Subject"])
        #expect(rows.first?.value == "Alex <alex@example.org>")
        #expect(rows.first(where: { $0.label == "Subject" })?.value == "Lunch?")
        #expect(rows.first(where: { $0.label == "Date" })?.value == "June 1, 2026")
    }

    @Test("multiple recipients join with commas and cc/bcc appear when present")
    func multipleRecipientsJoinWithCommas() {
        let header = Self.makeHeader(
            to: [
                Correspondent(name: "Bea", email: "bea@example.org"),
                Correspondent(name: nil, email: "carol@example.org")
            ],
            cc: [Correspondent(name: "Dan", email: "dan@example.org")],
            bcc: [Correspondent(name: "Eve", email: "eve@example.org")],
            subject: "Sync"
        )

        let rows = MessagePropertiesPresentation.rows(for: header, dateText: "x")

        #expect(rows.map(\.label) == ["From", "To", "Cc", "Bcc", "Date", "Subject"])
        #expect(rows.first(where: { $0.label == "To" })?.value == "Bea <bea@example.org>, carol@example.org")
        #expect(rows.first(where: { $0.label == "Cc" })?.value == "Dan <dan@example.org>")
    }

    @Test("empty subject falls back to a placeholder")
    func emptySubjectFallsBackToPlaceholder() {
        let header = Self.makeHeader(subject: "   ")
        let rows = MessagePropertiesPresentation.rows(for: header, dateText: "x")
        #expect(rows.first(where: { $0.label == "Subject" })?.value == "(No subject)")
    }

    @Test("attachments row appears only when the message has attachments")
    func attachmentsRowAppearsOnlyWhenPresent() {
        let without = MessagePropertiesPresentation.rows(
            for: Self.makeHeader(hasAttachments: false),
            dateText: "x"
        )
        #expect(without.contains { $0.label == "Attachments" } == false)

        let with = MessagePropertiesPresentation.rows(
            for: Self.makeHeader(hasAttachments: true),
            dateText: "x"
        )
        #expect(with.first(where: { $0.label == "Attachments" })?.value == "Yes")
    }

    private static func makeHeader(
        to: [Correspondent] = [],
        cc: [Correspondent] = [],
        bcc: [Correspondent] = [],
        subject: String = "Hello",
        hasAttachments: Bool = false
    ) -> MessageHeader {
        MessageHeader(
            id: "m1",
            threadID: "t1",
            folderID: "inbox",
            from: Correspondent(name: "Alex", email: "alex@example.org"),
            to: to,
            cc: cc,
            bcc: bcc,
            subject: subject,
            snippet: "Preview",
            date: Date(timeIntervalSince1970: 1_779_960_600),
            hasAttachments: hasAttachments
        )
    }
}
