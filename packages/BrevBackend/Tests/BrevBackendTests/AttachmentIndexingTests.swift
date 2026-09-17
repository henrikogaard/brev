/*
 Brev - Mail Client for macOS and iOS
 Copyright (c) 2026 Brev contributors

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the conditions of the LICENSE file.
 */

@testable import BrevBackend
import Foundation
import PDFKit
import Testing

/// ADR-0078: bounded, cache-only attachment text extraction and the
/// serialized per-account indexer that feeds `attachment_search`.
@Suite("Attachment text extractor")
struct AttachmentTextExtractorTests {
    @Test("plain text and CSV decode")
    func plainText() async throws {
        let text = try await AttachmentTextExtractor.extract(
            data: Data("invoice needle".utf8),
            mimeType: "text/plain",
            fileName: "notes.txt"
        )
        #expect(text?.contains("invoice needle") == true)

        let csv = try await AttachmentTextExtractor.extract(
            data: Data("a,b\n1,2".utf8),
            mimeType: "application/octet-stream",
            fileName: "data.csv"
        )
        #expect(csv?.contains("a,b") == true)
    }

    @Test("RTF decodes via NSAttributedString")
    func rtf() async throws {
        let rtf = Data(#"{\rtf1\ansi hello rtf needle}"#.utf8)
        let text = try await AttachmentTextExtractor.extract(
            data: rtf, mimeType: "text/rtf", fileName: "doc.rtf"
        )
        #expect(text?.contains("hello rtf needle") == true)
    }

    @Test("HTML decodes to visible text")
    func html() async throws {
        let html = Data("<html><body><p>html needle text</p></body></html>".utf8)
        let text = try await AttachmentTextExtractor.extract(
            data: html, mimeType: "text/html", fileName: "page.html"
        )
        #expect(text?.contains("html needle text") == true)
    }

    @Test("PDF text extracts via PDFKit; malformed PDF returns nil")
    func pdf() async throws {
        let pdfData = Self.minimalPDF(text: "pdf needle text")
        let text = try await AttachmentTextExtractor.extract(
            data: pdfData, mimeType: "application/pdf", fileName: "doc.pdf"
        )
        #expect(text?.contains("pdf needle text") == true)

        let bad = try await AttachmentTextExtractor.extract(
            data: Data("not a pdf".utf8), mimeType: "application/pdf", fileName: "x.pdf"
        )
        #expect(bad == nil)
    }

    @Test("Office documents return nil (importer may resolve external relationships)")
    func officeDocumentsSkipped() async throws {
        let text = try await AttachmentTextExtractor.extract(
            data: Data("PK fake zip bytes".utf8),
            mimeType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            fileName: "doc.docx"
        )
        #expect(text == nil)
    }

    @Test("HTML with remote references extracts without any network load")
    func htmlRemoteReferencesStayInert() async throws {
        // Extraction is a pure-string strip — no document importer is ever
        // constructed — so `<img src>`/`<link href>` are inert markup and no
        // code path can fetch them. If an importer is ever reintroduced,
        // the unreachable 127.0.0.1:1 references make this test hang and
        // fail on the timeout rather than silently hitting the network.
        let html = """
        <html><head>
        <link rel="stylesheet" href="http://127.0.0.1:1/x.css">
        <style>body { color: red }</style>
        </head><body>
        <img src="http://127.0.0.1:1/x.png">
        <p>Quarterly&nbsp;report &amp; outlook</p>
        <script>fetch('http://127.0.0.1:1/beacon')</script>
        </body></html>
        """
        let text = try await AttachmentTextExtractor.extract(
            data: Data(html.utf8),
            mimeType: "text/html",
            fileName: "page.html",
            timeout: .seconds(10)
        )
        #expect(text?.contains("Quarterly report & outlook") == true)
        #expect(text?.contains("127.0.0.1") == false)
        #expect(text?.contains("color: red") == false)
        #expect(text?.contains("beacon") == false)
    }

    @Test("unsupported types return nil")
    func unsupported() async throws {
        let text = try await AttachmentTextExtractor.extract(
            data: Data([0x00, 0x01, 0x02]),
            mimeType: "application/octet-stream",
            fileName: "blob.bin"
        )
        #expect(text == nil)
    }

    @Test("inputs over 25 MB are skipped")
    func oversized() async throws {
        let data = Data(repeating: 0x61, count: AttachmentTextExtractor.maxInputBytes + 1)
        let text = try await AttachmentTextExtractor.extract(
            data: data, mimeType: "text/plain", fileName: "big.txt"
        )
        #expect(text == nil)
    }

    @Test("output truncates at 512 KB of characters")
    func truncation() async throws {
        let big = String(repeating: "x", count: AttachmentTextExtractor.maxOutputCharacters + 10)
        let text = try await AttachmentTextExtractor.extract(
            data: Data(big.utf8), mimeType: "text/plain", fileName: "big.txt"
        )
        #expect(text?.count == AttachmentTextExtractor.maxOutputCharacters)
    }

    @Test("a cancelled task throws before extracting")
    func cancellation() async throws {
        let task = Task<String?, any Error> {
            // Park until cancellation lands, then enter extract — its first
            // checkCancellation() must throw.
            while !Task.isCancelled {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            return try await AttachmentTextExtractor.extract(
                data: Data("needle".utf8), mimeType: "text/plain", fileName: "n.txt"
            )
        }
        task.cancel()
        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    @Test("extraction honours the caller timeout")
    func timeout() async throws {
        // Regex stripping of a multi-MB HTML document is slow enough that a
        // 1 ms budget reliably loses the race.
        var html = "<html><body>"
        for _ in 0 ..< 200_000 {
            html += "<p>needle</p>"
        }
        html += "</body></html>"
        await #expect(throws: AttachmentTextExtractionError.timedOut) {
            _ = try await AttachmentTextExtractor.extract(
                data: Data(html.utf8),
                mimeType: "text/html",
                fileName: "big.html",
                timeout: .milliseconds(1)
            )
        }
    }

    /// Smallest PDF with an extractable text run that PDFKit parses.
    private static func minimalPDF(text: String) -> Data {
        let stream = "BT /F1 24 Tf 100 700 Td (\(text)) Tj ET"
        let pdf = """
        %PDF-1.4
        1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
        2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
        3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]/Contents 4 0 R/Resources<</Font<</F1 5 0 R>>>>>>endobj
        4 0 obj<</Length \(stream.utf8.count)>>stream
        \(stream)
        endstream endobj
        5 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj
        trailer<</Root 1 0 R>>
        """
        return Data(pdf.utf8)
    }
}

/// Records attachment-index writes for `AttachmentIndexer` tests.
private actor RecordingAttachmentIndex: MailLocalSearchIndex {
    struct Row: Equatable {
        let messageID: String
        let attachmentID: String
        let name: String
        let text: String
    }

    private var rows: [Row] = []

    var indexedRows: [Row] { rows }

    func indexedMessageIDs() -> Set<String> { Set(rows.map(\.messageID)) }

    func indexAttachmentText(
        accountID: String,
        messageID: MessageHeader.ID,
        folderID: Folder.ID,
        attachmentID: String,
        name: String,
        text: String
    ) async throws {
        rows.removeAll { $0.messageID == messageID && $0.attachmentID == attachmentID }
        rows.append(Row(messageID: messageID, attachmentID: attachmentID, name: name, text: text))
    }

    func removeAttachmentText(accountID: String, messageIDs: [MessageHeader.ID]) async throws {
        rows.removeAll { messageIDs.contains($0.messageID) }
    }

    func removeAllAttachmentText(accountID: String) async throws {
        rows.removeAll()
    }

    func attachmentIndexBytes(accountID: String) async -> Int {
        rows.reduce(0) { $0 + $1.text.count }
    }

    func indexedAttachmentMessageIDs(accountID: String) async -> Set<MessageHeader.ID> {
        Set(rows.map(\.messageID))
    }

    func matchedAttachmentNames(
        matching query: SearchQuery,
        account: BrevAccount,
        messageIDs: [MessageHeader.ID]
    ) async -> [MessageHeader.ID: String] { [:] }

    // Unused protocol surface.
    func cachedHeaders(
        for folder: Folder, account: BrevAccount, pageToken: String?
    ) async -> (headers: [MessageHeader], nextPageToken: String?)? { nil }
    func cachedRawMessage(for messageID: MessageHeader.ID, account: BrevAccount) async -> Data? { nil }
    func storeRawMessage(_ data: Data, for messageID: MessageHeader.ID, account: BrevAccount) async {}
    func search(_ query: SearchQuery, account: BrevAccount, limit: Int) async -> [MessageHeader] { [] }
    func storeHeaders(_ newHeaders: [MessageHeader], account: BrevAccount) async {}
    func deleteMessages(_ messageIDs: [MessageHeader.ID], account: BrevAccount) async {}
    func deleteRawMessages(_ messageIDs: [MessageHeader.ID], account: BrevAccount) async {}
    func deleteRawMessages(inFolder folderID: Folder.ID, account: BrevAccount) async {}
    func deleteRawMessages(
        inFolder folderID: Folder.ID,
        except exceptMessageIDs: Set<MessageHeader.ID>,
        account: BrevAccount
    ) async {}
    func clearFolder(folderID: Folder.ID, account: BrevAccount) async {}
    func clearAccount(_ account: BrevAccount) async {}
    func metrics(for account: BrevAccount) async -> LocalSearchIndexMetrics? { nil }
}

@Suite("Attachment indexer")
struct AttachmentIndexerTests {
    private static let account = BrevAccount(
        id: "acc", displayName: "A", emailAddress: "a@example.org"
    )

    /// Minimal RFC 5322 message with one text attachment; `disposition`
    /// controls inline vs regular attachment.
    private static func rawMessage(
        attachmentText: String = "attachment needle text",
        fileName: String = "notes.txt",
        disposition: String = "attachment"
    ) -> String {
        """
        From: sender@example.org
        Subject: Message
        MIME-Version: 1.0
        Content-Type: multipart/mixed; boundary="bb"

        --bb
        Content-Type: text/plain

        body text
        --bb
        Content-Type: text/plain; name="\(fileName)"
        Content-Disposition: \(disposition); filename="\(fileName)"

        \(attachmentText)
        --bb--
        """
    }

    private static func makeIndexer(
        enabled: @escaping @Sendable () -> Bool = { true },
        index: RecordingAttachmentIndex,
        entries: [AttachmentIndexer.SweepEntry],
        raw: [String: String]
    ) -> AttachmentIndexer {
        AttachmentIndexer(
            accountID: account.id,
            isEnabled: enabled,
            index: index,
            sweepEntries: { entries },
            rawMessageProvider: { raw[$0] }
        )
    }

    /// Drains run in internal tasks; poll briefly for the expected row count.
    private static func waitForRows(
        _ count: Int, in index: RecordingAttachmentIndex
    ) async -> [RecordingAttachmentIndex.Row] {
        for _ in 0 ..< 200 {
            let rows = await index.indexedRows
            if rows.count >= count { return rows }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return await index.indexedRows
    }

    @Test("sweep indexes text from a cached attachment")
    func sweepIndexes() async throws {
        let index = RecordingAttachmentIndex()
        let indexer = Self.makeIndexer(
            index: index,
            entries: [.init(messageID: "INBOX:1", folderID: "INBOX")],
            raw: ["INBOX:1": Self.rawMessage()]
        )
        await indexer.sweep()
        let rows = await Self.waitForRows(1, in: index)
        #expect(rows.first?.name == "notes.txt")
        #expect(rows.first?.text.contains("attachment needle text") == true)
    }

    @Test("sweep skips messages already indexed")
    func skipsAlreadyIndexed() async throws {
        let index = RecordingAttachmentIndex()
        try await index.indexAttachmentText(
            accountID: Self.account.id,
            messageID: "INBOX:1",
            folderID: "INBOX",
            attachmentID: "a1",
            name: "old.txt",
            text: "existing"
        )
        let indexer = Self.makeIndexer(
            index: index,
            entries: [.init(messageID: "INBOX:1", folderID: "INBOX")],
            raw: ["INBOX:1": Self.rawMessage(attachmentText: "new content")]
        )
        await indexer.sweep()
        try await Task.sleep(nanoseconds: 100_000_000)
        let rows = await index.indexedRows
        #expect(rows.count == 1)
        #expect(rows.first?.text == "existing")
    }

    @Test("inline attachments are skipped")
    func skipsInline() async throws {
        let index = RecordingAttachmentIndex()
        let indexer = Self.makeIndexer(
            index: index,
            entries: [.init(messageID: "INBOX:1", folderID: "INBOX")],
            raw: ["INBOX:1": Self.rawMessage(disposition: "inline")]
        )
        await indexer.sweep()
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(await index.indexedRows.isEmpty)
    }

    @Test("disabled consent does no work; disable() removes rows")
    func disableRemovesRows() async throws {
        let index = RecordingAttachmentIndex()
        let flag = Flag()
        let indexer = Self.makeIndexer(
            enabled: { flag.value },
            index: index,
            entries: [.init(messageID: "INBOX:1", folderID: "INBOX")],
            raw: ["INBOX:1": Self.rawMessage()]
        )
        await indexer.sweep()
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(await index.indexedRows.isEmpty)

        flag.value = true
        await indexer.sweep()
        _ = await Self.waitForRows(1, in: index)
        #expect(await index.indexedRows.count == 1)

        flag.value = false
        await indexer.disable()
        #expect(await index.indexedRows.isEmpty)
    }

    @Test("messages without cached source are skipped without fetching")
    func skipsUncached() async throws {
        let index = RecordingAttachmentIndex()
        let indexer = Self.makeIndexer(
            index: index,
            entries: [.init(messageID: "INBOX:9", folderID: "INBOX")],
            raw: [:]
        )
        await indexer.sweep()
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(await index.indexedRows.isEmpty)
    }

    @Test("noteSourceCached enqueues a single message")
    func noteSourceCached() async throws {
        let index = RecordingAttachmentIndex()
        let indexer = Self.makeIndexer(
            index: index,
            entries: [],
            raw: ["INBOX:2": Self.rawMessage()]
        )
        await indexer.noteSourceCached(messageID: "INBOX:2", folderID: "INBOX")
        let rows = await Self.waitForRows(1, in: index)
        #expect(rows.first?.messageID == "INBOX:2")
    }
}

/// Mutable box for flipping the indexer's enabled flag mid-test.
private final class Flag: @unchecked Sendable {
    var value = false
}

/// `.localAttachmentIndex` is advertised only when a local search index is
/// wired (ADR-0078 §8); the UI gates every indexing control on it.
@Suite("Attachment index capability")
struct AttachmentIndexCapabilityTests {
    private static let account = BrevAccount(
        id: "imap-smtp:person@example.org",
        displayName: "Person",
        emailAddress: "person@example.org"
    )

    private static let configuration = IMAPAccountConfiguration(
        accountID: "imap-smtp:person@example.org",
        emailAddress: "person@example.org",
        displayName: "Person",
        incoming: MailServerSettings(
            kind: .imap,
            host: "imap.example.org",
            port: 993,
            tlsMode: .implicit,
            authentication: .password
        ),
        outgoing: MailServerSettings(
            kind: .smtp,
            host: "smtp.example.org",
            port: 587,
            tlsMode: .startTLS,
            authentication: .password
        ),
        credentialID: "imap-smtp:person@example.org"
    )

    private static let credential = MailAccountCredential(
        incomingUsername: "person@example.org",
        outgoingUsername: "person@example.org",
        secret: "secret",
        authentication: .password
    )

    private static func imapBackend(
        index: (any MailLocalSearchIndex)?
    ) -> IMAPSMTPBackend {
        IMAPSMTPBackend(
            account: account,
            configuration: configuration,
            credential: credential,
            listFolders: { _, _ in [] },
            localSearchIndex: index
        )
    }

    @Test("IMAP advertises the capability only with a local index")
    func imapCapability() {
        #expect(Self.imapBackend(index: RecordingAttachmentIndex())
            .extendedCapabilities.contains(.localAttachmentIndex))
        #expect(!Self.imapBackend(index: nil)
            .extendedCapabilities.contains(.localAttachmentIndex))
    }

    @Test("local mail advertises the capability only with a local index")
    func localCapability() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-attcap-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let withIndex = LocalMailBackend(
            store: LocalMaildirStore(rootURL: root),
            localSearchIndex: RecordingAttachmentIndex()
        )
        #expect(withIndex.extendedCapabilities.contains(.localAttachmentIndex))

        let without = LocalMailBackend(store: LocalMaildirStore(rootURL: root))
        #expect(!without.extendedCapabilities.contains(.localAttachmentIndex))
    }
}
