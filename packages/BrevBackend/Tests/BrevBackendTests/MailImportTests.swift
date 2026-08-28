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

@testable import BrevBackend
import Foundation
import Testing

@Suite("MBOXParser")
struct MBOXParserTests {
    private static let singleMessage = """
    From alice@example.com Thu Jan  1 00:00:00 2026
    From: Alice <alice@example.com>
    To: Bob <bob@example.com>
    Subject: Hello
    Date: Thu, 1 Jan 2026 00:00:00 +0000

    Hello Bob, this is the body.
    """

    private static let twoMessages = """
    From alice@example.com Thu Jan  1 00:00:00 2026
    From: Alice <alice@example.com>
    Subject: Message 1

    Body of message 1.
    From bob@example.com Thu Jan  1 01:00:00 2026
    From: Bob <bob@example.com>
    Subject: Message 2

    Body of message 2.
    """

    @Test("single message parses headers and body")
    func singleMessageParsesHeadersAndBody() {
        let parser = MBOXParser()
        let result = parser.parse(data: Data(Self.singleMessage.utf8))
        #expect(result.messages.count == 1)
        let msg = result.messages[0]
        #expect(msg.subject == "Hello")
        #expect(msg.from?.contains("alice@example.com") == true)
        #expect(String(data: msg.bodyData, encoding: .utf8)?.contains("Hello Bob") == true)
    }

    @Test("mboxrd-escaped >From body lines are unquoted and don't split the message")
    func mboxrdFromUnquoting() {
        let mbox = """
        From alice@example.com Thu Jan  1 00:00:00 2026
        From: Alice <alice@example.com>
        Subject: Quoting

        Quote follows:
        >From the desk of Alice
        >>From a nested quote
        Regular line.
        """
        let result = MBOXParser().parse(data: Data(mbox.utf8))
        #expect(result.messages.count == 1) // the body From-lines must not split it
        let body = String(data: result.messages[0].bodyData, encoding: .utf8) ?? ""
        #expect(body.contains("From the desk of Alice")) // ">From " unquoted to "From "
        #expect(body.contains(">From a nested quote")) // ">>From " unquoted to ">From "
        #expect(!body.contains(">From the desk")) // the escaped single-">" form is gone
    }

    @Test("two messages are both parsed")
    func twoMessagesAreBothParsed() {
        let parser = MBOXParser()
        let result = parser.parse(data: Data(Self.twoMessages.utf8))
        #expect(result.messages.count == 2)
        #expect(result.messages[0].subject == "Message 1")
        #expect(result.messages[1].subject == "Message 2")
        #expect(result.parseErrors.isEmpty)
    }

    @Test("empty MBOX returns no messages")
    func emptyMBOXReturnsNoMessages() {
        let result = MBOXParser().parse(data: Data())
        #expect(result.messages.isEmpty)
    }

    @Test("mboxrd-style >From lines are unescaped in body")
    func mboxrdFromLinesUnescaped() {
        let mbox = """
        From sender@example.com Mon Jan  1 00:00:00 2026
        Subject: Test

        >From the body, this was escaped.
        """
        let result = MBOXParser().parse(data: Data(mbox.utf8))
        let body = String(data: result.messages[0].bodyData, encoding: .utf8) ?? ""
        #expect(body.contains("From the body"))
        #expect(!body.contains(">From"))
    }

    @Test("header folding is handled")
    func headerFoldingIsHandled() {
        let mbox = """
        From sender@example.com Mon Jan  1 00:00:00 2026
        Subject: A very long subject that is
         folded across multiple lines

        Body.
        """
        let result = MBOXParser().parse(data: Data(mbox.utf8))
        let subject = result.messages[0].subject ?? ""
        #expect(subject.contains("very long subject"))
        #expect(subject.contains("folded"))
    }

    @Test("two-message mbox with >From escaped line in body")
    func twoMessageMboxWithEscapedFromInBody() {
        // The second message body contains a >From  line that must be unescaped
        // to "From " and must NOT be treated as a message separator.
        let mbox = """
        From alice@example.com Thu Jan  1 00:00:00 2026
        From: Alice <alice@example.com>
        Subject: First

        First body.
        From bob@example.com Thu Jan  1 01:00:00 2026
        From: Bob <bob@example.com>
        Subject: Second

        >From the river, a quote.
        Normal second body line.
        """
        let result = MBOXParser().parse(data: Data(mbox.utf8))
        #expect(result.messages.count == 2)
        #expect(result.messages[0].subject == "First")
        #expect(result.messages[1].subject == "Second")
        let secondBody = String(data: result.messages[1].bodyData, encoding: .utf8) ?? ""
        // The ">From " escape must be stripped to "From ".
        #expect(secondBody.contains("From the river"))
        #expect(!secondBody.contains(">From"))
        #expect(result.parseErrors.isEmpty)
    }

    @Test("From - empty-sender separator is recognised")
    func fromDashEmptySenderSeparatorRecognised() {
        // Some MUAs write "From - <timestamp>" when the envelope sender is unknown.
        let mbox = """
        From - Thu Jan  1 00:00:00 2026
        From: Carol <carol@example.com>
        Subject: Empty-sender message

        Body with no envelope sender.
        """
        let result = MBOXParser().parse(data: Data(mbox.utf8))
        #expect(result.messages.count == 1)
        #expect(result.messages[0].subject == "Empty-sender message")
        let body = String(data: result.messages[0].bodyData, encoding: .utf8) ?? ""
        #expect(body.contains("no envelope sender"))
        #expect(result.parseErrors.isEmpty)
    }

    @Test("header(name:) lookup is case-insensitive")
    func headerLookupIsCaseInsensitive() {
        let mbox = """
        From s@example.com Mon Jan  1 00:00:00 2026
        Message-ID: <unique-id@example.com>
        Subject: Test

        Body.
        """
        let result = MBOXParser().parse(data: Data(mbox.utf8))
        let msg = result.messages[0]
        #expect(msg.header("message-id") == msg.header("Message-ID"))
        #expect(msg.messageID?.contains("unique-id") == true)
    }

    @Test("contentsOf streams messages in bounded batches")
    func contentsOfStreamsMessagesInBoundedBatches() throws {
        let url = try Self.writeTemporaryMBOX(Self.twoMessages)
        var batchSizes: [Int] = []
        var subjects: [String] = []

        let summary = try MBOXParser().parseBatches(contentsOf: url, batchSize: 1) { batch in
            batchSizes.append(batch.count)
            subjects.append(contentsOf: batch.compactMap(\.subject))
            #expect(batch.allSatisfy { $0.sourceURL == url })
        }

        #expect(summary.messageCount == 2)
        #expect(summary.parseErrors.isEmpty)
        #expect(batchSizes == [1, 1])
        #expect(subjects == ["Message 1", "Message 2"])
    }

    @Test("async batch parser flushes final partial batch")
    func asyncBatchParserFlushesFinalPartialBatch() async throws {
        let url = try Self.writeTemporaryMBOX(Self.twoMessages)
        var batchSizes: [Int] = []

        let summary = try await MBOXParser().parseBatches(contentsOf: url, batchSize: 10) { batch in
            await Task.yield()
            batchSizes.append(batch.count)
        }

        #expect(summary.messageCount == 2)
        #expect(batchSizes == [2])
    }

    @Test("stream parser reports missing source files")
    func streamParserReportsMissingSourceFiles() throws {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).mbox")

        do {
            _ = try MBOXParser().parseBatches(contentsOf: missingURL) { _ in }
            Issue.record("Expected missing MBOX source to throw.")
        } catch let error as MailImportReadError {
            switch error {
            case .cannotOpenFile(let name):
                #expect(name.contains("missing"))
            case .readFailed(let reason):
                #expect(reason.contains("No such file") || reason.contains("missing"))
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    private static func writeTemporaryMBOX(_ contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrevMBOXParserTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("archive.mbox")
        try Data(contents.utf8).write(to: url)
        return url
    }
}

@Suite("EMLReader")
struct EMLReaderTests {
    @Test("single EML parses CRLF headers, folded values, body, and source URL")
    func singleEMLParsesHeadersBodyAndSourceURL() {
        let url = URL(fileURLWithPath: "/tmp/brev-import-message.eml")
        let eml = """
        From: Alice <alice@example.com>\r
        To: Bob <bob@example.com>\r
        Subject: A long subject that is\r
         folded across lines\r
        Date: Thu, 1 Jan 2026 00:00:00 +0000\r
        \r
        Hello Bob,\r
        This came from an EML file.\r
        """

        let result = EMLReader().read(data: Data(eml.utf8), sourceURL: url)

        #expect(result.messages.count == 1)
        #expect(result.parseErrors.isEmpty)
        #expect(result.sourceURL == url)
        let message = result.messages[0]
        #expect(message.sourceURL == url)
        #expect(message.subject == "A long subject that is folded across lines")
        #expect(String(data: message.bodyData, encoding: .utf8)?.contains("This came from an EML file.") == true)
    }

    @Test("malformed EML reports a parse error")
    func malformedEMLReportsParseError() {
        let result = EMLReader().read(data: Data("This is not an RFC 2822 message.".utf8))

        #expect(result.messages.isEmpty)
        #expect(result.parseErrors.isEmpty == false)
    }
}

@Suite("MaildirReader — filename parsing")
struct MaildirReaderTests {
    @Test("basic filename parses unique ID and no flags")
    func basicFilenameNoFlags() {
        let (uid, flags) = MaildirReader.parseFilename("1234567890.abc.hostname")
        #expect(uid == "1234567890.abc.hostname")
        #expect(flags.isEmpty)
    }

    @Test("filename with flags parses correctly")
    func filenameWithFlagsParsesCorrectly() {
        let (uid, flags) = MaildirReader.parseFilename("1234.abc.host:2,FRS")
        #expect(uid == "1234.abc.host")
        #expect(flags.contains(.flagged))
        #expect(flags.contains(.replied))
        #expect(flags.contains(.seen))
        #expect(!flags.contains(.trashed))
    }

    @Test("all flag characters are recognized")
    func allFlagCharactersAreRecognized() {
        let (_, flags) = MaildirReader.parseFilename("uid:2,DFPRST")
        #expect(flags == [.draft, .flagged, .passed, .replied, .seen, .trashed])
    }

    @Test("unknown flag characters are silently dropped")
    func unknownFlagCharactersDropped() {
        let (_, flags) = MaildirReader.parseFilename("uid:2,SXZ")
        #expect(flags == [.seen])
    }

    @Test("Maildir reader streams message files in batches")
    func maildirReaderStreamsMessageFilesInBatches() async throws {
        let maildirURL = try Self.makeMaildir(messages: [
            ("cur", "1:2,S", "From: A <a@example.com>\nSubject: One\n\nOne"),
            ("new", "2", "From: B <b@example.com>\nSubject: Two\n\nTwo")
        ])
        var batchSizes: [Int] = []
        var subjects: [String] = []

        let summary = try await MaildirReader().readBatches(contentsOf: maildirURL, batchSize: 1) { batch in
            batchSizes.append(batch.count)
            subjects.append(contentsOf: batch.compactMap(\.subject))
        }

        #expect(summary.messageCount == 2)
        #expect(summary.parseErrors.isEmpty)
        #expect(batchSizes == [1, 1])
        #expect(subjects == ["One", "Two"])
    }

    private static func makeMaildir(messages: [(subdir: String, name: String, body: String)]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrevMaildirReaderTests-\(UUID().uuidString)", isDirectory: true)
        for subdir in ["cur", "new", "tmp"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(subdir),
                withIntermediateDirectories: true
            )
        }
        for message in messages {
            let url = root
                .appendingPathComponent(message.subdir)
                .appendingPathComponent(message.name)
            try Data(message.body.utf8).write(to: url)
        }
        return root
    }
}
