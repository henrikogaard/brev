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

/// .eml export coverage (#79): the temp-file writer that backs the iOS
/// share-sheet path, and the help action that opens the shortcuts sheet.
@Suite("MessageEMLExport")
struct MessageEMLExportTests {
    private static func header(subject: String) -> MessageHeader {
        MessageHeader(
            id: "m1",
            threadID: "t1",
            folderID: "inbox",
            from: Correspondent(name: "Alex", email: "alex@example.org"),
            subject: subject,
            snippet: "Preview",
            date: Date(timeIntervalSince1970: 1_779_960_600),
            isRead: false,
            isFlagged: false
        )
    }

    @Test("temp export writes raw bytes to a subject-named .eml file")
    func temporaryFileWritesRawBytes() throws {
        let bytes = Data("Subject: Hi\r\n\r\nBody".utf8)
        let url = try MessageEMLExport.writeToTemporaryFile(
            header: Self.header(subject: "Quarterly Report"),
            rawMessageData: bytes
        )
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(url.pathExtension == "eml")
        #expect(url.lastPathComponent == "Quarterly Report.eml")
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test("temp export sanitizes hostile subjects")
    func temporaryFileSanitizesName() throws {
        let url = try MessageEMLExport.writeToTemporaryFile(
            header: Self.header(subject: "a/b\\c:.."),
            rawMessageData: Data("x".utf8)
        )
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(url.lastPathComponent.hasSuffix(".eml"))
        #expect(!url.lastPathComponent.contains("/"))
        #expect(!url.lastPathComponent.hasPrefix("."))
    }

    @Test("temp export overwrites a previous export of the same message")
    func temporaryFileOverwrites() throws {
        let header = Self.header(subject: "Repeat")
        let first = try MessageEMLExport.writeToTemporaryFile(
            header: header,
            rawMessageData: Data("one".utf8)
        )
        defer { try? FileManager.default.removeItem(at: first) }
        let second = try MessageEMLExport.writeToTemporaryFile(
            header: header,
            rawMessageData: Data("two".utf8)
        )

        #expect(first == second)
        #expect(try Data(contentsOf: second) == Data("two".utf8))
    }
}

/// The focused help action published for the iPadOS Help menu (#79).
@Suite("MailHelpActions")
struct MailHelpActionsTests {
    @MainActor
    @Test("keyboardShortcuts invokes the published handler")
    func keyboardShortcutsForwards() {
        var didOpen = false
        let actions = MailHelpActions(keyboardShortcuts: { didOpen = true })

        actions.keyboardShortcuts()

        #expect(didOpen)
    }
}
