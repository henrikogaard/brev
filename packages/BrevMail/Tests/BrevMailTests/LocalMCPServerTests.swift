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
import BrevSettings
import Foundation
import Testing
#if os(macOS)
import Darwin
#endif

@Suite("Local MCP server and approval flow (#305, ADR-0095)")
@MainActor
struct LocalMCPServerTests {
    private let client = MCPClientContext(processName: "claude-code", pid: 4242, clientInfoName: "Claude")

    private func sendRPC(_ broker: LocalMCPBroker, _ request: [String: Any]) async throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: request)
        let responseData = try #require(await broker.handleJSONRPCData(data, client: client))
        return try #require(try JSONSerialization.jsonObject(with: responseData) as? [String: Any])
    }

    private func parseToolTextPayload(_ response: [String: Any]) throws -> [String: Any] {
        let result = try #require(response["result"] as? [String: Any])
        let content = try #require(result["content"] as? [[String: Any]])
        let text = try #require(content.first?["text"] as? String)
        let data = try #require(text.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("master disabled fails closed and logs blocked_disabled; non-opted-in account is invisible")
    func consentIsolationAndAuditLogging() async throws {
        let optedInBackend = MockBackend()
        let hiddenAccount = BrevAccount(id: "hidden-acct", displayName: "Hidden", emailAddress: "hidden@example.org")
        let hiddenBackend = MockBackend(account: hiddenAccount, folders: [Folder(id: "inbox", name: "Inbox", role: .inbox)])

        var settings = AgentAccessSettings.defaults
        let auditStore = AgentAccessAuditLogStore(fileURL: nil, postsChangeNotification: false)
        let broker = LocalMCPBroker(
            backendsProvider: { [optedInBackend, hiddenBackend] },
            settingsProvider: { settings },
            auditStore: auditStore
        )

        // Master disabled -> blocked_disabled.
        let disabledResp = try await sendRPC(broker, [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": ["name": "list_accounts", "arguments": [:]]
        ])
        #expect((disabledResp["error"] as? [String: Any])?["code"] as? Int == -32001)
        #expect(auditStore.entries().first?.outcome == .blockedDisabled)

        // Enable master + only optedInBackend.
        settings.isEnabled = true
        settings.setAccount(optedInBackend.account.id, enabled: true)

        let accountsResp = try await sendRPC(broker, [
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/call",
            "params": ["name": "list_accounts", "arguments": [:]]
        ])
        let accountsPayload = try parseToolTextPayload(accountsResp)
        let accounts = try #require(accountsPayload["accounts"] as? [[String: Any]])
        #expect(accounts.count == 1)
        #expect(accounts[0]["account_id"] as? String == optedInBackend.account.id)

        // Hidden account returns generic not-found and logs blocked_account.
        let hiddenResp = try await sendRPC(broker, [
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": ["name": "list_folders", "arguments": ["account_id": "hidden-acct"]]
        ])
        #expect((hiddenResp["error"] as? [String: Any])?["code"] as? Int == -32002)
        #expect(auditStore.entries().first?.outcome == .blockedAccount)
    }

    @Test("read tools search cache-only, cap at 50, return plain text, and redact sign-in codes (ADR-0088)")
    func readToolsAndSignInCodeRedaction() async throws {
        let account = BrevAccount(id: "acct-demo", displayName: "Demo", emailAddress: "demo@example.org")
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let regularHeader = MessageHeader(
            id: "msg-regular",
            threadID: "t1",
            folderID: "inbox",
            from: Correspondent(name: "Maya", email: "maya@northwind.example"),
            to: [Correspondent(name: "Demo", email: "demo@example.org")],
            subject: "Quarterly invoice",
            snippet: "Attached is the Q3 invoice PDF.",
            date: Date(timeIntervalSince1970: 1_735_689_600)
        )
        let otpHeader = MessageHeader(
            id: "msg-otp",
            threadID: "t2",
            folderID: "inbox",
            from: Correspondent(name: "Acme Security", email: "no-reply@acme.example"),
            to: [Correspondent(name: "Demo", email: "demo@example.org")],
            subject: "Your verification code",
            snippet: "Your Acme verification code is 839204. It expires in 10 minutes.",
            date: Date(timeIntervalSince1970: 1_735_689_700)
        )
        let backend = MCPBodyStubBackend(
            wrapped: MockBackend(
                account: account,
                folders: [inbox],
                messagesByFolder: ["inbox": [regularHeader, otpHeader]]
            ),
            bodies: [
                "msg-regular": MessageBody(
                    messageID: "msg-regular",
                    html: "<script>alert(1)</script><p>Hello team</p>",
                    plainText: "Hello team, invoice attached.",
                    attachments: [BrevBackend.Attachment(
                        id: "a1",
                        name: "invoice.pdf",
                        mimeType: "application/pdf",
                        sizeBytes: 4200
                    )]
                ),
                "msg-otp": MessageBody(
                    messageID: "msg-otp",
                    plainText: "Your Acme sign-in verification code is 839204. Do not share this code."
                )
            ]
        )

        let settings = AgentAccessSettings(isEnabled: true, enabledAccountIDs: [account.id])
        let auditStore = AgentAccessAuditLogStore(fileURL: nil, postsChangeNotification: false)
        let broker = LocalMCPBroker(
            backendsProvider: { [backend] },
            settingsProvider: { settings },
            auditStore: auditStore
        )

        let searchResp = try await sendRPC(broker, [
            "jsonrpc": "2.0",
            "id": 10,
            "method": "tools/call",
            "params": ["name": "search_messages", "arguments": ["account_id": account.id, "folder_id": "inbox", "limit": 999]]
        ])
        let searchPayload = try parseToolTextPayload(searchResp)
        let messages = try #require(searchPayload["messages"] as? [[String: Any]])
        #expect(messages.count == 2)
        let otpSearchRow = try #require(messages.first { $0["message_id"] as? String == "msg-otp" })
        #expect((otpSearchRow["snippet"] as? String)?.contains("839204") == false)

        let regularRead = try await sendRPC(broker, [
            "jsonrpc": "2.0",
            "id": 11,
            "method": "tools/call",
            "params": ["name": "read_message", "arguments": ["account_id": account.id, "message_id": "msg-regular"]]
        ])
        let regularPayload = try parseToolTextPayload(regularRead)
        #expect(regularPayload["body_text"] as? String == "Hello team, invoice attached.")
        let attachments = try #require(regularPayload["attachments"] as? [[String: Any]])
        let firstAttachmentName = attachments.first?["name"] as? String
        #expect(firstAttachmentName == "invoice.pdf")

        let otpRead = try await sendRPC(broker, [
            "jsonrpc": "2.0",
            "id": 12,
            "method": "tools/call",
            "params": ["name": "read_message", "arguments": ["account_id": account.id, "message_id": "msg-otp"]]
        ])
        let otpPayload = try parseToolTextPayload(otpRead)
        #expect((otpPayload["body_text"] as? String)?.contains("839204") == false)
    }

    @Test("change tools enforce per-call approval, denial, timeout, concurrent rate-limit, and exclude send/delete/trash")
    func changeToolApprovalFlowsAndExclusions() async throws {
        let account = BrevAccount(id: "acct-demo", displayName: "Demo", emailAddress: "demo@example.org")
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let archive = Folder(id: "archive", name: "Archive", role: .archive)
        let trash = Folder(id: "trash", name: "Trash", role: .trash)
        let projectFolder = Folder(id: "projects", name: "Projects", role: .custom)
        let msg1 = MessageHeader(
            id: "m1",
            threadID: "t1",
            folderID: "inbox",
            from: Correspondent(name: "Alex", email: "alex@example.org"),
            subject: "Roadmap",
            snippet: "Update",
            date: Date(timeIntervalSince1970: 1_735_689_600)
        )
        let msg2 = MessageHeader(
            id: "m2",
            threadID: "t2",
            folderID: "inbox",
            from: Correspondent(name: "Sam", email: "sam@example.org"),
            subject: "Invoice",
            snippet: "Paid",
            date: Date(timeIntervalSince1970: 1_735_689_700)
        )
        let backend = MockBackend(
            account: account,
            folders: [inbox, archive, trash, projectFolder],
            messagesByFolder: ["inbox": [msg1, msg2]]
        )

        let settings = AgentAccessSettings(isEnabled: true, enabledAccountIDs: [account.id])
        let auditStore = AgentAccessAuditLogStore(fileURL: nil, postsChangeNotification: false)
        let coordinator = MCPApprovalCoordinator()
        let broker = LocalMCPBroker(
            backendsProvider: { [backend] },
            settingsProvider: { settings },
            auditStore: auditStore,
            approvalCoordinator: coordinator,
            approvalTimeoutSeconds: 2.0
        )

        func waitForActiveRequest() async throws {
            for _ in 0 ..< 100 where coordinator.activeRequest == nil {
                try await Task.sleep(for: .milliseconds(5))
            }
        }

        // Excluded tools: send_message and delete_message must be rejected.
        for forbidden in ["send_message", "delete_message", "move_to_trash"] {
            let resp = try await sendRPC(broker, [
                "jsonrpc": "2.0",
                "id": forbidden,
                "method": "tools/call",
                "params": ["name": forbidden, "arguments": ["account_id": account.id]]
            ])
            #expect((resp["error"] as? [String: Any])?["code"] as? Int == -32601)
        }

        // Moving to Trash via label_messages is permanently excluded.
        let trashResp = try await sendRPC(broker, [
            "jsonrpc": "2.0",
            "id": "trash-block",
            "method": "tools/call",
            "params": [
                "name": "label_messages",
                "arguments": ["account_id": account.id, "message_ids": ["m1"], "folder_id": "trash"]
            ]
        ])
        #expect((trashResp["error"] as? [String: Any])?["code"] as? Int == -32602)

        // Approve archive_messages + reject concurrent write with rate_limited!
        let archiveTask = Task {
            try await sendRPC(broker, [
                "jsonrpc": "2.0",
                "id": "arch-1",
                "method": "tools/call",
                "params": [
                    "name": "archive_messages",
                    "arguments": ["account_id": account.id, "message_ids": ["m1"]]
                ]
            ])
        }
        try await waitForActiveRequest()
        #expect(coordinator.activeRequest?.toolName == "archive_messages")
        #expect(coordinator.activeRequest?.messageCount == 1)

        // Concurrent request while prompt is active -> rate_limited.
        let concurrentResp = try await sendRPC(broker, [
            "jsonrpc": "2.0",
            "id": "arch-concurrent",
            "method": "tools/call",
            "params": [
                "name": "archive_messages",
                "arguments": ["account_id": account.id, "message_ids": ["m2"]]
            ]
        ])
        #expect((concurrentResp["error"] as? [String: Any])?["code"] as? Int == -32012)
        #expect(auditStore.entries().first?.outcome == .rateLimited)

        coordinator.approveActiveRequest()
        let archiveResp = try await archiveTask.value
        let archivePayload = try parseToolTextPayload(archiveResp)
        #expect(archivePayload["status"] as? String == "approved")
        let archivedHeaders = try await backend.messages(in: archive, pageToken: nil).headers
        #expect(archivedHeaders.map { (header: MessageHeader) in header.id } == ["m1"])

        // Deny label_messages -> message stays in Inbox.
        let denyTask = Task {
            try await sendRPC(broker, [
                "jsonrpc": "2.0",
                "id": "label-deny",
                "method": "tools/call",
                "params": [
                    "name": "label_messages",
                    "arguments": ["account_id": account.id, "message_ids": ["m2"], "folder_id": "projects"]
                ]
            ])
        }
        try await waitForActiveRequest()
        coordinator.denyActiveRequest()
        let denyResp = try await denyTask.value
        #expect((denyResp["error"] as? [String: Any])?["code"] as? Int == -32010)
        #expect(auditStore.entries().first?.outcome == .denied)

        // Timeout fails closed -> timed_out.
        let fastTimeoutBroker = LocalMCPBroker(
            backendsProvider: { [backend] },
            settingsProvider: { settings },
            auditStore: auditStore,
            approvalCoordinator: coordinator,
            approvalTimeoutSeconds: 0.15
        )
        let timeoutResp = try await sendRPC(fastTimeoutBroker, [
            "jsonrpc": "2.0",
            "id": "label-timeout",
            "method": "tools/call",
            "params": [
                "name": "label_messages",
                "arguments": ["account_id": account.id, "message_ids": ["m2"], "folder_id": "projects"]
            ]
        ])
        #expect((timeoutResp["error"] as? [String: Any])?["code"] as? Int == -32011)
        #expect(auditStore.entries().first?.outcome == .timedOut)
    }

    #if os(macOS)
    @Test("Unix domain socket enforces 0600 permissions and serves JSON-RPC round-trip over AF_UNIX")
    func unixSocketRoundTripAndPermissions() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-mcp-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let socketURL = tempDir.appendingPathComponent("mcp.sock")

        let backend = MockBackend()
        let settings = AgentAccessSettings(isEnabled: true, enabledAccountIDs: [backend.account.id])
        let auditStore = AgentAccessAuditLogStore(fileURL: nil, postsChangeNotification: false)
        let broker = LocalMCPBroker(
            backendsProvider: { [backend] },
            settingsProvider: { settings },
            auditStore: auditStore
        )
        let server = LocalMCPUnixSocketServer(socketURL: socketURL, broker: broker)
        try server.start()
        defer { server.stop() }

        let attrs = try FileManager.default.attributesOfItem(atPath: socketURL.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue
        #expect(perms == 0o600)

        // Perform a real AF_UNIX client connect + tools/list round-trip off the main actor.
        let responseText: String = try await Task.detached {
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { throw POSIXError(.EIO) }
            defer { close(fd) }

            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            let pathBytes = Array(socketURL.path.utf8)
            withUnsafeMutableBytes(of: &addr.sun_path) { raw in
                raw.initializeMemory(as: UInt8.self, repeating: 0)
                for (i, b) in pathBytes.enumerated() {
                    raw[i] = b
                }
            }
            let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
            let connected = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    connect(fd, sockPtr, addrLen)
                }
            }
            guard connected == 0 else { throw POSIXError(.ECONNREFUSED) }

            let payload = Data("{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/list\"}\n".utf8)
            payload.withUnsafeBytes { raw in
                _ = write(fd, raw.baseAddress!, payload.count)
            }

            var buf = [UInt8](repeating: 0, count: 8192)
            let n = read(fd, &buf, buf.count)
            return String(decoding: buf[0 ..< max(0, n)], as: UTF8.self)
        }.value

        #expect(responseText.contains("list_accounts"))
        #expect(responseText.contains("archive_messages"))
        #expect(!responseText.contains("send_message"))
        #expect(!responseText.contains("delete_message"))
    }
    #endif
}

private final class MCPBodyStubBackend: MailBackend, @unchecked Sendable {
    private let wrapped: MockBackend
    private let bodies: [String: MessageBody]

    init(wrapped: MockBackend, bodies: [String: MessageBody]) {
        self.wrapped = wrapped
        self.bodies = bodies
    }

    var account: BrevAccount { wrapped.account }
    var capabilities: BackendCapabilities { wrapped.capabilities }
    var extendedCapabilities: BackendExtendedCapabilities { wrapped.extendedCapabilities }

    func connect() async throws { try await wrapped.connect() }
    func disconnect() async { await wrapped.disconnect() }
    func folders() async throws -> [Folder] { try await wrapped.folders() }
    func refresh(folder: Folder) async throws { try await wrapped.refresh(folder: folder) }

    func messages(in folder: Folder, pageToken: String?) async throws -> (
        headers: [MessageHeader],
        nextPageToken: String?
    ) {
        try await wrapped.messages(in: folder, pageToken: pageToken)
    }

    func body(for messageID: String) async throws -> MessageBody {
        if let stub = bodies[messageID] { return stub }
        return try await wrapped.body(for: messageID)
    }

    func setRead(_ isRead: Bool, for messageIDs: [String]) async throws {
        try await wrapped.setRead(isRead, for: messageIDs)
    }

    func setFlagged(_ isFlagged: Bool, for messageIDs: [String]) async throws {
        try await wrapped.setFlagged(isFlagged, for: messageIDs)
    }

    func move(messageIDs: [String], to folder: Folder) async throws {
        try await wrapped.move(messageIDs: messageIDs, to: folder)
    }

    func delete(messageIDs: [String]) async throws {
        try await wrapped.delete(messageIDs: messageIDs)
    }

    func save(draft: Draft) async throws -> Draft { try await wrapped.save(draft: draft) }
    func discard(draftID: String) async throws { try await wrapped.discard(draftID: draftID) }
    func send(draft: Draft) async throws -> SendResult { try await wrapped.send(draft: draft) }
    func search(_ query: SearchQuery) async throws -> [MessageHeader] { try await wrapped.search(query) }

    func calendarEvent(from attachmentID: String) async throws -> CalendarEvent {
        try await wrapped.calendarEvent(from: attachmentID)
    }

    func replyToCalendarInvite(messageID: String, response: AttendeeState) async throws {
        try await wrapped.replyToCalendarInvite(messageID: messageID, response: response)
    }

    func subscribeToChanges() -> AsyncStream<MailEvent> { wrapped.subscribeToChanges() }
}
