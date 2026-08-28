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

@Suite("MBOXExporter")
struct MBOXExporterTests {
    @Test("MBOX export writes messages in order and escapes body From lines")
    func mboxExportWritesMessagesInOrderAndEscapesFromLines() throws {
        let url = try Self.temporaryFile(named: "export.mbox")
        let messages = [
            ImportedMessage(
                headers: [
                    (name: "From", value: "Alice <alice@example.com>"),
                    (name: "Date", value: "Thu Jan  1 00:00:00 2026"),
                    (name: "Subject", value: "One")
                ],
                bodyData: Data("Subject: One\n\nFirst body\nFrom escaped body line".utf8)
            ),
            ImportedMessage(
                headers: [
                    (name: "From", value: "Bob <bob@example.com>"),
                    (name: "Date", value: "Thu Jan  1 01:00:00 2026"),
                    (name: "Subject", value: "Two")
                ],
                bodyData: Data("Subject: Two\n\nSecond body".utf8)
            )
        ]
        let progress = ProgressRecorder()

        try MBOXExporter().export(messages: messages, to: url) { completed, total in
            progress.record(completed: completed, total: total)
        }

        let output = try String(contentsOf: url, encoding: .utf8)
        #expect(output.contains("From Alice <alice@example.com> Thu Jan  1 00:00:00 2026"))
        #expect(output.contains("From Bob <bob@example.com> Thu Jan  1 01:00:00 2026"))
        #expect(output.contains("\n>From escaped body line"))
        let aliceIndex = try #require(output.range(of: "From Alice")?.lowerBound)
        let bobIndex = try #require(output.range(of: "From Bob")?.lowerBound)
        #expect(aliceIndex < bobIndex)
        #expect(progress.completedValues == [1, 2])
        #expect(progress.totalValues == [2, 2])
    }

    @Test("MBOX export escapes already-quoted >From body lines so import round-trips")
    func mboxExportEscapesQuotedFromLinesForRoundTrip() throws {
        let url = try Self.temporaryFile(named: "quoted-from.mbox")
        let messages = [
            ImportedMessage(
                headers: [
                    (name: "From", value: "a@example.com"),
                    (name: "Date", value: "Thu Jan  1 00:00:00 2026"),
                    (name: "Subject", value: "Q")
                ],
                bodyData: Data("Subject: Q\n\nFrom a\n>From b\n>>From c".utf8)
            )
        ]

        try MBOXExporter().export(messages: messages, to: url) { _, _ in }
        let output = try String(contentsOf: url, encoding: .utf8)

        // Each From-line gains exactly one ">", including the already-quoted ones.
        #expect(output.contains("\n>From a"))
        #expect(output.contains("\n>>From b"))
        #expect(output.contains("\n>>>From c"))

        // Re-importing the exported mbox recovers the original body lines exactly.
        let reimported = MBOXParser().parse(data: Data(output.utf8))
        #expect(reimported.messages.count == 1)
        let bodyLines = (String(data: reimported.messages[0].bodyData, encoding: .utf8) ?? "")
            .components(separatedBy: "\n")
        #expect(bodyLines.contains("From a"))
        #expect(bodyLines.contains(">From b"))
        #expect(bodyLines.contains(">>From c"))
    }

    @Test("MBOX append writes one message without replacing existing output")
    func appendWritesOneMessageWithoutReplacingExistingOutput() throws {
        let url = try Self.temporaryFile(named: "streamed.mbox")
        FileManager.default.createFile(atPath: url.path, contents: Data("prefix\n".utf8))
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()

        try MBOXExporter().append(
            message: ImportedMessage(
                headers: [
                    (name: "From", value: "stream@example.com"),
                    (name: "Date", value: "Thu Jan  1 02:00:00 2026")
                ],
                bodyData: Data("Body".utf8)
            ),
            to: handle
        )

        let output = try String(contentsOf: url, encoding: .utf8)
        #expect(output.hasPrefix("prefix\n"))
        #expect(output.contains("From stream@example.com Thu Jan  1 02:00:00 2026\nBody\n"))
    }

    @Test("EML export writes headers and raw body")
    func emlExportWritesHeadersAndRawBody() throws {
        let url = try Self.temporaryFile(named: "message.eml")
        let body = "Hello\nFrom line should not be escaped in EML"

        try MBOXExporter().exportToEML(
            message: ImportedMessage(
                headers: [
                    (name: "From", value: "Alice <alice@example.com>"),
                    (name: "Subject", value: "Plain EML")
                ],
                bodyData: Data(body.utf8)
            ),
            to: url
        )

        let output = try String(contentsOf: url, encoding: .utf8)
        #expect(output == "From: Alice <alice@example.com>\nSubject: Plain EML\n\n\(body)")
    }

    @Test("EML export emits each header exactly once (no duplicate header block)")
    func emlExportDoesNotDuplicateHeaders() throws {
        // Regression: the export caller previously passed a full raw message
        // (headers+body) as bodyData while exportToEML also wrote the headers,
        // producing a malformed .eml with the header block twice.
        let url = try Self.temporaryFile(named: "single-headers.eml")
        try MBOXExporter().exportToEML(
            message: ImportedMessage(
                headers: [
                    (name: "From", value: "Bob <bob@example.com>"),
                    (name: "Subject", value: "Once")
                ],
                bodyData: Data("Just the body.".utf8)
            ),
            to: url
        )

        let output = try String(contentsOf: url, encoding: .utf8)
        let fromCount = output.components(separatedBy: "From: Bob <bob@example.com>").count - 1
        let subjectCount = output.components(separatedBy: "Subject: Once").count - 1
        #expect(fromCount == 1)
        #expect(subjectCount == 1)
    }

    @Test("MBOX export reports unwritable destinations")
    func mboxExportReportsUnwritableDestinations() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrevMBOXExporterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        do {
            try MBOXExporter().export(
                messages: [
                    ImportedMessage(
                        headers: [(name: "From", value: "writer@example.com")],
                        bodyData: Data("Body".utf8)
                    )
                ],
                to: directory
            )
            Issue.record("Expected directory export destination to throw.")
        } catch let error as MailExportError {
            #expect(error.localizedDescription.contains("Cannot open file"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    private static func temporaryFile(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrevMBOXExporterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(name)
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [(completed: Int, total: Int)] = []

    var completedValues: [Int] {
        lock.withLock { values.map(\.completed) }
    }

    var totalValues: [Int] {
        lock.withLock { values.map(\.total) }
    }

    func record(completed: Int, total: Int) {
        lock.withLock {
            values.append((completed: completed, total: total))
        }
    }
}
