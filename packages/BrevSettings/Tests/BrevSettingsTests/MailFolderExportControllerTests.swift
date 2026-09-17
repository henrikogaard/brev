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
@testable import BrevSettings
import Foundation
import Testing

@Suite("Folder export presentation lifecycle")
@MainActor
struct MailFolderExportControllerTests {
    @Test("an export failure settles and allows a new attempt")
    func failureAllowsRetry() async throws {
        let controller = MailFolderExportController()
        let backend = MockBackend()
        let exporter = MailFolderExporter(backend: backend,
                                          sourceID: MailSourceID(accountID: backend.account.id, mailboxID: backend.account.id),
                                          folder: Folder(id: "inbox", name: "Inbox", role: .inbox))
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("brev-export-\(UUID().uuidString).mbox")
        let first = try #require(controller.start(exporter, to: target, format: .mbox, sourceTitle: "First Inbox"))
        await first.value
        if case .failed = controller.state {} else { Issue.record("Expected a visible export failure") }
        #expect(!controller.isRunning)
        let retry = try #require(controller.start(exporter, to: target, format: .mbox, sourceTitle: "Second Inbox"))
        await retry.value
        #expect(controller.sourceTitle == "Second Inbox")
        #expect(!controller.isRunning)
        controller.dismiss()
        #expect(controller.state == .idle)
    }

    @Test("successful exports settle and duplicate starts do not replace their source")
    func successAndSingleFlight() async throws {
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("brev-export-\(UUID().uuidString).mbox")
        defer { try? FileManager.default.removeItem(at: target) }
        let controller = MailFolderExportController()
        let exporter = try await Self.emptyExporter()
        let task = try #require(controller.start(exporter, to: target, format: .mbox, sourceTitle: "Inbox · Work"))
        #expect(controller.start(exporter, to: target, format: .mbox, sourceTitle: "Wrong source") == nil)
        #expect(controller.sourceTitle == "Inbox · Work")
        await task.value
        #expect(controller.state == .completed(target, 0))
        #expect(!controller.isRunning)
    }

    @Test("canceling an owned export preserves the previous output")
    func cancellationSettles() async throws {
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("brev-export-\(UUID().uuidString).mbox")
        defer { try? FileManager.default.removeItem(at: target) }
        let original = Data("Keep me".utf8)
        try original.write(to: target)
        let controller = MailFolderExportController()
        let exporter = try await Self.emptyExporter()
        let task = try #require(controller.start(exporter, to: target, format: .mbox, sourceTitle: "Inbox"))
        controller.cancel()
        await task.value
        #expect(controller.state == .cancelled)
        #expect(!controller.isRunning)
        #expect(try Data(contentsOf: target) == original)
    }

    @Test("a destination chosen for a retired mailbox session cannot start an export")
    func retiredPickerCannotStartExport() async throws {
        let controller = MailFolderExportController()
        let exporter = try await Self.emptyExporter()
        let token = controller.sessionToken
        let first = NSObject(), second = NSObject(), replacement = NSObject()
        let previous = [ObjectIdentifier(first), ObjectIdentifier(second)]
        // Account B stays selected while account A's backend is replaced.
        controller.reconcileSessions(previous: previous, current: [ObjectIdentifier(replacement), ObjectIdentifier(second)])
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("brev-export-\(UUID().uuidString).mbox")
        defer { try? FileManager.default.removeItem(at: target) }
        let task = controller.start(exporter, to: target, format: .mbox, sourceTitle: "Retired", sessionToken: token)
        await task?.value
        #expect(task == nil)
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }

    @Test("adding or reordering live accounts preserves a captured export session")
    func liveSessionsKeepPickerValid() {
        let controller = MailFolderExportController()
        let first = NSObject(), second = NSObject(), added = NSObject()
        let token = controller.sessionToken
        controller.reconcileSessions(previous: [ObjectIdentifier(first), ObjectIdentifier(second)],
                                     current: [ObjectIdentifier(second), ObjectIdentifier(added), ObjectIdentifier(first)])
        #expect(controller.sessionToken == token)
    }

    private static func emptyExporter() async throws -> MailFolderExporter {
        let account = BrevAccount(id: "export-controller", displayName: "Work", emailAddress: "work@example.org")
        let folder = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        let configuration = IMAPAccountConfiguration(accountID: account.id, emailAddress: account.emailAddress,
                                                     displayName: account.displayName,
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
                                                     credentialID: account.id)
        let credential = MailAccountCredential(incomingUsername: account.emailAddress, outgoingUsername: account.emailAddress,
                                               secret: "fixture", authentication: .password)
        let backend = IMAPSMTPBackend(account: account, configuration: configuration, credential: credential,
                                      listFolders: { _, _ in [IMAPFolderListing(
                                          path: "INBOX",
                                          displayName: "Inbox",
                                          delimiter: "/",
                                          flags: [],
                                          role: .inbox
                                      )] },
                                      listMessages: { _, _, _, _, _ in IMAPMessageListingPage(messages: [], nextPageToken: nil) },
                                      fetchMessageSource: { _, _, _, uid in IMAPMessageSource(
                                          uid: uid,
                                          rawMessageData: Data("Unused".utf8)
                                      ) })
        try await backend.connect()
        return MailFolderExporter(
            backend: backend,
            sourceID: MailSourceID(accountID: account.id, mailboxID: account.id),
            folder: folder
        )
    }
}
