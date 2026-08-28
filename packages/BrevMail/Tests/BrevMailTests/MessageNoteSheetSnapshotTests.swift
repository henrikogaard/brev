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

#if canImport(UIKit)
import BrevBackend
@testable import BrevMail
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@Suite("Message note sheet snapshots")
@MainActor
struct MessageNoteSheetSnapshotTests {
    private static func header() -> MessageHeader {
        MessageHeader(
            id: "m1",
            threadID: "t1",
            folderID: "inbox",
            from: Correspondent(name: "Alex Rivera", email: "alex@example.org"),
            subject: "Quarterly report follow-up",
            snippet: "Preview",
            date: Date(timeIntervalSince1970: 1_779_960_600),
            isRead: false,
            isFlagged: false
        )
    }

    @Test("Add Note sheet renders with empty editor")
    func addNoteEmpty() {
        let theme = BrevTheme.brevBuiltIns.first!
        let view = MessageNoteSheet(
            header: Self.header(),
            note: nil,
            onSave: { _ in },
            onClose: {}
        )
        .frame(width: 460, height: 420)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear
        assertSnapshot(of: host, as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)), named: "add-note-empty")
    }

    @Test("Edit Note sheet renders with existing body and delete action")
    func editNoteWithBody() {
        let theme = BrevTheme.brevBuiltIns.first!
        let note = LocalMessageNote(
            messageID: SourceMessageID(
                sourceID: MailSourceID(accountID: "acct", mailboxID: "inbox"),
                messageID: "m1"
            ),
            body: "Follow up after launch. Confirm the rollout date with the platform team.",
            createdAt: Date(timeIntervalSince1970: 1_779_960_000),
            updatedAt: Date(timeIntervalSince1970: 1_779_961_200)
        )
        let view = MessageNoteSheet(
            header: Self.header(),
            note: note,
            onSave: { _ in },
            onDelete: {},
            onClose: {}
        )
        .frame(width: 460, height: 420)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear
        assertSnapshot(of: host, as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)), named: "edit-note-with-body")
    }
}
#endif
