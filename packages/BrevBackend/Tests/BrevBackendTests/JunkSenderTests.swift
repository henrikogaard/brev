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

@Suite("Junk and block-sender capability gates")
struct JunkSenderTests {
    // MARK: - BackendCapabilities

    @Test("junkAPI and blockSender are distinct capability bits")
    func junkAPIAndBlockSenderAreDistinctBits() {
        let caps: BackendCapabilities = [.junkAPI, .blockSender]
        #expect(caps.contains(.junkAPI))
        #expect(caps.contains(.blockSender))
        #expect(!caps.contains(.serverSideSearch))
    }

    @Test("full mock capability set includes junk and blockSender")
    func fullMockCapabilitySetIncludesJunkAndBlockSender() {
        let backend = MockBackend()
        #expect(backend.capabilities.contains(.junkAPI))
        #expect(backend.capabilities.contains(.blockSender))
    }

    // MARK: - MockBackend.setJunk

    @Test("setJunk moves a message to the spam folder when isJunk is true")
    func setJunkMovesToSpam() async throws {
        let backend = MockBackend()
        let folders = try await backend.folders()
        let inbox = try #require(folders.first { $0.role == .inbox })
        let inboxMessages = try await backend.messages(in: inbox, pageToken: nil)
        let firstMessage = try #require(inboxMessages.headers.first)

        try await backend.setJunk(true, for: [firstMessage.id])

        let afterSpam = try await backend.folders()
        let spamFolder = try #require(afterSpam.first { $0.role == .spam })
        let spamMessages = try await backend.messages(in: spamFolder, pageToken: nil)
        #expect(spamMessages.headers.contains { $0.id == firstMessage.id })
    }

    @Test("setJunk without the capability throws notSupported")
    func setJunkWithoutCapabilityThrows() async throws {
        let backend = MockBackend(capabilities: [.serverSideSearch])
        let folders = try await backend.folders()
        let inbox = try #require(folders.first { $0.role == .inbox })
        let messages = try await backend.messages(in: inbox, pageToken: nil)
        let firstMessage = try #require(messages.headers.first)

        await #expect(throws: MailBackendError.self) {
            try await backend.setJunk(true, for: [firstMessage.id])
        }
    }

    // MARK: - MockBackend.blockSender

    @Test("blockSender records the sender email in the blocked set")
    func blockSenderRecordsSenderEmail() async throws {
        let backend = MockBackend()
        let email = "spammer@example.org"

        try await backend.blockSender(email: email)

        // Access the store's blocked senders indirectly through the test hook.
        let blocked = await backend.blockedSenders
        #expect(blocked.contains(email.lowercased()))
    }

    @Test("blockSender without the capability throws notSupported")
    func blockSenderWithoutCapabilityThrows() async throws {
        let backend = MockBackend(capabilities: [.serverSideSearch])

        await #expect(throws: MailBackendError.self) {
            try await backend.blockSender(email: "bad@example.com")
        }
    }
}
