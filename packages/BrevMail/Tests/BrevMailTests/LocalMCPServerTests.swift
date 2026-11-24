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
        let trash = Folder(id: "trash", name: "Trash", role: .trash)
        let spam = Folder(id: "spam", name: "Spam", role: .spam)
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
            subject: "Your verification code is 839204",
            snippet: "Your Acme verification code is 839204. Click here to unsubscribe.",
            date: Date(timeIntervalSince1970: 1_735_689_700)
        )
        let uncachedHeader = MessageHeader(
            id: "msg-uncached",
            threadID: "t3",
            folderID: "inbox",
            from: Correspondent(name: "Ops", email: "ops@example.org"),
            subject: "Uncached body",
            snippet: "Header only",
            date: Date(timeIntervalSince1970: 1_735_689_750)
        )
        let trashHeader = MessageHeader(
            id: "msg-trash",
            threadID: "t4",
            folderID: "trash",
            from: Correspondent(name: "Trash Sender", email: "trash@example.org"),
            subject: "Deleted secret",
            snippet: "Should never appear",
            date: Date(timeIntervalSince1970: 1_735_689_800)
        )
        let spamHeader = MessageHeader(
            id: "msg-spam",
            threadID: "t5",
            folderID: "spam",
            from: Correspondent(name: "Spam Sender", email: "spam@example.org"),
            subject: "Junk mail",
            snippet: "Should never appear",
            date: Date(timeIntervalSince1970: 1_735_689_850)
        )
        let backend = MCPBodyStubBackend(
            wrapped: MockBackend(
                account: account,
                folders: [inbox, trash, spam],
                messagesByFolder: [
                    "inbox": [regularHeader, otpHeader, uncachedHeader],
                    "trash": [trashHeader],
                    "spam": [spamHeader]
                ]
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
                    plainText: "Your Acme sign-in verification code is 839204. Click here to unsubscribe."
                ),
                "msg-trash": MessageBody(
                    messageID: "msg-trash",
                    plainText: "Deleted body"
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

        // Unscoped search must exclude Trash and Spam and redact OTPs in subjects & snippets even with unsubscribe text.
        let searchResp = try await sendRPC(broker, [
            "jsonrpc": "2.0",
            "id": 10,
            "method": "tools/call",
            "params": ["name": "search_messages", "arguments": ["account_id": account.id, "query": "e", "limit": 999]]
        ])
        let searchPayload = try parseToolTextPayload(searchResp)
        let messages = try #require(searchPayload["messages"] as? [[String: Any]])
        let messageIDs = Set(messages.compactMap { $0["message_id"] as? String })
        #expect(!messageIDs.contains("msg-trash"))
        #expect(!messageIDs.contains("msg-spam"))
        #expect(messageIDs.contains("msg-regular"))
        #expect(messageIDs.contains("msg-otp"))
        let otpSearchRow = try #require(messages.first { $0["message_id"] as? String == "msg-otp" })
        #expect((otpSearchRow["subject"] as? String)?.contains("839204") == false)
        #expect((otpSearchRow["snippet"] as? String)?.contains("839204") == false)

        // Explicit Trash search and Trash read must be rejected.
        let trashSearch = try await sendRPC(broker, [
            "jsonrpc": "2.0",
            "id": 101,
            "method": "tools/call",
            "params": ["name": "search_messages", "arguments": ["account_id": account.id, "folder_id": "trash"]]
        ])
        #expect((trashSearch["error"] as? [String: Any])?["code"] as? Int == -32602)

        let trashRead = try await sendRPC(broker, [
            "jsonrpc": "2.0",
            "id": 102,
            "method": "tools/call",
            "params": ["name": "read_message", "arguments": ["account_id": account.id, "message_id": "msg-trash"]]
        ])
        #expect((trashRead["error"] as? [String: Any])?["code"] as? Int == -32602)

        // Uncached body fails closed with cache-miss error and NEVER calls network-fetching body(for:).
        let uncachedRead = try await sendRPC(broker, [
            "jsonrpc": "2.0",
            "id": 103,
            "method": "tools/call",
            "params": ["name": "read_message", "arguments": ["account_id": account.id, "message_id": "msg-uncached"]]
        ])
        #expect((uncachedRead["error"] as? [String: Any])?["code"] as? Int == -32004)
        #expect(backend.networkBodyFetchCount == 0)

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
        #expect((otpPayload["subject"] as? String)?.contains("839204") == false)
        #expect((otpPayload["body_text"] as? String)?.contains("839204") == false)
        #expect(backend.networkBodyFetchCount == 0)
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

        // Stopping the server must terminate active client connections immediately.
        let closedOnStop: Bool = try await Task.detached {
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

            // Perform one request so the server has definitely accepted and registered the fd.
            let ping = Data("{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"tools/list\"}\n".utf8)
            ping.withUnsafeBytes { raw in
                _ = write(fd, raw.baseAddress!, ping.count)
            }
            var buf = [UInt8](repeating: 0, count: 4096)
            _ = read(fd, &buf, buf.count)

            server.stop()

            let afterStop = read(fd, &buf, buf.count)
            return afterStop <= 0
        }.value
        #expect(closedOnStop)
    }
    #endif

    @Test(
        "validation failures are audited, previews scan folders once, Trash/Spam overrides inbox, and mid-flight revocation fails closed"
    )
    func auditValidationBatchPreviewTrashMembershipAndMidFlightRevocation() async throws {
        let account = BrevAccount(id: "acct-sec", displayName: "Security", emailAddress: "sec@example.org")
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let archive = Folder(id: "archive", name: "Archive", role: .archive)
        let trash = Folder(id: "trash", name: "Trash", role: .trash)
        let msg1 = MessageHeader(
            id: "m1",
            threadID: "t1",
            folderID: "inbox",
            from: Correspondent(name: "Alice", email: "alice@example.org"),
            subject: "First",
            snippet: "Hello",
            date: Date(timeIntervalSince1970: 1_735_689_600)
        )
        let msg2 = MessageHeader(
            id: "m2",
            threadID: "t2",
            folderID: "inbox",
            from: Correspondent(name: "Bob", email: "bob@example.org"),
            subject: "Second",
            snippet: "Hello",
            date: Date(timeIntervalSince1970: 1_735_689_610)
        )
        let msg3 = MessageHeader(
            id: "m3",
            threadID: "t3",
            folderID: "inbox",
            from: Correspondent(name: "Cara", email: "cara@example.org"),
            subject: "Third",
            snippet: "Hello",
            date: Date(timeIntervalSince1970: 1_735_689_620)
        )
        // Simulates a multi-label message present in both Inbox and Trash.
        let dualInboxCopy = MessageHeader(
            id: "m-dual",
            threadID: "t4",
            folderID: "inbox",
            from: Correspondent(name: "Dual", email: "dual@example.org"),
            subject: "In both inbox and trash",
            snippet: "Hidden",
            date: Date(timeIntervalSince1970: 1_735_689_630)
        )
        let dualTrashCopy = MessageHeader(
            id: "m-dual",
            threadID: "t4",
            folderID: "trash",
            from: Correspondent(name: "Dual", email: "dual@example.org"),
            subject: "In both inbox and trash",
            snippet: "Hidden",
            date: Date(timeIntervalSince1970: 1_735_689_630)
        )

        @MainActor
        final class RevocationState {
            var settings: AgentAccessSettings
            var revokeOnBodyRead = false
            init(settings: AgentAccessSettings) { self.settings = settings }
        }
        let state = RevocationState(settings: AgentAccessSettings(isEnabled: true, enabledAccountIDs: [account.id]))
        let auditStore = AgentAccessAuditLogStore(fileURL: nil, postsChangeNotification: false)
        let coordinator = MCPApprovalCoordinator(canDisplayUI: true)

        let backend = MCPBodyStubBackend(
            wrapped: MockBackend(
                account: account,
                folders: [inbox, archive, trash],
                messagesByFolder: [
                    "inbox": [msg1, msg2, msg3, dualInboxCopy],
                    "archive": [],
                    "trash": [dualTrashCopy]
                ]
            ),
            bodies: [
                "m1": MessageBody(messageID: "m1", plainText: "Secret body"),
                "m-dual": MessageBody(messageID: "m-dual", plainText: "Deleted dual body")
            ],
            onCachedBodyRead: { @MainActor in
                if state.revokeOnBodyRead {
                    state.settings.isEnabled = false
                }
            }
        )
        let broker = LocalMCPBroker(
            backendsProvider: { [backend] },
            settingsProvider: { state.settings },
            auditStore: auditStore,
            approvalCoordinator: coordinator,
            approvalTimeoutSeconds: 2
        )

        // 1. Multi-label Trash message is excluded from both search_messages and read_message.
        let searchResp = try await sendRPC(broker, [
            "jsonrpc": "2.0",
            "id": 201,
            "method": "tools/call",
            "params": ["name": "search_messages", "arguments": ["account_id": account.id, "query": ""]]
        ])
        let searchPayload = try parseToolTextPayload(searchResp)
        let listedIDs = Set((searchPayload["messages"] as? [[String: Any]] ?? []).compactMap { $0["message_id"] as? String })
        #expect(!listedIDs.contains("m-dual"))

        let dualRead = try await sendRPC(broker, [
            "jsonrpc": "2.0",
            "id": 202,
            "method": "tools/call",
            "params": ["name": "read_message", "arguments": ["account_id": account.id, "message_id": "m-dual"]]
        ])
        #expect((dualRead["error"] as? [String: Any])?["code"] as? Int == -32602)

        // 2. Rejected validation calls in handleChangeMessages are recorded in audit history.
        let emptyBatch = try await sendRPC(broker, [
            "jsonrpc": "2.0",
            "id": 203,
            "method": "tools/call",
            "params": ["name": "archive_messages", "arguments": ["account_id": account.id, "message_ids": []]]
        ])
        #expect((emptyBatch["error"] as? [String: Any])?["code"] as? Int == -32602)
        #expect(auditStore.entries().first?.parameterSummary == "empty_message_ids")
        #expect(auditStore.entries().first?.outcome == .denied)

        let missingFolder = try await sendRPC(broker, [
            "jsonrpc": "2.0",
            "id": 204,
            "method": "tools/call",
            "params": [
                "name": "label_messages",
                "arguments": ["account_id": account.id, "message_ids": ["m1"], "folder_id": "nonexistent"]
            ]
        ])
        #expect((missingFolder["error"] as? [String: Any])?["code"] as? Int == -32005)
        #expect(auditStore.entries().first?.parameterSummary == "folder_not_found folder=nonexistent")

        // 3. Approval preview for 3 messages scans Inbox only once instead of repeating per message.
        backend.resetSearchCallCount()
        let approveTask = Task {
            try await sendRPC(broker, [
                "jsonrpc": "2.0",
                "id": 205,
                "method": "tools/call",
                "params": ["name": "archive_messages", "arguments": ["account_id": account.id, "message_ids": ["m1", "m2", "m3"]]]
            ])
        }
        while coordinator.activeRequest == nil {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(coordinator.activeRequest?.previews.count == 3)
        #expect(backend.searchCallCount == 1)
        coordinator.denyActiveRequest()
        _ = try await approveTask.value

        // 4. Mid-flight revocation during read_message fails closed instead of returning the body.
        state.revokeOnBodyRead = true
        let revokedRead = try await sendRPC(broker, [
            "jsonrpc": "2.0",
            "id": 206,
            "method": "tools/call",
            "params": ["name": "read_message", "arguments": ["account_id": account.id, "message_id": "m1"]]
        ])
        #expect((revokedRead["error"] as? [String: Any])?["code"] as? Int == -32001)
        #expect(revokedRead["result"] == nil)
        #expect(auditStore.entries().first?.outcome == .blockedDisabled)
    }

    @Test("unlabeled archived messages are readable via unscoped cache fallback and rejected reads never log sign-in codes")
    func unlabeledArchivedReadAndAuditRedaction() async throws {
        let account = BrevAccount(id: "acct-gmail", displayName: "Gmail", emailAddress: "user@gmail.example")
        let inbox = Folder(id: "INBOX", name: "Inbox", role: .inbox)
        let trash = Folder(id: "TRASH", name: "Trash", role: .trash)
        // Archived Gmail message with empty label list resolves to synthetic ALL_MAIL, which is not in `folders`.
        let archivedHeader = MessageHeader(
            id: "gm-archived-1",
            threadID: "t-arch",
            folderID: "ALL_MAIL",
            from: Correspondent(name: "Bank", email: "statements@bank.example"),
            subject: "Annual statement",
            snippet: "Your 2026 statement is ready.",
            date: Date(timeIntervalSince1970: 1_735_689_900)
        )
        let backend = MCPBodyStubBackend(
            wrapped: MockBackend(
                account: account,
                folders: [inbox, trash],
                messagesByFolder: ["INBOX": [], "TRASH": []]
            ),
            bodies: [
                "gm-archived-1": MessageBody(
                    messageID: "gm-archived-1",
                    plainText: "Annual statement body."
                )
            ],
            unscopedExtraHeaders: [archivedHeader]
        )

        let settings = AgentAccessSettings(isEnabled: true, enabledAccountIDs: [account.id])
        let auditStore = AgentAccessAuditLogStore(fileURL: nil, postsChangeNotification: false)
        let broker = LocalMCPBroker(
            backendsProvider: { [backend] },
            settingsProvider: { settings },
            auditStore: auditStore
        )

        let readResp = try await sendRPC(broker, [
            "jsonrpc": "2.0",
            "id": 301,
            "method": "tools/call",
            "params": ["name": "read_message", "arguments": ["account_id": account.id, "message_id": "gm-archived-1"]]
        ])
        let payload = try parseToolTextPayload(readResp)
        #expect(payload["body_text"] as? String == "Annual statement body.")
        #expect(payload["folder_id"] as? String == "ALL_MAIL")

        // Rejected reads supplying a sign-in code as `message_id` must NEVER write that value to the audit log.
        for injectedID in ["839204", "Your verification code is 839204"] {
            let missResp = try await sendRPC(broker, [
                "jsonrpc": "2.0",
                "id": "miss-\(injectedID)",
                "method": "tools/call",
                "params": ["name": "read_message", "arguments": ["account_id": account.id, "message_id": injectedID]]
            ])
            #expect((missResp["error"] as? [String: Any])?["code"] as? Int == -32004)
            let lastEntry = try #require(auditStore.entries().first)
            #expect(lastEntry.parameterSummary == "header_cache_miss")
            #expect(!lastEntry.parameterSummary.contains("839204"))
        }
    }

    #if os(macOS)
    @Test("socket ownership prevents unstarted stop() or competing start() from removing a live listener's socket")
    func socketOwnershipProtectsLiveListenerAndCleansStaleSocket() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-own-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let socketURL = tempDir.appendingPathComponent("mcp.sock")

        let backend = MockBackend()
        let settings = AgentAccessSettings(isEnabled: true, enabledAccountIDs: [backend.account.id])
        let broker = LocalMCPBroker(
            backendsProvider: { [backend] },
            settingsProvider: { settings },
            auditStore: AgentAccessAuditLogStore(fileURL: nil, postsChangeNotification: false)
        )

        let primary = LocalMCPUnixSocketServer(socketURL: socketURL, broker: broker)
        try primary.start()
        defer { primary.stop() }

        // Simulates Nightly launching with Agent access off: stop() without start() must NOT unlink primary's socket.
        let unstartedSecondary = LocalMCPUnixSocketServer(socketURL: socketURL, broker: broker)
        unstartedSecondary.stop()
        #expect(FileManager.default.fileExists(atPath: socketURL.path))

        // Competing start() against a live listener must fail with EADDRINUSE and preserve the live socket file.
        let competingSecondary = LocalMCPUnixSocketServer(socketURL: socketURL, broker: broker)
        do {
            try competingSecondary.start()
            Issue.record("Expected competing start() against a live socket to throw EADDRINUSE")
        } catch let error as POSIXError {
            #expect(error.code == .EADDRINUSE)
        }
        #expect(FileManager.default.fileExists(atPath: socketURL.path))

        // Stop primary, create an abandoned stale socket file, and verify a fresh start() replaces it cleanly.
        primary.stop()
        #expect(!FileManager.default.fileExists(atPath: socketURL.path))

        let staleFD = socket(AF_UNIX, SOCK_STREAM, 0)
        #expect(staleFD >= 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        for (idx, byte) in socketURL.path.utf8.enumerated() {
            withUnsafeMutableBytes(of: &addr.sun_path) { raw in raw[idx] = byte }
        }
        let bindRes = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(staleFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        #expect(bindRes == 0)
        close(staleFD)
        #expect(FileManager.default.fileExists(atPath: socketURL.path))

        let recovered = LocalMCPUnixSocketServer(socketURL: socketURL, broker: broker)
        try recovered.start()
        defer { recovered.stop() }
        #expect(recovered.isRunning)
    }
    #endif

    @Test("tools/list advertises create_draft schema and keeps send/delete/trash tools excluded")
    func createDraftToolListedAndExclusionsPreserved() async throws {
        let backend = MockBackend()
        let settings = AgentAccessSettings(isEnabled: true, enabledAccountIDs: [backend.account.id])
        let broker = LocalMCPBroker(
            backendsProvider: { [backend] },
            settingsProvider: { settings },
            auditStore: AgentAccessAuditLogStore(fileURL: nil, postsChangeNotification: false)
        )

        let listResp = try await sendRPC(broker, [
            "jsonrpc": "2.0",
            "id": 401,
            "method": "tools/list"
        ])
        let result = try #require(listResp["result"] as? [String: Any])
        let tools = try #require(result["tools"] as? [[String: Any]])
        let toolNames = tools.compactMap { $0["name"] as? String }
        #expect(toolNames.contains("create_draft"))
        for forbidden in ["send_message", "delete_message", "move_to_trash", "empty_trash"] {
            #expect(!toolNames.contains(forbidden))
            let callResp = try await sendRPC(broker, [
                "jsonrpc": "2.0",
                "id": "forbid-\(forbidden)",
                "method": "tools/call",
                "params": ["name": forbidden, "arguments": ["account_id": backend.account.id]]
            ])
            #expect((callResp["error"] as? [String: Any])?["code"] as? Int == -32601)
        }

        let draftTool = try #require(tools.first { ($0["name"] as? String) == "create_draft" })
        let schema = try #require(draftTool["inputSchema"] as? [String: Any])
        let properties = try #require(schema["properties"] as? [String: Any])
        let required = Set(schema["required"] as? [String] ?? [])
        #expect(required == ["account_id", "to", "subject", "body_text"])
        #expect(properties["cc"] != nil)
        #expect(properties["bcc"] != nil)
        #expect(properties["in_reply_to_message_id"] != nil)
        let bodySchema = try #require(properties["body_text"] as? [String: Any])
        #expect(bodySchema["maxLength"] == nil)
        #expect((bodySchema["description"] as? String)?.contains("65,536") == true)
        #expect((bodySchema["description"] as? String)?.contains("UTF-8") == true)
        #expect(schema["additionalProperties"] as? Bool == false)
    }

    @Test("create_draft prompts with preview, saves via backend.save on approval, supports reply threading, and never sends")
    func createDraftApprovalSavesDraftNeverSendsAndSupportsReplyThreading() async throws {
        let account = BrevAccount(id: "acct-work", displayName: "Work", emailAddress: "work@northwind.example")
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let drafts = Folder(id: "drafts", name: "Drafts", role: .drafts)
        let original = MessageHeader(
            id: "msg-orig",
            threadID: "thread-q3",
            folderID: "inbox",
            from: Correspondent(name: "Maya", email: "maya@northwind.example"),
            to: [Correspondent(name: "Work", email: "work@northwind.example")],
            subject: "Q3 contract",
            snippet: "Please review the draft terms.",
            date: Date(timeIntervalSince1970: 1_735_689_600),
            messageID: "<orig-q3@northwind.example>"
        )
        let backend = MCPBodyStubBackend(
            wrapped: MockBackend(
                account: account,
                folders: [inbox, drafts],
                messagesByFolder: ["inbox": [original], "drafts": []]
            ),
            bodies: [:]
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

        let bodySecret = "Hello Maya,\n\n<script>alert(1)</script> ConfidentialBodyMarker991."
        let draftTask = Task {
            try await sendRPC(broker, [
                "jsonrpc": "2.0",
                "id": 402,
                "method": "tools/call",
                "params": [
                    "name": "create_draft",
                    "arguments": [
                        "account_id": account.id,
                        "to": ["maya@northwind.example"],
                        "cc": ["sam@northwind.example"],
                        "bcc": ["audit@northwind.example"],
                        "subject": "  Re: Q3 contract  ",
                        "body_text": bodySecret,
                        "in_reply_to_message_id": "msg-orig"
                    ]
                ]
            ])
        }

        for _ in 0 ..< 100 where coordinator.activeRequest == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        let active = try #require(coordinator.activeRequest)
        #expect(active.toolName == "create_draft")
        #expect(active.accountID == account.id)
        #expect(active.accountLabel == "Work")
        let preview = try #require(active.draftPreview)
        #expect(preview.to == ["maya@northwind.example"])
        #expect(preview.cc == ["sam@northwind.example"])
        #expect(preview.bcc == ["audit@northwind.example"])
        #expect(preview.subject == "Re: Q3 contract")
        #expect(preview.bodyPreview.contains("Hello Maya"))
        #expect(preview.inReplyToSubject == "Q3 contract")

        coordinator.approveActiveRequest()
        let resp = try await draftTask.value
        let payload = try parseToolTextPayload(resp)
        let draftID = try #require(payload["draft_id"] as? String)
        #expect(!draftID.isEmpty)
        #expect(payload["account_id"] as? String == account.id)
        #expect(payload["subject"] as? String == "Re: Q3 contract")
        #expect(payload["recipient_count"] as? Int == 3)
        #expect(payload["status"] as? String == "saved_as_draft")

        #expect(backend.sendCallCount == 0)
        #expect(backend.savedDrafts.count == 1)
        let saved = try #require(backend.savedDrafts.first)
        #expect(saved.id == draftID)
        #expect(saved.to.map(\.email) == ["maya@northwind.example"])
        #expect(saved.cc.map(\.email) == ["sam@northwind.example"])
        #expect(saved.bcc.map(\.email) == ["audit@northwind.example"])
        #expect(saved.subject == "Re: Q3 contract")
        #expect(saved.threadID == "thread-q3")
        #expect(saved.inReplyToMessageID == "<orig-q3@northwind.example>")
        #expect(!saved.htmlBody.contains("<script>"))
        #expect(saved.htmlBody.contains("ConfidentialBodyMarker991"))

        let auditEntry = try #require(auditStore.entries().first)
        #expect(auditEntry.toolName == "create_draft")
        #expect(auditEntry.outcome == .approved)
        #expect(auditEntry.accountID == account.id)
        #expect(!auditEntry.parameterSummary.contains("ConfidentialBodyMarker991"))
    }

    @Test("create_draft denial, timeout, and mid-flight consent revocation never save or send")
    func createDraftDenialTimeoutAndConsentRevocation() async throws {
        let account = BrevAccount(id: "acct-work", displayName: "Work", emailAddress: "work@northwind.example")
        let backend = MCPBodyStubBackend(
            wrapped: MockBackend(
                account: account,
                folders: [
                    Folder(id: "inbox", name: "Inbox", role: .inbox),
                    Folder(id: "drafts", name: "Drafts", role: .drafts)
                ],
                messagesByFolder: [:]
            ),
            bodies: [:]
        )

        @MainActor
        final class ToggleSettings {
            var settings: AgentAccessSettings
            init(_ settings: AgentAccessSettings) { self.settings = settings }
        }
        let state = ToggleSettings(AgentAccessSettings(isEnabled: true, enabledAccountIDs: [account.id]))
        let auditStore = AgentAccessAuditLogStore(fileURL: nil, postsChangeNotification: false)
        let coordinator = MCPApprovalCoordinator()
        let broker = LocalMCPBroker(
            backendsProvider: { [backend] },
            settingsProvider: { state.settings },
            auditStore: auditStore,
            approvalCoordinator: coordinator,
            approvalTimeoutSeconds: 2.0
        )

        let args: [String: Any] = [
            "account_id": account.id,
            "to": ["alice@example.org"],
            "subject": "Quarterly update",
            "body_text": "PrivateDraftBodyNeverLogged774"
        ]

        // 1. Denied approval -> -32010, no draft saved, logged without body.
        let denyTask = Task {
            try await sendRPC(broker, [
                "jsonrpc": "2.0",
                "id": 410,
                "method": "tools/call",
                "params": ["name": "create_draft", "arguments": args]
            ])
        }
        for _ in 0 ..< 100 where coordinator.activeRequest == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        coordinator.denyActiveRequest()
        let denyResp = try await denyTask.value
        #expect((denyResp["error"] as? [String: Any])?["code"] as? Int == -32010)
        #expect(backend.savedDrafts.isEmpty)
        #expect(backend.sendCallCount == 0)
        let denyAudit = try #require(auditStore.entries().first)
        #expect(denyAudit.toolName == "create_draft")
        #expect(denyAudit.outcome == .denied)
        #expect(!denyAudit.parameterSummary.contains("PrivateDraftBodyNeverLogged774"))

        // 2. Timeout -> -32011, no draft saved.
        let fastBroker = LocalMCPBroker(
            backendsProvider: { [backend] },
            settingsProvider: { state.settings },
            auditStore: auditStore,
            approvalCoordinator: coordinator,
            approvalTimeoutSeconds: 0.15
        )
        let timeoutResp = try await sendRPC(fastBroker, [
            "jsonrpc": "2.0",
            "id": 411,
            "method": "tools/call",
            "params": ["name": "create_draft", "arguments": args]
        ])
        #expect((timeoutResp["error"] as? [String: Any])?["code"] as? Int == -32011)
        #expect(backend.savedDrafts.isEmpty)
        #expect(auditStore.entries().first?.outcome == .timedOut)

        // 3. Consent revoked while prompt is open -> -32001, no draft saved.
        let revokeTask = Task {
            try await sendRPC(broker, [
                "jsonrpc": "2.0",
                "id": 412,
                "method": "tools/call",
                "params": ["name": "create_draft", "arguments": args]
            ])
        }
        for _ in 0 ..< 100 where coordinator.activeRequest == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        state.settings.isEnabled = false
        coordinator.approveActiveRequest()
        let revokeResp = try await revokeTask.value
        #expect((revokeResp["error"] as? [String: Any])?["code"] as? Int == -32001)
        #expect(backend.savedDrafts.isEmpty)
        #expect(backend.sendCallCount == 0)
        #expect(auditStore.entries().first?.outcome == .blockedDisabled)
    }

    @Test("create_draft rejects invalid arguments, out-of-scope reply IDs, and redacts sign-in codes in previews and audit logs")
    func createDraftValidationAndSignInCodeRedaction() async throws {
        let allowedAccount = BrevAccount(id: "acct-allowed", displayName: "Allowed", emailAddress: "allowed@example.org")
        let hiddenAccount = BrevAccount(id: "acct-hidden", displayName: "Hidden", emailAddress: "hidden@example.org")
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let drafts = Folder(id: "drafts", name: "Drafts", role: .drafts)
        let trash = Folder(id: "trash", name: "Trash", role: .trash)

        let trashMsg = MessageHeader(
            id: "msg-in-trash",
            threadID: "t-trash",
            folderID: "trash",
            from: Correspondent(name: "Trash", email: "trash@example.org"),
            subject: "Deleted secret",
            snippet: "Secret",
            date: Date(timeIntervalSince1970: 1_735_689_600)
        )
        let hiddenMsg = MessageHeader(
            id: "msg-in-hidden",
            threadID: "t-hidden",
            folderID: "inbox",
            from: Correspondent(name: "Hidden", email: "secret@example.org"),
            subject: "Other account secret",
            snippet: "Secret",
            date: Date(timeIntervalSince1970: 1_735_689_600)
        )
        let allowedBackend = MCPBodyStubBackend(
            wrapped: MockBackend(
                account: allowedAccount,
                folders: [inbox, drafts, trash],
                messagesByFolder: ["inbox": [], "drafts": [], "trash": [trashMsg]]
            ),
            bodies: [:]
        )
        let hiddenBackend = MCPBodyStubBackend(
            wrapped: MockBackend(
                account: hiddenAccount,
                folders: [inbox],
                messagesByFolder: ["inbox": [hiddenMsg]]
            ),
            bodies: [:]
        )

        let settings = AgentAccessSettings(isEnabled: true, enabledAccountIDs: [allowedAccount.id])
        let auditStore = AgentAccessAuditLogStore(fileURL: nil, postsChangeNotification: false)
        let coordinator = MCPApprovalCoordinator()
        let broker = LocalMCPBroker(
            backendsProvider: { [allowedBackend, hiddenBackend] },
            settingsProvider: { settings },
            auditStore: auditStore,
            approvalCoordinator: coordinator,
            approvalTimeoutSeconds: 2.0
        )

        // Disallowed account fails closed with -32002.
        let hiddenAcctResp = try await sendRPC(broker, [
            "jsonrpc": "2.0",
            "id": 420,
            "method": "tools/call",
            "params": [
                "name": "create_draft",
                "arguments": [
                    "account_id": hiddenAccount.id,
                    "to": ["alice@example.org"],
                    "subject": "Hi",
                    "body_text": "Hello"
                ]
            ]
        ])
        #expect((hiddenAcctResp["error"] as? [String: Any])?["code"] as? Int == -32002)
        #expect(auditStore.entries().first?.outcome == .blockedAccount)

        // Empty / malformed recipients fail closed without prompting or saving.
        let badRecipientCases: [[String: Any]] = [
            ["account_id": allowedAccount.id, "to": [], "subject": "Hi", "body_text": "Hello"],
            ["account_id": allowedAccount.id, "to": ["not-an-email"], "subject": "Hi", "body_text": "Hello"],
            ["account_id": allowedAccount.id, "to": ["you@corp.com@evil.com"], "subject": "Hi", "body_text": "Hello"],
            [
                "account_id": allowedAccount.id,
                "to": ["alice@example.org\r\nBcc: evil@example.org"],
                "subject": "Hi",
                "body_text": "Hello"
            ],
            [
                "account_id": allowedAccount.id,
                "to": ["alice@example.org"],
                "cc": ["bad-cc"],
                "subject": "Hi",
                "body_text": "Hello"
            ],
            ["account_id": allowedAccount.id, "to": ["alice@example.org"], "bcc": [""], "subject": "Hi", "body_text": "Hello"]
        ]
        for (idx, badArgs) in badRecipientCases.enumerated() {
            let resp = try await sendRPC(broker, [
                "jsonrpc": "2.0",
                "id": 421 + idx,
                "method": "tools/call",
                "params": ["name": "create_draft", "arguments": badArgs]
            ])
            #expect((resp["error"] as? [String: Any])?["code"] as? Int == -32602)
            #expect(auditStore.entries().first?.outcome == .denied)
        }

        // Oversized body (> 64 KiB) fails closed.
        let hugeBody = String(repeating: "a", count: LocalMCPBroker.maxDraftBodyBytes + 1)
        let hugeResp = try await sendRPC(broker, [
            "jsonrpc": "2.0",
            "id": 430,
            "method": "tools/call",
            "params": [
                "name": "create_draft",
                "arguments": [
                    "account_id": allowedAccount.id,
                    "to": ["alice@example.org"],
                    "subject": "Huge",
                    "body_text": hugeBody
                ]
            ]
        ])
        #expect((hugeResp["error"] as? [String: Any])?["code"] as? Int == -32602)

        // Inaccessible in_reply_to_message_id (Trash, other account, or injected OTP) fails closed without leaking.
        for badReplyID in ["msg-in-trash", "msg-in-hidden", "Your verification code is 839204"] {
            let resp = try await sendRPC(broker, [
                "jsonrpc": "2.0",
                "id": "reply-\(badReplyID)",
                "method": "tools/call",
                "params": [
                    "name": "create_draft",
                    "arguments": [
                        "account_id": allowedAccount.id,
                        "to": ["alice@example.org"],
                        "subject": "Re: Secret",
                        "body_text": "Hello",
                        "in_reply_to_message_id": badReplyID
                    ]
                ]
            ])
            let error = try #require(resp["error"] as? [String: Any])
            #expect(error["code"] as? Int == -32004)
            #expect((error["message"] as? String)?.contains("839204") == false)
            #expect((error["message"] as? String)?.contains("Trash") == false)
            let lastAudit = try #require(auditStore.entries().first)
            #expect(!lastAudit.parameterSummary.contains("839204"))
            #expect(!lastAudit.parameterSummary.contains("msg-in-trash"))
            #expect(!lastAudit.parameterSummary.contains("msg-in-hidden"))
        }

        // Sign-in code redaction in draft approval preview and audit log.
        let otpTask = Task {
            try await sendRPC(broker, [
                "jsonrpc": "2.0",
                "id": 440,
                "method": "tools/call",
                "params": [
                    "name": "create_draft",
                    "arguments": [
                        "account_id": allowedAccount.id,
                        "to": ["alice@example.org"],
                        "subject": "Your verification code is 839204",
                        "body_text": "Your Acme sign-in verification code is 839204. SecretMarker440."
                    ]
                ]
            ])
        }
        for _ in 0 ..< 100 where coordinator.activeRequest == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        let otpPreview = try #require(coordinator.activeRequest?.draftPreview)
        #expect(!otpPreview.subject.contains("839204"))
        #expect(!otpPreview.bodyPreview.contains("839204"))
        coordinator.denyActiveRequest()
        _ = try await otpTask.value

        let otpAudit = try #require(auditStore.entries().first)
        #expect(!otpAudit.parameterSummary.contains("839204"))
        #expect(!otpAudit.parameterSummary.contains("SecretMarker440"))
        #expect(allowedBackend.savedDrafts.isEmpty)
        #expect(hiddenBackend.savedDrafts.isEmpty)
        #expect(allowedBackend.sendCallCount == 0)
    }

    @Test(
        "create_draft rejects missing Drafts folder, unknown args, malformed local parts, flags 7-line truncation, keeps all 16 recipients, and never logs bare 6-digit subjects to disk"
    )
    func createDraftReviewHardening() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-mcp-audit-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let auditFileURL = tempDir.appendingPathComponent("agent-access-audit.json")

        let noDraftsAccount = BrevAccount(id: "acct-nodrafts", displayName: "NoDrafts", emailAddress: "nodrafts@example.org")
        let noDraftsBackend = MCPBodyStubBackend(
            wrapped: MockBackend(
                account: noDraftsAccount,
                folders: [Folder(id: "inbox", name: "Inbox", role: .inbox)],
                messagesByFolder: [:]
            ),
            bodies: [:]
        )
        let fullAccount = BrevAccount(id: "acct-full", displayName: "Full", emailAddress: "full@example.org")
        let fullBackend = MCPBodyStubBackend(
            wrapped: MockBackend(
                account: fullAccount,
                folders: [
                    Folder(id: "inbox", name: "Inbox", role: .inbox),
                    Folder(id: "drafts", name: "Drafts", role: .drafts)
                ],
                messagesByFolder: [:]
            ),
            bodies: [:]
        )

        let settings = AgentAccessSettings(isEnabled: true, enabledAccountIDs: [noDraftsAccount.id, fullAccount.id])
        let auditStore = AgentAccessAuditLogStore(fileURL: auditFileURL, postsChangeNotification: false)
        let coordinator = MCPApprovalCoordinator()
        let broker = LocalMCPBroker(
            backendsProvider: { [noDraftsBackend, fullBackend] },
            settingsProvider: { settings },
            auditStore: auditStore,
            approvalCoordinator: coordinator,
            approvalTimeoutSeconds: 2.0
        )

        // 1. Account without a visible .drafts folder fails closed with -32005 before approval.
        let noDraftsResp = try await sendRPC(broker, [
            "jsonrpc": "2.0",
            "id": 501,
            "method": "tools/call",
            "params": [
                "name": "create_draft",
                "arguments": [
                    "account_id": noDraftsAccount.id,
                    "to": ["alice@example.org"],
                    "subject": "Hello",
                    "body_text": "Body"
                ]
            ]
        ])
        #expect((noDraftsResp["error"] as? [String: Any])?["code"] as? Int == -32005)
        #expect(auditStore.entries().first?.parameterSummary == "no_drafts_folder")
        #expect(noDraftsBackend.savedDrafts.isEmpty)

        // 2. Unknown argument keys (e.g. attachments) are rejected at runtime with -32602.
        let unknownArgResp = try await sendRPC(broker, [
            "jsonrpc": "2.0",
            "id": 502,
            "method": "tools/call",
            "params": [
                "name": "create_draft",
                "arguments": [
                    "account_id": fullAccount.id,
                    "to": ["alice@example.org"],
                    "subject": "Hello",
                    "body_text": "Body",
                    "attachments": ["secret.pdf"]
                ]
            ]
        ])
        #expect((unknownArgResp["error"] as? [String: Any])?["code"] as? Int == -32602)
        #expect(auditStore.entries().first?.parameterSummary == "unknown_arguments count=1")

        // 3. Strict RFC 5322 unquoted dot-atom local-part validation.
        let overlongLocal = String(repeating: "a", count: 65) + "@example.org"
        let malformedLocalParts = [
            "maya..patel@example.org",
            ".maya@example.org",
            "maya.@example.org",
            "@example.org",
            overlongLocal,
            "maya(comment)@example.org",
            "\"quoted\"@example.org",
            "maya patel@example.org"
        ]
        for (idx, badAddress) in malformedLocalParts.enumerated() {
            let resp = try await sendRPC(broker, [
                "jsonrpc": "2.0",
                "id": 510 + idx,
                "method": "tools/call",
                "params": [
                    "name": "create_draft",
                    "arguments": [
                        "account_id": fullAccount.id,
                        "to": [badAddress],
                        "subject": "Hello",
                        "body_text": "Body"
                    ]
                ]
            ])
            #expect((resp["error"] as? [String: Any])?["code"] as? Int == -32602)
        }

        // 4. Short 7-line body sets isBodyTruncated = true and truncates to 6 lines;
        //    16 recipients across to/cc/bcc all appear in draftPreview without truncation;
        //    bare 6-digit subject "482913" never appears in memory or persisted audit file on disk.
        let toList = (1 ... 10).map { "to\($0).user+tag@northwind.example" }
        let ccList = (1 ... 3).map { "cc\($0)_name@northwind.example" }
        let bccList = (1 ... 3).map { "bcc\($0)-audit@northwind.example" }
        let sevenLineBody = "Line 1\nLine 2\nLine 3\nLine 4\nLine 5\nLine 6\nLine 7"

        let previewTask = Task {
            try await sendRPC(broker, [
                "jsonrpc": "2.0",
                "id": 530,
                "method": "tools/call",
                "params": [
                    "name": "create_draft",
                    "arguments": [
                        "account_id": fullAccount.id,
                        "to": toList,
                        "cc": ccList,
                        "bcc": bccList,
                        "subject": "482913",
                        "body_text": sevenLineBody
                    ]
                ]
            ])
        }
        for _ in 0 ..< 100 where coordinator.activeRequest == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        let preview = try #require(coordinator.activeRequest?.draftPreview)
        #expect(preview.to == toList)
        #expect(preview.cc == ccList)
        #expect(preview.bcc == bccList)
        #expect(preview.isBodyTruncated)
        #expect(preview.bodyPreview.contains("Line 6"))
        #expect(!preview.bodyPreview.contains("Line 7"))

        coordinator.approveActiveRequest()
        let okResp = try await previewTask.value
        let okPayload = try parseToolTextPayload(okResp)
        #expect(okPayload["recipient_count"] as? Int == 16)
        #expect(okPayload["status"] as? String == "saved_as_draft")

        // Also test denied path with bare 6-digit subject.
        let denyBareTask = Task {
            try await sendRPC(broker, [
                "jsonrpc": "2.0",
                "id": 531,
                "method": "tools/call",
                "params": [
                    "name": "create_draft",
                    "arguments": [
                        "account_id": fullAccount.id,
                        "to": ["maya.patel+work@northwind.example"],
                        "subject": "482913",
                        "body_text": "Short body"
                    ]
                ]
            ])
        }
        for _ in 0 ..< 100 where coordinator.activeRequest == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        coordinator.denyActiveRequest()
        _ = try await denyBareTask.value

        for entry in auditStore.entries() {
            #expect(!entry.parameterSummary.contains("482913"))
        }
        let persistedJSON = try String(contentsOf: auditFileURL, encoding: .utf8)
        #expect(!persistedJSON.contains("482913"))
    }
}

private final class MCPBodyStubBackend: MailBackend, CachedMessageBodyProviding, @unchecked Sendable {
    private let wrapped: MockBackend
    private let bodies: [String: MessageBody]
    private let unscopedExtraHeaders: [MessageHeader]
    private let onCachedBodyRead: (@MainActor @Sendable () -> Void)?
    private let lock = NSLock()
    private var fetchCount = 0
    private var searchCount = 0
    private var recordedSavedDrafts: [Draft] = []
    private var recordedSendCount = 0

    var networkBodyFetchCount: Int {
        lock.withLock { fetchCount }
    }

    var searchCallCount: Int {
        lock.withLock { searchCount }
    }

    var savedDrafts: [Draft] {
        lock.withLock { recordedSavedDrafts }
    }

    var sendCallCount: Int {
        lock.withLock { recordedSendCount }
    }

    func resetSearchCallCount() {
        lock.withLock { searchCount = 0 }
    }

    init(
        wrapped: MockBackend,
        bodies: [String: MessageBody],
        unscopedExtraHeaders: [MessageHeader] = [],
        onCachedBodyRead: (@MainActor @Sendable () -> Void)? = nil
    ) {
        self.wrapped = wrapped
        self.bodies = bodies
        self.unscopedExtraHeaders = unscopedExtraHeaders
        self.onCachedBodyRead = onCachedBodyRead
    }

    var account: BrevAccount { wrapped.account }
    var capabilities: BackendCapabilities { wrapped.capabilities }
    var extendedCapabilities: BackendExtendedCapabilities { wrapped.extendedCapabilities }

    func extensionService<Service>(_ serviceType: Service.Type) -> Service? {
        if serviceType == CachedMessageBodyProviding.self {
            return self as? Service
        }
        return wrapped.extensionService(serviceType)
    }

    func cachedBody(for messageID: MessageHeader.ID, sourceID _: MailSourceID?) async -> MessageBody? {
        if let onCachedBodyRead {
            await onCachedBodyRead()
        }
        return bodies[messageID]
    }

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
        lock.withLock { fetchCount += 1 }
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

    func save(draft: Draft) async throws -> Draft {
        let saved = try await wrapped.save(draft: draft)
        lock.withLock { recordedSavedDrafts.append(saved) }
        return saved
    }

    func discard(draftID: String) async throws { try await wrapped.discard(draftID: draftID) }

    func send(draft: Draft) async throws -> SendResult {
        lock.withLock { recordedSendCount += 1 }
        return try await wrapped.send(draft: draft)
    }

    func search(_ query: SearchQuery) async throws -> [MessageHeader] {
        lock.withLock { searchCount += 1 }
        var results = try await wrapped.search(query)
        if query.folderID == nil {
            results.append(contentsOf: unscopedExtraHeaders.filter { query.matches($0) })
        }
        return results
    }

    func calendarEvent(from attachmentID: String) async throws -> CalendarEvent {
        try await wrapped.calendarEvent(from: attachmentID)
    }

    func replyToCalendarInvite(messageID: String, response: AttendeeState) async throws {
        try await wrapped.replyToCalendarInvite(messageID: messageID, response: response)
    }

    func subscribeToChanges() -> AsyncStream<MailEvent> { wrapped.subscribeToChanges() }
}
