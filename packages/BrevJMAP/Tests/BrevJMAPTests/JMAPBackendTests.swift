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
@testable import BrevJMAP
import Foundation
import Testing

@Suite("JMAPBackend RFC 8620/8621 operations")
struct JMAPBackendTests {
    private static let sessionURL = URL(string: "https://api.fastmail.com/jmap/session")!
    private static let apiURL = URL(string: "https://api.fastmail.com/jmap/api/")!

    private static let sampleSessionJSON = Data("""
    {
      "capabilities": {
        "urn:ietf:params:jmap:core": {
          "maxSizeUpload": 50000000,
          "maxCallsInRequest": 32,
          "maxObjectsInGet": 500
        },
        "urn:ietf:params:jmap:mail": {},
        "urn:ietf:params:jmap:submission": {}
      },
      "accounts": {
        "u123": {
          "name": "henrik@fastmail.com",
          "isPersonal": true,
          "isReadOnly": false,
          "accountCapabilities": {
            "urn:ietf:params:jmap:mail": {},
            "urn:ietf:params:jmap:submission": {}
          }
        }
      },
      "primaryAccounts": {
        "urn:ietf:params:jmap:mail": "u123",
        "urn:ietf:params:jmap:submission": "u123"
      },
      "username": "henrik@fastmail.com",
      "apiUrl": "https://api.fastmail.com/jmap/api/",
      "downloadUrl": "https://api.fastmail.com/jmap/download/{accountId}/{blobId}/{name}?accept={type}",
      "uploadUrl": "https://api.fastmail.com/jmap/upload/{accountId}/",
      "eventSourceUrl": "https://api.fastmail.com/jmap/eventsource/?types={types}&closeafter={closeafter}&ping={ping}",
      "state": "sess-1"
    }
    """.utf8)

    private static func makeAccount(email: String = "henrik@fastmail.com") -> BrevAccount {
        BrevAccount(
            id: BrevAccount.jmapAccountID(forEmailAddress: email),
            displayName: "Henrik",
            emailAddress: email,
            backendIdentifier: BrevAccount.jmapBackendIdentifier,
            backendDisplayName: BrevAccount.jmapBackendDisplayName
        )
    }

    private static func initialBootstrapResponse() -> JMAPResponse {
        let mailboxes: [JMAPJSONValue] = [
            .object([
                "id": .string("mb-inbox"),
                "name": .string("Inbox"),
                "role": .string("inbox"),
                "sortOrder": .int(1),
                "totalEmails": .int(12),
                "unreadEmails": .int(3)
            ]),
            .object([
                "id": .string("mb-sent"),
                "name": .string("Sent"),
                "role": .string("sent"),
                "sortOrder": .int(2),
                "totalEmails": .int(5),
                "unreadEmails": .int(0)
            ]),
            .object([
                "id": .string("mb-drafts"),
                "name": .string("Drafts"),
                "role": .string("drafts"),
                "sortOrder": .int(3),
                "totalEmails": .int(1),
                "unreadEmails": .int(0)
            ]),
            .object([
                "id": .string("mb-archive"),
                "name": .string("Archive"),
                "role": .string("archive"),
                "sortOrder": .int(4),
                "totalEmails": .int(40),
                "unreadEmails": .int(0)
            ]),
            .object([
                "id": .string("mb-junk"),
                "name": .string("Spam"),
                "role": .string("junk"),
                "sortOrder": .int(5),
                "totalEmails": .int(2),
                "unreadEmails": .int(1)
            ]),
            .object([
                "id": .string("mb-trash"),
                "name": .string("Trash"),
                "role": .string("trash"),
                "sortOrder": .int(6),
                "totalEmails": .int(4),
                "unreadEmails": .int(0)
            ]),
            .object([
                "id": .string("mb-custom"),
                "name": .string("Projects"),
                "sortOrder": .int(10),
                "totalEmails": .int(7),
                "unreadEmails": .int(2)
            ])
        ]
        let identities: [JMAPJSONValue] = [
            .object([
                "id": .string("id-1"),
                "name": .string("Henrik"),
                "email": .string("henrik@fastmail.com"),
                "textSignature": .string("-- Henrik"),
                "htmlSignature": .string("<p>-- Henrik</p>")
            ]),
            .object([
                "id": .string("id-2"),
                "name": .string("Henrik Work"),
                "email": .string("work@example.org"),
                "textSignature": .string(""),
                "htmlSignature": .string("")
            ])
        ]
        return JMAPResponse(
            methodResponses: [
                JMAPInvocation(
                    name: "Mailbox/get",
                    arguments: [
                        "accountId": .string("u123"),
                        "state": .string("mb-state-1"),
                        "list": .array(mailboxes)
                    ],
                    callID: "m0"
                ),
                JMAPInvocation(
                    name: "Identity/get",
                    arguments: [
                        "accountId": .string("u123"),
                        "state": .string("id-state-1"),
                        "list": .array(identities)
                    ],
                    callID: "i0"
                )
            ],
            sessionState: "sess-1"
        )
    }

    private static func jsonResponse(_ response: JMAPResponse, url: URL = apiURL) throws -> JMAPHTTPResponse {
        let data = try JSONEncoder().encode(response)
        return JMAPHTTPResponse(statusCode: 200, body: data, finalURL: url)
    }

    @Test("connect discovers session, maps mailbox roles/counts, and advertises exact capabilities")
    func connectAndFolderRoleMapping() async throws {
        let transport = MockJMAPHTTPTransport { request in
            if request.url == Self.sessionURL {
                return JMAPHTTPResponse(statusCode: 200, body: Self.sampleSessionJSON, finalURL: request.url)
            }
            return try Self.jsonResponse(Self.initialBootstrapResponse())
        }
        let backend = JMAPBackend(
            account: Self.makeAccount(),
            sessionURL: Self.sessionURL,
            tokenProvider: StaticJMAPAccessTokenProvider(token: "tok-123"),
            transport: transport
        )

        try await backend.connect()

        #expect(backend.capabilities.contains(.jmapMail))
        #expect(backend.capabilities.contains(.providerAPI))
        #expect(backend.capabilities.contains(.serverSideSearch))
        #expect(backend.capabilities.contains(.serverSideThreading))
        #expect(backend.capabilities.contains(.historyDeltaSync))
        #expect(backend.capabilities.contains(.idleSync))
        #expect(backend.capabilities.contains(.flagColors))
        #expect(backend.capabilities.contains(.aliases))
        #expect(backend.capabilities.contains(.serverSignatures))
        #expect(backend.extendedCapabilities.contains(.messageCopy))
        #expect(backend.extendedCapabilities.contains(.rawMessageSource))
        #expect(backend.extendedCapabilities.contains(.rawMessageBytes))
        #expect(backend.extendedCapabilities.contains(.serverAliases))
        #expect(backend.extendedCapabilities.contains(.sendAs))

        let folders = try await backend.folders()
        #expect(folders.count == 7)
        #expect(folders.first(where: { $0.id == "mb-inbox" })?.role == .inbox)
        #expect(folders.first(where: { $0.id == "mb-inbox" })?.unreadCount == 3)
        #expect(folders.first(where: { $0.id == "mb-junk" })?.role == .spam)
        #expect(folders.first(where: { $0.id == "mb-archive" })?.role == .archive)
        #expect(folders.first(where: { $0.id == "mb-custom" })?.role == .custom)

        let aliases = try await backend.listAliases()
        #expect(aliases.count == 2)
        #expect(aliases.first?.email == "henrik@fastmail.com")
        let signatures = try await backend.listServerSignatures()
        #expect(signatures.count == 1)
        #expect(signatures.first?.body == "<p>-- Henrik</p>")

        await backend.disconnect()
        #expect(backend.capabilities.isEmpty)
    }

    @Test("messages uses single-round-trip batched Email/query + Email/get with #resultRef and pagination")
    func batchedQueryAndGetMessagesWithPagination() async throws {
        let recordedRequests = RecordedRequests()
        let transport = MockJMAPHTTPTransport { request in
            if request.url == Self.sessionURL {
                return JMAPHTTPResponse(statusCode: 200, body: Self.sampleSessionJSON, finalURL: request.url)
            }
            let decoded = try JSONDecoder().decode(JMAPRequest.self, from: request.body ?? Data())
            await recordedRequests.append(decoded)
            if decoded.methodCalls.first?.name == "Mailbox/get" {
                return try Self.jsonResponse(Self.initialBootstrapResponse())
            }
            // Verify batched Email/query + Email/get with #ids back-reference.
            #expect(decoded.methodCalls.count == 2)
            #expect(decoded.methodCalls[0].name == "Email/query")
            #expect(decoded.methodCalls[1].name == "Email/get")
            let idsRef = decoded.methodCalls[1].arguments["#ids"]?.objectValue
            #expect(idsRef?["resultOf"]?.stringValue == "q0")
            #expect(idsRef?["name"]?.stringValue == "Email/query")
            #expect(idsRef?["path"]?.stringValue == "/ids")

            let position = decoded.methodCalls[0].arguments["position"]?.intValue ?? 0
            let emailID = position == 0 ? "e-1" : "e-2"
            let emailObj: JMAPJSONValue = .object([
                "id": .string(emailID),
                "blobId": .string("blob-\(emailID)"),
                "threadId": .string("t-1"),
                "mailboxIds": .object(["mb-inbox": .bool(true)]),
                "keywords": .object([
                    "$seen": .bool(position != 0),
                    "$flagged": .bool(true),
                    "$answered": .bool(true),
                    "$MailFlagBit1": .bool(true) // red (ordinal 2)
                ]),
                "size": .int(2048),
                "receivedAt": .string("2026-11-25T08:00:00Z"),
                "sentAt": .string("2026-11-25T07:59:00Z"),
                "from": .array([.object(["name": .string("Alice"), "email": .string("alice@example.org")])]),
                "to": .array([.object(["email": .string("henrik@fastmail.com")])]),
                "subject": .string("JMAP batch test \(position)"),
                "preview": .string("Hello from JMAP"),
                "hasAttachment": .bool(true)
            ])
            return try Self.jsonResponse(
                JMAPResponse(
                    methodResponses: [
                        JMAPInvocation(
                            name: "Email/query",
                            arguments: [
                                "accountId": .string("u123"),
                                "queryState": .string("qs-1"),
                                "canCalculateChanges": .bool(true),
                                "position": .int(position),
                                "ids": .array([.string(emailID)]),
                                "total": .int(2)
                            ],
                            callID: "q0"
                        ),
                        JMAPInvocation(
                            name: "Email/get",
                            arguments: [
                                "accountId": .string("u123"),
                                "state": .string("em-state-1"),
                                "list": .array([emailObj])
                            ],
                            callID: "g0"
                        )
                    ],
                    sessionState: "sess-1"
                )
            )
        }

        let backend = JMAPBackend(
            account: Self.makeAccount(),
            sessionURL: Self.sessionURL,
            tokenProvider: StaticJMAPAccessTokenProvider(token: "tok-123"),
            transport: transport
        )
        try await backend.connect()
        let inbox = try #require(try await backend.folders().first(where: { $0.role == .inbox }))

        let firstPage = try await backend.messages(in: inbox, pageToken: nil)
        #expect(firstPage.headers.count == 1)
        #expect(firstPage.headers[0].id == "e-1")
        #expect(firstPage.headers[0].threadID == "t-1")
        #expect(firstPage.headers[0].isRead == false)
        #expect(firstPage.headers[0].isFlagged == true)
        #expect(firstPage.headers[0].isAnswered == true)
        #expect(firstPage.headers[0].flagColor == .red)
        #expect(firstPage.headers[0].hasAttachments == true)
        #expect(firstPage.nextPageToken == "1")

        let secondPage = try await backend.messages(in: inbox, pageToken: firstPage.nextPageToken)
        #expect(secondPage.headers.count == 1)
        #expect(secondPage.headers[0].id == "e-2")
        #expect(secondPage.headers[0].isRead == true)
        #expect(secondPage.nextPageToken == nil)
    }

    @Test("body, attachment download with escaping, raw source, and cache-only services work")
    func bodyAttachmentAndRawSource() async throws {
        let downloadedURLs = RecordedURLs()
        let transport = MockJMAPHTTPTransport { request in
            if request.url == Self.sessionURL {
                return JMAPHTTPResponse(statusCode: 200, body: Self.sampleSessionJSON, finalURL: request.url)
            }
            if request.url.absoluteString.contains("/jmap/download/") {
                await downloadedURLs.append(request.url)
                if request.url.absoluteString.contains("blob-att") {
                    return JMAPHTTPResponse(statusCode: 200, body: Data("PDF-BYTES".utf8), finalURL: request.url)
                }
                return JMAPHTTPResponse(
                    statusCode: 200,
                    body: Data("From: alice@example.org\r\nSubject: Raw\r\n\r\nHello raw".utf8),
                    finalURL: request.url
                )
            }
            let decoded = try JSONDecoder().decode(JMAPRequest.self, from: request.body ?? Data())
            if decoded.methodCalls.first?.name == "Mailbox/get" {
                return try Self.jsonResponse(Self.initialBootstrapResponse())
            }
            let emailObj: JMAPJSONValue = .object([
                "id": .string("e-body"),
                "blobId": .string("blob-raw-1"),
                "threadId": .string("t-body"),
                "textBody": .array([.object(["partId": .string("p-txt"), "type": .string("text/plain")])]),
                "htmlBody": .array([.object(["partId": .string("p-html"), "type": .string("text/html")])]),
                "bodyValues": .object([
                    "p-txt": .object(["value": .string("Plain hello")]),
                    "p-html": .object(["value": .string("<p>HTML hello <img src=\"cid:logo@ex\"></p>")])
                ]),
                "bodyStructure": .object([
                    "type": .string("multipart/related"),
                    "subParts": .array([
                        .object([
                            "partId": .string("p-cid"),
                            "blobId": .string("blob-inline-1"),
                            "type": .string("image/png"),
                            "name": .string("logo.png"),
                            "size": .int(512),
                            "disposition": .string("inline"),
                            "cid": .string("<logo@ex>")
                        ])
                    ])
                ]),
                "attachments": .array([
                    .object([
                        "partId": .string("p-att"),
                        "blobId": .string("blob-att+1"),
                        "type": .string("application/pdf"),
                        "name": .string("Q4 Invoice #2.pdf"),
                        "size": .int(9)
                    ])
                ]),
                "headers": .array([
                    .object(["name": .string("List-Unsubscribe"), "value": .string("<https://lists.example.org/unsub>")]),
                    .object(["name": .string("List-Unsubscribe-Post"), "value": .string("List-Unsubscribe=One-Click")]),
                    .object(["name": .string("Precedence"), "value": .string("bulk")]),
                    .object(["name": .string("Authentication-Results"), "value": .string("mx.fastmail.com; dmarc=pass")])
                ])
            ])
            return try Self.jsonResponse(
                JMAPResponse(
                    methodResponses: [
                        JMAPInvocation(
                            name: "Email/get",
                            arguments: [
                                "accountId": .string("u123"),
                                "state": .string("em-state-2"),
                                "list": .array([emailObj])
                            ],
                            callID: "g0"
                        )
                    ],
                    sessionState: "sess-1"
                )
            )
        }

        let backend = JMAPBackend(
            account: Self.makeAccount(),
            sessionURL: Self.sessionURL,
            tokenProvider: StaticJMAPAccessTokenProvider(token: "tok-123"),
            transport: transport
        )
        try await backend.connect()

        let body = try await backend.body(for: "e-body")
        #expect(body.plainText == "Plain hello")
        #expect(body.html == "<p>HTML hello <img src=\"cid:logo@ex\"></p>")
        #expect(body.attachments.count == 2)
        let pdfAttachment = try #require(body.attachments.first(where: { !$0.isInline }))
        let inlineAttachment = try #require(body.attachments.first(where: { $0.isInline }))
        #expect(inlineAttachment.contentID == "logo@ex")
        #expect(body.isBulkPrecedence == true)
        #expect(body.listUnsubscribe?.methods.count == 1)
        #expect(body.authenticationResults == "mx.fastmail.com; dmarc=pass")

        // Cache-only extension services read without network.
        let cachedBodyProvider = try #require(backend.extensionService(CachedMessageBodyProviding.self))
        #expect(await cachedBodyProvider.cachedBody(for: "e-body", sourceID: nil) == body)
        let unsubProvider = try #require(backend.extensionService(CachedListUnsubscribeProviding.self))
        let sourceID = MailSourceID(accountID: backend.account.id, mailboxID: backend.account.id)
        #expect(await unsubProvider.cachedIsBulkPrecedence(for: "e-body", sourceID: sourceID) == true)

        // Attachment download escapes blobId, name, and MIME type.
        let bytes = try await backend.downloadAttachment(pdfAttachment)
        #expect(String(data: bytes, encoding: .utf8) == "PDF-BYTES")
        let raw = try await backend.rawSource(for: "e-body")
        #expect(raw.contains("Hello raw"))

        let urls = await downloadedURLs.urls
        #expect(urls.first?.absoluteString.contains("blob-att%2B1/Q4%20Invoice%20%232.pdf?accept=application%2Fpdf") == true)
    }

    @Test("server search maps structured SearchQuery into RFC 8621 FilterCondition")
    func structuredSearchFilter() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = Date(timeIntervalSince1970: 1_700_086_400)
        let query = SearchQuery(
            text: "invoice",
            folderID: "mb-inbox",
            from: "billing@example.org",
            to: "henrik@fastmail.com",
            dateRange: start ... end,
            hasAttachments: true,
            isUnread: true,
            isFlagged: true,
            subject: "Q4"
        )
        let filter = JMAPBackend.buildSearchFilter(for: query)
        #expect(filter["text"] == .string("invoice"))
        #expect(filter["from"] == .string("billing@example.org"))
        #expect(filter["to"] == .string("henrik@fastmail.com"))
        #expect(filter["subject"] == .string("Q4"))
        #expect(filter["inMailbox"] == .string("mb-inbox"))
        #expect(filter["hasAttachment"] == .bool(true))
        #expect(filter["notKeyword"] == .string("$seen"))
        #expect(filter["hasKeyword"] == .string("$flagged"))
        #expect(filter["after"] == .string(JMAPDateCoding.formatUTC(start)))
        #expect(filter["before"] == .string(JMAPDateCoding.formatUTC(end)))
    }

    @Test("Email/set and Mailbox/set mutations execute expected JMAP patches")
    func emailAndMailboxMutations() async throws {
        let recordedRequests = RecordedRequests()
        let transport = MockJMAPHTTPTransport { request in
            if request.url == Self.sessionURL {
                return JMAPHTTPResponse(statusCode: 200, body: Self.sampleSessionJSON, finalURL: request.url)
            }
            let decoded = try JSONDecoder().decode(JMAPRequest.self, from: request.body ?? Data())
            await recordedRequests.append(decoded)
            let method = decoded.methodCalls.first?.name ?? ""
            if method == "Mailbox/get" {
                return try Self.jsonResponse(Self.initialBootstrapResponse())
            }
            if method == "Mailbox/set" {
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "Mailbox/set",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "newState": .string("mb-state-2"),
                                    "created": .object(["new-mailbox": .object(["id": .string("mb-new")])]),
                                    "updated": .object(["mb-new": .null]),
                                    "destroyed": .array([.string("mb-new")])
                                ],
                                callID: "ms0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            }
            return try Self.jsonResponse(
                JMAPResponse(
                    methodResponses: [
                        JMAPInvocation(
                            name: "Email/set",
                            arguments: [
                                "accountId": .string("u123"),
                                "newState": .string("em-state-next")
                            ],
                            callID: "es0"
                        )
                    ],
                    sessionState: "sess-1"
                )
            )
        }

        let backend = JMAPBackend(
            account: Self.makeAccount(),
            sessionURL: Self.sessionURL,
            tokenProvider: StaticJMAPAccessTokenProvider(token: "tok-123"),
            transport: transport
        )
        try await backend.connect()

        try await backend.setRead(true, for: ["e-1"])
        try await backend.setFlagColor(.blue, for: ["e-1"])
        try await backend.setFlagged(false, for: ["e-1"])
        let archive = Folder(id: "mb-archive", name: "Archive", role: .archive)
        try await backend.move(messageIDs: ["e-1"], to: archive)
        try await backend.copy(messageIDs: ["e-1"], to: Folder(id: "mb-custom", name: "Projects", role: .custom))
        try await backend.delete(messageIDs: ["e-1"])

        let created = try await backend.createFolder(name: "Receipts", parentID: nil)
        #expect(created.id == "mb-new")
        let renamed = try await backend.renameFolder(id: "mb-new", name: "Tax Receipts")
        #expect(renamed.name == "Tax Receipts")
        try await backend.deleteFolder(id: "mb-new")

        let calls = await recordedRequests.requests.flatMap(\.methodCalls)
        let emailSetCalls = calls.filter { $0.name == "Email/set" }
        #expect(emailSetCalls.count == 6)
        // Mark read
        #expect(emailSetCalls[0].arguments["update"]?.objectValue?["e-1"]?.objectValue?["keywords/$seen"] == .bool(true))
        // Flag color blue (ordinal 5 = bit0 + bit2)
        let colorPatch = emailSetCalls[1].arguments["update"]?.objectValue?["e-1"]?.objectValue
        #expect(colorPatch?["keywords/$flagged"] == .bool(true))
        #expect(colorPatch?["keywords/$MailFlagBit0"] == .bool(true))
        #expect(colorPatch?["keywords/$MailFlagBit1"] == .null)
        #expect(colorPatch?["keywords/$MailFlagBit2"] == .bool(true))
        // Move to archive
        #expect(emailSetCalls[3].arguments["update"]?.objectValue?["e-1"]?
            .objectValue?["mailboxIds"] == .object(["mb-archive": .bool(true)]))
        // Copy preserves existing mailboxes via patch path
        #expect(emailSetCalls[4].arguments["update"]?.objectValue?["e-1"]?.objectValue?["mailboxIds/mb-custom"] == .bool(true))
        // Delete moves to Trash first
        #expect(emailSetCalls[5].arguments["update"]?.objectValue?["e-1"]?
            .objectValue?["mailboxIds"] == .object(["mb-trash": .bool(true)]))
    }

    @Test("saveDraft uploads attachments via Blob/upload and send batches Email/set + EmailSubmission/set")
    func draftSaveAndBatchedSendFlow() async throws {
        let recordedRequests = RecordedRequests()
        let uploadedBlobs = RequestCounter()
        let transport = MockJMAPHTTPTransport { request in
            if request.url == Self.sessionURL {
                return JMAPHTTPResponse(statusCode: 200, body: Self.sampleSessionJSON, finalURL: request.url)
            }
            if request.url.absoluteString.contains("/jmap/upload/") {
                await uploadedBlobs.increment()
                let uploadResp = JMAPBlobUploadResponse(
                    accountId: "u123",
                    blobId: "blob-uploaded-1",
                    type: request.headers["Content-Type"] ?? "application/octet-stream",
                    size: request.body?.count ?? 0
                )
                return try JMAPHTTPResponse(
                    statusCode: 201,
                    body: JSONEncoder().encode(uploadResp),
                    finalURL: request.url
                )
            }
            let decoded = try JSONDecoder().decode(JMAPRequest.self, from: request.body ?? Data())
            await recordedRequests.append(decoded)
            let firstMethod = decoded.methodCalls.first?.name ?? ""
            if firstMethod == "Mailbox/get" {
                return try Self.jsonResponse(Self.initialBootstrapResponse())
            }
            if decoded.methodCalls.count == 2, decoded.methodCalls[1].name == "EmailSubmission/set" {
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "Email/set",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "newState": .string("em-sent-1"),
                                    "created": .object(["draft": .object(["id": .string("e-sent-1")])])
                                ],
                                callID: "es0"
                            ),
                            JMAPInvocation(
                                name: "EmailSubmission/set",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "newState": .string("sub-1"),
                                    "created": .object(["send": .object(["id": .string("sub-id-1")])])
                                ],
                                callID: "sub0"
                            ),
                            // Implicit RFC 8621 §7.3 Email/set produced by onSuccessUpdateEmail.
                            JMAPInvocation(
                                name: "Email/set",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "newState": .string("em-sent-2"),
                                    "updated": .object(["e-sent-1": .null])
                                ],
                                callID: "sub0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            }
            if decoded.methodCalls.first?.arguments["destroy"] != nil {
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "Email/set",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "newState": .string("em-destroyed-1"),
                                    "destroyed": decoded.methodCalls.first?.arguments["destroy"] ?? .array([])
                                ],
                                callID: "es0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            }
            return try Self.jsonResponse(
                JMAPResponse(
                    methodResponses: [
                        JMAPInvocation(
                            name: "Email/set",
                            arguments: [
                                "accountId": .string("u123"),
                                "newState": .string("em-draft-1"),
                                "created": .object(["draft": .object([
                                    "id": .string("e-draft-1"),
                                    "threadId": .string("t-draft-1")
                                ])])
                            ],
                            callID: "es0"
                        )
                    ],
                    sessionState: "sess-1"
                )
            )
        }

        let backend = JMAPBackend(
            account: Self.makeAccount(),
            sessionURL: Self.sessionURL,
            tokenProvider: StaticJMAPAccessTokenProvider(token: "tok-123"),
            transport: transport
        )
        try await backend.connect()

        // Missing recipients fails closed before network.
        await #expect(throws: DraftValidationError.missingRecipients) {
            _ = try await backend.send(draft: Draft(id: "d-empty", subject: "No recipients"))
        }

        let attID = try await backend.uploadAttachment(
            draftID: "d-1",
            data: Data("hello".utf8),
            filename: "notes.txt",
            mimeType: "text/plain"
        )
        let saved = try await backend.save(
            draft: Draft(
                id: "d-1",
                to: [Correspondent(name: "Bob", email: "bob@example.org")],
                subject: "Draft subject",
                htmlBody: "<p>Hello Bob</p>",
                attachmentIDs: [attID]
            )
        )
        #expect(saved.remoteID == "e-draft-1")
        #expect(saved.threadID == "t-draft-1")
        #expect(await uploadedBlobs.count == 1)

        // Sending reuses uploaded blob without re-uploading, submits without destroying the prior draft
        // upfront, verifies implicit onSuccessUpdateEmail Sent move, then cleans up the prior draft after submission.
        let sendResult = try await backend.send(draft: saved)
        #expect(sendResult.sentMessageID == "e-sent-1")
        #expect(sendResult.warnings.isEmpty)
        #expect(await uploadedBlobs.count == 1)

        let allRequests = await recordedRequests.requests
        let sendRequest = try #require(
            allRequests.first(where: { $0.methodCalls.contains(where: { $0.name == "EmailSubmission/set" }) })
        )
        #expect(sendRequest.using.contains(JMAPCapability.submission))
        #expect(sendRequest.methodCalls[0].name == "Email/set")
        #expect(sendRequest.methodCalls[0].arguments["destroy"] == nil)
        #expect(sendRequest.methodCalls[1].name == "EmailSubmission/set")
        let onSuccess = sendRequest.methodCalls[1].arguments["onSuccessUpdateEmail"]?.objectValue?["#send"]?.objectValue
        #expect(onSuccess?["keywords/$draft"] == .null)
        #expect(onSuccess?["mailboxIds/mb-sent"] == .bool(true))

        let cleanupRequest = try #require(allRequests.last)
        #expect(cleanupRequest.methodCalls.count == 1)
        #expect(cleanupRequest.methodCalls[0].name == "Email/set")
        #expect(cleanupRequest.methodCalls[0].arguments["destroy"] == .array([.string("e-draft-1")]))
    }

    @Test("delta sync applies Email/changes and recovers cleanly from cannotCalculateChanges")
    func deltaSyncAndCannotCalculateChangesFallback() async throws {
        let syncPhase = PhaseBox()
        let transport = MockJMAPHTTPTransport { request in
            if request.url == Self.sessionURL {
                return JMAPHTTPResponse(statusCode: 200, body: Self.sampleSessionJSON, finalURL: request.url)
            }
            let decoded = try JSONDecoder().decode(JMAPRequest.self, from: request.body ?? Data())
            let first = decoded.methodCalls.first?.name ?? ""
            if first == "Mailbox/get" {
                return try Self.jsonResponse(Self.initialBootstrapResponse())
            }
            if first == "Email/query" {
                let phase = await syncPhase.phase
                let emailID = phase == 0 ? "e-initial" : "e-recovered"
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "Email/query",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "position": .int(0),
                                    "ids": .array([.string(emailID)]),
                                    "total": .int(1)
                                ],
                                callID: "q0"
                            ),
                            JMAPInvocation(
                                name: "Email/get",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "state": .string(phase == 0 ? "es-1" : "es-recovered"),
                                    "list": .array([
                                        .object([
                                            "id": .string(emailID),
                                            "mailboxIds": .object(["mb-inbox": .bool(true)]),
                                            "keywords": .object([:]),
                                            "receivedAt": .string("2026-11-25T09:00:00Z"),
                                            "from": .array([.object(["email": .string("sender@example.org")])]),
                                            "subject": .string("Subject \(emailID)")
                                        ])
                                    ])
                                ],
                                callID: "g0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            }
            if first == "Mailbox/changes" {
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "Mailbox/changes",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "oldState": .string("mb-state-1"),
                                    "newState": .string("mb-state-1")
                                ],
                                callID: "mc0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            }
            if first == "Email/changes" {
                let phase = await syncPhase.phase
                if phase == 1 {
                    return try Self.jsonResponse(
                        JMAPResponse(
                            methodResponses: [
                                JMAPInvocation(
                                    name: "Email/changes",
                                    arguments: [
                                        "accountId": .string("u123"),
                                        "oldState": .string("es-1"),
                                        "newState": .string("es-2"),
                                        "created": .array([.string("e-delta-new")]),
                                        "destroyed": .array([.string("e-initial")])
                                    ],
                                    callID: "ec0"
                                )
                            ],
                            sessionState: "sess-1"
                        )
                    )
                }
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "error",
                                arguments: ["type": .string("cannotCalculateChanges")],
                                callID: "ec0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            }
            // Email/get for delta created email
            return try Self.jsonResponse(
                JMAPResponse(
                    methodResponses: [
                        JMAPInvocation(
                            name: "Email/get",
                            arguments: [
                                "accountId": .string("u123"),
                                "state": .string("es-2"),
                                "list": .array([
                                    .object([
                                        "id": .string("e-delta-new"),
                                        "mailboxIds": .object(["mb-inbox": .bool(true)]),
                                        "keywords": .object([:]),
                                        "receivedAt": .string("2026-11-25T09:10:00Z"),
                                        "from": .array([.object(["email": .string("new@example.org")])]),
                                        "subject": .string("Fresh arrival")
                                    ])
                                ])
                            ],
                            callID: "g0"
                        )
                    ],
                    sessionState: "sess-1"
                )
            )
        }

        let startTime = Date(timeIntervalSince1970: 1_800_000_000)
        let backend = JMAPBackend(
            account: Self.makeAccount(),
            sessionURL: Self.sessionURL,
            tokenProvider: StaticJMAPAccessTokenProvider(token: "tok-123"),
            transport: transport,
            now: { startTime }
        )
        try await backend.connect()
        let inbox = try #require(try await backend.folders().first(where: { $0.role == .inbox }))
        _ = try await backend.messages(in: inbox, pageToken: nil)

        // Phase 1: incremental delta sync via Email/changes + MailboxBackgroundRefreshing.
        await syncPhase.set(1)
        let sourceID = MailSourceID(accountID: backend.account.id, mailboxID: backend.account.id)
        let refresher = try #require(backend.extensionService(MailboxBackgroundRefreshing.self))
        try await refresher.refreshMailbox(for: sourceID)

        let cachedAfterDelta = try await backend.cachedMessageHeaders(in: inbox, sourceID: sourceID)
        #expect(cachedAfterDelta.map(\.id) == ["e-delta-new"])
        #expect(backend.currentEmailState == "es-2")
        let freshIDs = await backend.freshDeliveryMessageIDs(since: startTime.addingTimeInterval(-1))
        #expect(freshIDs.contains("e-delta-new"))

        // Phase 2: server returns cannotCalculateChanges -> full refresh recovery.
        await syncPhase.set(2)
        try await backend.refresh(folder: inbox)
        let cachedAfterRecovery = try await backend.cachedMessageHeaders(in: inbox, sourceID: sourceID)
        #expect(cachedAfterRecovery.map(\.id) == ["e-recovered"])
        #expect(backend.currentEmailState == "es-recovered")
    }

    @Test("EventSource SSE triggers delta sync, emits MailEvent, and cancels cleanly")
    func eventSourceLiveUpdatesAndCancellation() async throws {
        let transport = MockJMAPHTTPTransport(
            handler: { request in
                if request.url == Self.sessionURL {
                    return JMAPHTTPResponse(statusCode: 200, body: Self.sampleSessionJSON, finalURL: request.url)
                }
                let decoded = try JSONDecoder().decode(JMAPRequest.self, from: request.body ?? Data())
                let first = decoded.methodCalls.first?.name ?? ""
                if first == "Mailbox/get" {
                    return try Self.jsonResponse(Self.initialBootstrapResponse())
                }
                if first == "Mailbox/changes" {
                    return try Self.jsonResponse(
                        JMAPResponse(
                            methodResponses: [
                                JMAPInvocation(
                                    name: "Mailbox/changes",
                                    arguments: [
                                        "accountId": .string("u123"),
                                        "oldState": .string("mb-state-1"),
                                        "newState": .string("mb-state-1")
                                    ],
                                    callID: "mc0"
                                )
                            ],
                            sessionState: "sess-1"
                        )
                    )
                }
                if first == "Email/query" {
                    return try Self.jsonResponse(
                        JMAPResponse(
                            methodResponses: [
                                JMAPInvocation(
                                    name: "Email/query",
                                    arguments: [
                                        "accountId": .string("u123"),
                                        "position": .int(0),
                                        "ids": .array([.string("e-sse-1")]),
                                        "total": .int(1)
                                    ],
                                    callID: "q0"
                                ),
                                JMAPInvocation(
                                    name: "Email/get",
                                    arguments: [
                                        "accountId": .string("u123"),
                                        "state": .string("es-sse-1"),
                                        "list": .array([
                                            .object([
                                                "id": .string("e-sse-1"),
                                                "mailboxIds": .object(["mb-inbox": .bool(true)]),
                                                "receivedAt": .string("2026-11-25T09:20:00Z"),
                                                "from": .array([.object(["email": .string("push@example.org")])]),
                                                "subject": .string("Live SSE message")
                                            ])
                                        ])
                                    ],
                                    callID: "g0"
                                )
                            ],
                            sessionState: "sess-1"
                        )
                    )
                }
                if first == "Email/changes" {
                    return try Self.jsonResponse(
                        JMAPResponse(
                            methodResponses: [
                                JMAPInvocation(
                                    name: "Email/changes",
                                    arguments: [
                                        "accountId": .string("u123"),
                                        "oldState": .string("es-sse-1"),
                                        "newState": .string("es-sse-2"),
                                        "created": .array([.string("e-sse-2")])
                                    ],
                                    callID: "ec0"
                                )
                            ],
                            sessionState: "sess-1"
                        )
                    )
                }
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "Email/get",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "state": .string("es-sse-2"),
                                    "list": .array([
                                        .object([
                                            "id": .string("e-sse-2"),
                                            "mailboxIds": .object(["mb-inbox": .bool(true)]),
                                            "receivedAt": .string("2026-11-25T09:25:00Z"),
                                            "from": .array([.object(["email": .string("sse@example.org")])]),
                                            "subject": .string("Arrived via SSE")
                                        ])
                                    ])
                                ],
                                callID: "g0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            },
            sseHandler: { _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(
                        JMAPEventSourceEvent(
                            event: "state",
                            id: "1",
                            data: #"{"changed":{"u123":{"Email":"es-sse-2"}}}"#
                        )
                    )
                    // Stay open until cancelled by consumer/disconnect.
                }
            }
        )

        let backend = JMAPBackend(
            account: Self.makeAccount(),
            sessionURL: Self.sessionURL,
            tokenProvider: StaticJMAPAccessTokenProvider(token: "tok-123"),
            transport: transport,
            eventSourceRetryDelay: { _ in 10_000_000 }
        )
        try await backend.connect()
        let inbox = try #require(try await backend.folders().first(where: { $0.role == .inbox }))
        _ = try await backend.messages(in: inbox, pageToken: nil)

        var receivedAdded = false
        for await event in backend.subscribeToChanges() {
            if case .messagesAdded(let folderID, let ids) = event,
               folderID == "mb-inbox",
               ids.contains("e-sse-2") {
                receivedAdded = true
                break
            }
        }
        #expect(receivedAdded)
        await backend.disconnect()
    }

    @Test("WebPush PushSubscription/set register, verify, and unregister integrate with PushRelayModels")
    func webPushSubscriptionLifecycle() async throws {
        let transport = MockJMAPHTTPTransport { request in
            if request.url == Self.sessionURL {
                return JMAPHTTPResponse(statusCode: 200, body: Self.sampleSessionJSON, finalURL: request.url)
            }
            let decoded = try JSONDecoder().decode(JMAPRequest.self, from: request.body ?? Data())
            let first = decoded.methodCalls.first?.name ?? ""
            if first == "Mailbox/get" {
                return try Self.jsonResponse(Self.initialBootstrapResponse())
            }
            let callID = decoded.methodCalls.first?.callID ?? "p0"
            if callID == "p0" {
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "PushSubscription/set",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "created": .object([
                                        "brev-push-sub": .object(["id": .string("sub-jmap-99")])
                                    ])
                                ],
                                callID: "p0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            }
            return try Self.jsonResponse(
                JMAPResponse(
                    methodResponses: [
                        JMAPInvocation(
                            name: "PushSubscription/set",
                            arguments: [
                                "accountId": .string("u123"),
                                "updated": .object(["sub-jmap-99": .null]),
                                "destroyed": .array([.string("sub-jmap-99")])
                            ],
                            callID: callID
                        )
                    ],
                    sessionState: "sess-1"
                )
            )
        }

        let backend = JMAPBackend(
            account: Self.makeAccount(),
            sessionURL: Self.sessionURL,
            tokenProvider: StaticJMAPAccessTokenProvider(token: "tok-123"),
            transport: transport
        )
        try await backend.connect()

        let keys = try PushRelayEncryptionKeyMaterial.generate().publicKeys()
        let spec = try JMAPWebPushSubscriptionSpec(
            deviceClientID: "dev-1",
            urlString: "https://push-bridge.example.org/jmap/hook",
            keys: keys
        )
        let registered = try await backend.registerWebPushSubscription(spec: spec)
        #expect(registered.subscriptionID == "sub-jmap-99")
        #expect(registered.state == .pendingVerification)

        let verified = try await backend.verifyWebPushSubscription(
            subscriptionID: registered.subscriptionID,
            verificationCode: "verify-xyz"
        )
        #expect(verified.state == .active)

        try await backend.unregisterWebPushSubscription(subscriptionID: registered.subscriptionID)
    }

    @Test("JMAPAccountConnector keeps bearer token strictly in TokenStore, restores, rolls back, and removes")
    func accountConnectorLifecycleAndKeychainIsolation() async throws {
        let suiteName = "BrevJMAPConfigTest-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let configStore = UserDefaultsJMAPAccountConfigurationStore(defaults: defaults)
        let tokenStore = TestJMAPTokenStore()
        let shouldFail = FailureSwitch()
        let secretToken = "fmu1-keychain-only-secret-xyz"

        let transport = MockJMAPHTTPTransport { request in
            if await shouldFail.fail {
                return JMAPHTTPResponse(statusCode: 401, body: Data(), finalURL: request.url)
            }
            if request.url == Self.sessionURL {
                return JMAPHTTPResponse(statusCode: 200, body: Self.sampleSessionJSON, finalURL: request.url)
            }
            return try Self.jsonResponse(Self.initialBootstrapResponse())
        }

        let connector = JMAPAccountConnector(
            configurationStore: configStore,
            tokenStore: tokenStore,
            transport: transport
        )

        // Provisioning failure rolls back token and metadata cleanly.
        await shouldFail.set(true)
        await #expect(throws: MailBackendError.self) {
            _ = try await connector.provision(
                JMAPAccountSetupRequest(
                    emailAddress: "henrik@fastmail.com",
                    displayName: "Henrik",
                    sessionURLString: "https://api.fastmail.com/jmap/session",
                    bearerToken: secretToken
                )
            )
        }
        let accountID = BrevAccount.jmapAccountID(forEmailAddress: "henrik@fastmail.com")
        #expect(await tokenStore.token(for: accountID) == nil)
        #expect(await configStore.configuration(for: accountID) == nil)

        // Successful provision persists metadata in UserDefaults (without token!) and token in TokenStore.
        await shouldFail.set(false)
        let connected = try await connector.provision(
            JMAPAccountSetupRequest(
                emailAddress: "henrik@fastmail.com",
                displayName: "Henrik",
                sessionURLString: "https://api.fastmail.com/jmap/session",
                bearerToken: secretToken
            )
        )
        #expect(connected.account.id == accountID)
        #expect(connected.account.backendIdentifier == BrevAccount.jmapBackendIdentifier)
        let persistedConfig = try #require(await configStore.configuration(for: accountID))
        #expect(persistedConfig.credentialID != accountID)
        #expect(await tokenStore.token(for: persistedConfig.credentialID)?.accessToken == secretToken)

        let rawDefaultsData = try #require(defaults.data(forKey: "Brev.jmapAccountConfigurations.v1"))
        let rawDefaultsString = String(decoding: rawDefaultsData, as: UTF8.self)
        #expect(!rawDefaultsString.contains(secretToken))
        #expect(rawDefaultsString.contains("https:\\/\\/api.fastmail.com\\/jmap\\/session") || rawDefaultsString
            .contains("api.fastmail.com"))

        // Restore succeeds from persisted config + Keychain token.
        let restored = try #require(try await connector.restore(connected.account))
        #expect(restored.account.id == accountID)
        #expect(restored.backend.capabilities.contains(.jmapMail))

        // Remove clears both Keychain token and configuration.
        try await connector.remove(accountID: accountID)
        #expect(await tokenStore.token(for: persistedConfig.credentialID) == nil)
        #expect(await tokenStore.token(for: accountID) == nil)
        #expect(await configStore.configuration(for: accountID) == nil)
    }

    @Test("replacing an account at another origin never exposes the new token to an existing backend")
    func accountReplacementIsolatesTokensFromPreviousBackend() async throws {
        let configStore = InMemoryJMAPAccountConfigurationStore()
        let tokenStore = TestJMAPTokenStore()
        let originASession = URL(string: "https://origin-a.example.org/jmap/session")!
        let originAAPI = URL(string: "https://origin-a.example.org/jmap/api/")!
        let originBSession = URL(string: "https://origin-b.example.org/jmap/session")!
        let originBAPI = URL(string: "https://origin-b.example.org/jmap/api/")!
        let originATokensSeen = RecordedStrings()

        @Sendable func sessionJSON(apiURL: URL) -> Data {
            Data("""
            {
              "capabilities": { "urn:ietf:params:jmap:core": {}, "urn:ietf:params:jmap:mail": {} },
              "accounts": {
                "u123": { "name": "henrik@example.org", "isPersonal": true, "isReadOnly": false,
                          "accountCapabilities": { "urn:ietf:params:jmap:mail": {} } }
              },
              "primaryAccounts": { "urn:ietf:params:jmap:mail": "u123" },
              "username": "henrik@example.org",
              "apiUrl": "\(apiURL.absoluteString)",
              "downloadUrl": "\(apiURL.absoluteString)download/{accountId}/{blobId}/{name}?accept={type}",
              "uploadUrl": "\(apiURL.absoluteString)upload/{accountId}/",
              "state": "s1"
            }
            """.utf8)
        }

        let transport = MockJMAPHTTPTransport { request in
            if request.url.host == "origin-a.example.org" {
                await originATokensSeen.append(request.headers["Authorization"] ?? "")
            }
            if request.url == originASession {
                return JMAPHTTPResponse(statusCode: 200, body: sessionJSON(apiURL: originAAPI), finalURL: request.url)
            }
            if request.url == originBSession {
                return JMAPHTTPResponse(statusCode: 200, body: sessionJSON(apiURL: originBAPI), finalURL: request.url)
            }
            return try Self.jsonResponse(Self.initialBootstrapResponse(), url: request.url)
        }

        let connector = JMAPAccountConnector(
            configurationStore: configStore,
            tokenStore: tokenStore,
            transport: transport
        )
        let first = try await connector.provision(
            JMAPAccountSetupRequest(
                emailAddress: "henrik@example.org",
                displayName: "Henrik",
                sessionURLString: originASession.absoluteString,
                bearerToken: "token-origin-A"
            )
        )
        let second = try await connector.provision(
            JMAPAccountSetupRequest(
                emailAddress: "henrik@example.org",
                displayName: "Henrik",
                sessionURLString: originBSession.absoluteString,
                bearerToken: "token-origin-B"
            )
        )
        #expect(second.backend.capabilities.contains(.jmapMail))

        // Calling a request on the still-connected old backend must fail with authenticationRequired
        // rather than reading and forwarding token-origin-B to origin-a.example.org.
        await #expect(throws: MailBackendError.self) {
            _ = try await first.backend.body(for: "e-1")
        }
        let seenOnOriginA = await originATokensSeen.values
        #expect(!seenOnOriginA.contains(where: { $0.contains("token-origin-B") }))
    }

    @Test("partial reads and mutations never advance reconciled delta-sync cursors")
    func partialReadsAndMutationsDoNotAdvanceDeltaSyncCursors() async throws {
        let recordedEmailChangeSince = RecordedStrings()
        let recordedMailboxChangeSince = RecordedStrings()
        let transport = MockJMAPHTTPTransport { request in
            if request.url == Self.sessionURL {
                return JMAPHTTPResponse(statusCode: 200, body: Self.sampleSessionJSON, finalURL: request.url)
            }
            let decoded = try JSONDecoder().decode(JMAPRequest.self, from: request.body ?? Data())
            let first = decoded.methodCalls.first?.name ?? ""
            if first == "Mailbox/get" {
                return try Self.jsonResponse(Self.initialBootstrapResponse())
            }
            if first == "Mailbox/set" {
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "Mailbox/set",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "newState": .string("mb-state-99"),
                                    "updated": .object(["mb-custom": .null])
                                ],
                                callID: "ms0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            }
            if first == "Email/query" {
                let inMailbox = decoded.methodCalls[0].arguments["filter"]?.objectValue?["inMailbox"]?.stringValue
                let emailID = inMailbox == "mb-inbox" ? "e-inbox-1" : "e-archive-1"
                let state = inMailbox == "mb-inbox" ? "es-1" : "es-archive-newer"
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "Email/query",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "position": .int(0),
                                    "ids": .array([.string(emailID)]),
                                    "total": .int(1)
                                ],
                                callID: "q0"
                            ),
                            JMAPInvocation(
                                name: "Email/get",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "state": .string(state),
                                    "list": .array([
                                        .object([
                                            "id": .string(emailID),
                                            "mailboxIds": .object([inMailbox ?? "mb-inbox": .bool(true)]),
                                            "receivedAt": .string("2026-11-25T09:00:00Z"),
                                            "from": .array([.object(["email": .string("a@example.org")])]),
                                            "subject": .string("Msg \(emailID)")
                                        ])
                                    ])
                                ],
                                callID: "g0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            }
            if first == "Email/get" {
                let ids = decoded.methodCalls[0].arguments["ids"]
                if case .array(let idVals) = ids, idVals.first == .string("e-intervening") {
                    return try Self.jsonResponse(
                        JMAPResponse(
                            methodResponses: [
                                JMAPInvocation(
                                    name: "Email/get",
                                    arguments: [
                                        "accountId": .string("u123"),
                                        "state": .string("es-5"),
                                        "list": .array([
                                            .object([
                                                "id": .string("e-intervening"),
                                                "mailboxIds": .object(["mb-inbox": .bool(true)]),
                                                "receivedAt": .string("2026-11-25T09:05:00Z"),
                                                "from": .array([.object(["email": .string("new@example.org")])]),
                                                "subject": .string("Intervening arrival")
                                            ])
                                        ])
                                    ],
                                    callID: "g0"
                                )
                            ],
                            sessionState: "sess-1"
                        )
                    )
                }
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "Email/get",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "state": .string("es-body-newer"),
                                    "list": .array([
                                        .object([
                                            "id": .string("e-inbox-1"),
                                            "textBody": .array([.object([
                                                "partId": .string("t"),
                                                "type": .string("text/plain")
                                            ])]),
                                            "bodyValues": .object(["t": .object(["value": .string("Body text")])])
                                        ])
                                    ])
                                ],
                                callID: "g0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            }
            if first == "Email/set" {
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "Email/set",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "newState": .string("es-mutation-newer")
                                ],
                                callID: "es0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            }
            if first == "Mailbox/changes" {
                if let since = decoded.methodCalls[0].arguments["sinceState"]?.stringValue {
                    await recordedMailboxChangeSince.append(since)
                }
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "Mailbox/changes",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "oldState": .string("mb-state-1"),
                                    "newState": .string("mb-state-99")
                                ],
                                callID: "mc0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            }
            if first == "Email/changes" {
                if let since = decoded.methodCalls[0].arguments["sinceState"]?.stringValue {
                    await recordedEmailChangeSince.append(since)
                }
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "Email/changes",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "oldState": .string("es-1"),
                                    "newState": .string("es-5"),
                                    "created": .array([.string("e-intervening")])
                                ],
                                callID: "ec0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            }
            return try Self.jsonResponse(Self.initialBootstrapResponse())
        }

        let backend = JMAPBackend(
            account: Self.makeAccount(),
            sessionURL: Self.sessionURL,
            tokenProvider: StaticJMAPAccessTokenProvider(token: "tok-123"),
            transport: transport
        )
        try await backend.connect()
        let inbox = Folder(id: "mb-inbox", name: "Inbox", role: .inbox)
        let archive = Folder(id: "mb-archive", name: "Archive", role: .archive)

        // Initial Inbox load establishes baseline es-1.
        _ = try await backend.messages(in: inbox, pageToken: nil)
        #expect(backend.currentEmailState == "es-1")
        #expect(backend.currentMailboxState == "mb-state-1")

        // Partial reads & mutations returning newer server states must NOT advance cursors.
        _ = try await backend.body(for: "e-inbox-1")
        _ = try await backend.messages(in: archive, pageToken: nil)
        try await backend.setRead(true, for: ["e-inbox-1"])
        _ = try await backend.renameFolder(id: "mb-custom", name: "Renamed")
        #expect(backend.currentEmailState == "es-1")
        #expect(backend.currentMailboxState == "mb-state-1")

        // Next delta sync still starts from es-1 and mb-state-1 and catches the intervening message.
        try await backend.refresh(folder: inbox)
        #expect(await recordedEmailChangeSince.values == ["es-1"])
        #expect(await recordedMailboxChangeSince.values == ["mb-state-1"])
        let sourceID = MailSourceID(accountID: backend.account.id, mailboxID: backend.account.id)
        let cachedInbox = try await backend.cachedMessageHeaders(in: inbox, sourceID: sourceID)
        #expect(cachedInbox.map(\.id).contains("e-intervening"))
        #expect(backend.currentEmailState == "es-5")
        #expect(backend.currentMailboxState == "mb-state-99")
    }

    @Test("saved and reopened drafts restore attachments via LocalDraftAttachmentProviding in-session and after restart")
    func draftAttachmentRestorationInSessionAndAfterRestart() async throws {
        let transport = MockJMAPHTTPTransport { request in
            if request.url == Self.sessionURL {
                return JMAPHTTPResponse(statusCode: 200, body: Self.sampleSessionJSON, finalURL: request.url)
            }
            if request.url.absoluteString.contains("/jmap/upload/") {
                let blobID = request.headers["Content-Type"] == "image/png" ? "blob-cid-1" : "blob-pdf-1"
                return try JMAPHTTPResponse(
                    statusCode: 201,
                    body: JSONEncoder().encode(
                        JMAPBlobUploadResponse(
                            accountId: "u123",
                            blobId: blobID,
                            type: request.headers["Content-Type"] ?? "application/octet-stream",
                            size: request.body?.count ?? 0
                        )
                    ),
                    finalURL: request.url
                )
            }
            if request.url.absoluteString.contains("/jmap/download/") {
                let payload = request.url.absoluteString.contains("blob-cid-1")
                    ? Data("PNG-BYTES".utf8)
                    : Data("PDF-BYTES".utf8)
                return JMAPHTTPResponse(statusCode: 200, body: payload, finalURL: request.url)
            }
            let decoded = try JSONDecoder().decode(JMAPRequest.self, from: request.body ?? Data())
            let first = decoded.methodCalls.first?.name ?? ""
            if first == "Mailbox/get" {
                return try Self.jsonResponse(Self.initialBootstrapResponse())
            }
            if first == "Email/set" {
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "Email/set",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "newState": .string("em-draft-1"),
                                    "created": .object(["draft": .object(["id": .string("e-draft-att-1")])])
                                ],
                                callID: "es0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            }
            // Email/get for post-restart remote draft reconstruction.
            return try Self.jsonResponse(
                JMAPResponse(
                    methodResponses: [
                        JMAPInvocation(
                            name: "Email/get",
                            arguments: [
                                "accountId": .string("u123"),
                                "state": .string("em-draft-1"),
                                "list": .array([
                                    .object([
                                        "id": .string("e-draft-att-1"),
                                        "threadId": .string("t-draft-1"),
                                        "mailboxIds": .object(["mb-drafts": .bool(true)]),
                                        "keywords": .object(["$draft": .bool(true), "$seen": .bool(true)]),
                                        "to": .array([.object(["email": .string("bob@example.org")])]),
                                        "subject": .string("With Attachments"),
                                        "htmlBody": .array([.object(["partId": .string("h1"), "type": .string("text/html")])]),
                                        "bodyValues": .object([
                                            "h1": .object(["value": .string("<p>Hi <img src=\"cid:img1\"></p>")])
                                        ]),
                                        "attachments": .array([
                                            .object([
                                                "partId": .string("p-pdf"),
                                                "blobId": .string("blob-pdf-1"),
                                                "type": .string("application/pdf"),
                                                "name": .string("spec.pdf"),
                                                "size": .int(9),
                                                "disposition": .string("attachment"),
                                                // Unreferenced Content-ID on a regular attachment must NOT make it inline.
                                                "cid": .string("<unreferenced-pdf@example.org>")
                                            ]),
                                            .object([
                                                "partId": .string("p-img"),
                                                "blobId": .string("blob-cid-1"),
                                                "type": .string("image/png"),
                                                "name": .string("pic.png"),
                                                "size": .int(9),
                                                "disposition": .string("inline"),
                                                "cid": .string("<img1>")
                                            ])
                                        ])
                                    ])
                                ])
                            ],
                            callID: "g0"
                        )
                    ],
                    sessionState: "sess-1"
                )
            )
        }

        // 1. In-session save & reopen via source-scoped lookup + LocalDraftAttachmentProviding.
        let session1 = JMAPBackend(
            account: Self.makeAccount(),
            sessionURL: Self.sessionURL,
            tokenProvider: StaticJMAPAccessTokenProvider(token: "tok-123"),
            transport: transport
        )
        try await session1.connect()
        let sourceID = MailSourceID(accountID: session1.account.id, mailboxID: session1.account.id)
        let foreignSourceID = MailSourceID(accountID: "jmap:other@example.org", mailboxID: "other")

        let pdfID = try await session1.uploadAttachment(
            draftID: "local-d1",
            data: Data("PDF-BYTES".utf8),
            filename: "spec.pdf",
            mimeType: "application/pdf"
        )
        let cidID = try await session1.stageInlineAttachment(
            draftID: "local-d1",
            contentID: "img1",
            filename: "pic.png",
            mimeType: "image/png",
            data: Data("PNG-BYTES".utf8)
        )
        let saved = try await session1.save(
            draft: Draft(
                id: "local-d1",
                to: [Correspondent(email: "bob@example.org")],
                subject: "With Attachments",
                htmlBody: "<p>Hi <img src=\"cid:img1\"></p>",
                attachmentIDs: [pdfID, cidID]
            )
        )
        let attachmentService1 = try #require(session1.extensionService(LocalDraftAttachmentProviding.self))
        let inSessionDraft = try #require(try await session1.draft(for: "e-draft-att-1", sourceID: sourceID))
        #expect(inSessionDraft == saved)
        let inSessionPayloads = try await attachmentService1.localDraftAttachments(for: inSessionDraft, sourceID: sourceID)
        #expect(inSessionPayloads.count == 2)
        #expect(inSessionPayloads[0].filename == "spec.pdf")
        #expect(inSessionPayloads[1].isInline == true)
        #expect(inSessionPayloads[1].contentID == "img1")

        // Foreign sourceID is rejected.
        await #expect(throws: MailBackendError.self) {
            _ = try await session1.draft(for: "e-draft-att-1", sourceID: foreignSourceID)
        }

        // 2. Post-restart (fresh JMAPBackend instance): remote draft + attachments are reconstructed and staged.
        let session2 = JMAPBackend(
            account: Self.makeAccount(),
            sessionURL: Self.sessionURL,
            tokenProvider: StaticJMAPAccessTokenProvider(token: "tok-123"),
            transport: transport
        )
        try await session2.connect()
        let reopened = try #require(try await session2.draft(for: "e-draft-att-1", sourceID: sourceID))
        #expect(reopened.remoteID == "e-draft-att-1")
        #expect(reopened.attachmentIDs.count == 2)
        let attachmentService2 = try #require(session2.extensionService(LocalDraftAttachmentProviding.self))
        let restoredPayloads = try await attachmentService2.localDraftAttachments(for: reopened, sourceID: sourceID)
        #expect(restoredPayloads.count == 2)
        #expect(restoredPayloads[0].data == Data("PDF-BYTES".utf8))
        #expect(restoredPayloads[0].isInline == false)
        #expect(restoredPayloads[0].contentID == nil)
        #expect(restoredPayloads[1].data == Data("PNG-BYTES".utf8))
        #expect(restoredPayloads[1].isInline == true)
        #expect(restoredPayloads[1].contentID == "img1")
    }

    @Test("discarding a reopened server draft destroys the canonical remote ID rather than the local UUID")
    func discardReopenedServerDraftDestroysCanonicalRemoteID() async throws {
        let destroyedIDs = RecordedStrings()
        let transport = MockJMAPHTTPTransport { request in
            if request.url == Self.sessionURL {
                return JMAPHTTPResponse(statusCode: 200, body: Self.sampleSessionJSON, finalURL: request.url)
            }
            let decoded = try JSONDecoder().decode(JMAPRequest.self, from: request.body ?? Data())
            let first = decoded.methodCalls.first?.name ?? ""
            if first == "Mailbox/get" {
                return try Self.jsonResponse(Self.initialBootstrapResponse())
            }
            if first == "Email/get" {
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "Email/get",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "state": .string("es-1"),
                                    "list": .array([
                                        .object([
                                            "id": .string("e-server-draft-42"),
                                            "mailboxIds": .object(["mb-drafts": .bool(true)]),
                                            "keywords": .object(["$draft": .bool(true)]),
                                            "subject": .string("Text draft"),
                                            "textBody": .array([.object([
                                                "partId": .string("t"),
                                                "type": .string("text/plain")
                                            ])]),
                                            "bodyValues": .object(["t": .object(["value": .string("Hello")])])
                                        ])
                                    ])
                                ],
                                callID: "g0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            }
            if first == "Email/set",
               case .array(let ids) = decoded.methodCalls.first?.arguments["destroy"] {
                for id in ids {
                    if let str = id.stringValue { await destroyedIDs.append(str) }
                }
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "Email/set",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "newState": .string("es-2"),
                                    "destroyed": .array(ids)
                                ],
                                callID: "es0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            }
            return try Self.jsonResponse(Self.initialBootstrapResponse())
        }

        let backend = JMAPBackend(
            account: Self.makeAccount(),
            sessionURL: Self.sessionURL,
            tokenProvider: StaticJMAPAccessTokenProvider(token: "tok-123"),
            transport: transport
        )
        try await backend.connect()
        let sourceID = MailSourceID(accountID: backend.account.id, mailboxID: backend.account.id)
        let reopened = try #require(try await backend.draft(for: "e-server-draft-42", sourceID: sourceID))
        #expect(reopened.id != "e-server-draft-42")
        #expect(reopened.remoteID == "e-server-draft-42")

        try await backend.discard(draftID: reopened.id, sourceID: sourceID)
        #expect(await destroyedIDs.values == ["e-server-draft-42"])
    }

    @Test("rejected draft edits keep the prior saved draft intact and retain new ID if old cleanup fails")
    func rejectedDraftEditPreservesPreviousSavedDraft() async throws {
        let phase = PhaseBox()
        let destroyedIDs = RecordedStrings()
        let transport = MockJMAPHTTPTransport { request in
            if request.url == Self.sessionURL {
                return JMAPHTTPResponse(statusCode: 200, body: Self.sampleSessionJSON, finalURL: request.url)
            }
            let decoded = try JSONDecoder().decode(JMAPRequest.self, from: request.body ?? Data())
            let first = decoded.methodCalls.first?.name ?? ""
            if first == "Mailbox/get" {
                return try Self.jsonResponse(Self.initialBootstrapResponse())
            }
            let call = decoded.methodCalls[0]
            if case .array(let ids) = call.arguments["destroy"] {
                for id in ids {
                    if let str = id.stringValue { await destroyedIDs.append(str) }
                }
                // Simulate cleanup failure on phase 2.
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "Email/set",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "notDestroyed": .object(["e-draft-1": .object(["type": .string("serverFail")])])
                                ],
                                callID: "es0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            }
            let currentPhase = await phase.phase
            if currentPhase == 0 {
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "Email/set",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "created": .object(["draft": .object(["id": .string("e-draft-1")])])
                                ],
                                callID: "es0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            }
            if currentPhase == 1 {
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "Email/set",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "notCreated": .object(["draft": .object(["type": .string("tooLarge")])])
                                ],
                                callID: "es0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            }
            return try Self.jsonResponse(
                JMAPResponse(
                    methodResponses: [
                        JMAPInvocation(
                            name: "Email/set",
                            arguments: [
                                "accountId": .string("u123"),
                                "created": .object(["draft": .object(["id": .string("e-draft-2")])])
                            ],
                            callID: "es0"
                        )
                    ],
                    sessionState: "sess-1"
                )
            )
        }

        let backend = JMAPBackend(
            account: Self.makeAccount(),
            sessionURL: Self.sessionURL,
            tokenProvider: StaticJMAPAccessTokenProvider(token: "tok-123"),
            transport: transport
        )
        try await backend.connect()

        let initial = try await backend.save(draft: Draft(id: "d-edit", subject: "v1"))
        #expect(initial.remoteID == "e-draft-1")

        // Rejected v2 edit must NOT destroy e-draft-1.
        await phase.set(1)
        var edited = initial
        edited.subject = "v2 too large"
        await #expect(throws: MailBackendError.self) {
            _ = try await backend.save(draft: edited)
        }
        #expect(await destroyedIDs.values.isEmpty)
        #expect(try await backend.draft(for: "e-draft-1")?.subject == "v1")

        // Accepted v3 edit retains e-draft-2 even if old draft cleanup fails.
        await phase.set(2)
        edited.subject = "v3 ok"
        let savedV3 = try await backend.save(draft: edited)
        #expect(savedV3.remoteID == "e-draft-2")
        #expect(await destroyedIDs.values == ["e-draft-1"])
    }

    @Test("failed send keeps saved draft intact, cleans staging copy, and retry reports non-fatal cleanup warnings")
    func failedSendPreservesSavedDraftAndRetrySucceeds() async throws {
        let phase = PhaseBox()
        let destroyedIDs = RecordedStrings()
        let transport = MockJMAPHTTPTransport { request in
            if request.url == Self.sessionURL {
                return JMAPHTTPResponse(statusCode: 200, body: Self.sampleSessionJSON, finalURL: request.url)
            }
            let decoded = try JSONDecoder().decode(JMAPRequest.self, from: request.body ?? Data())
            let first = decoded.methodCalls.first?.name ?? ""
            if first == "Mailbox/get" {
                return try Self.jsonResponse(Self.initialBootstrapResponse())
            }
            if decoded.methodCalls.count == 2, decoded.methodCalls[1].name == "EmailSubmission/set" {
                let currentPhase = await phase.phase
                if currentPhase == 1 {
                    return try Self.jsonResponse(
                        JMAPResponse(
                            methodResponses: [
                                JMAPInvocation(
                                    name: "Email/set",
                                    arguments: [
                                        "accountId": .string("u123"),
                                        "created": .object(["draft": .object(["id": .string("e-staging-failed")])])
                                    ],
                                    callID: "es0"
                                ),
                                JMAPInvocation(
                                    name: "EmailSubmission/set",
                                    arguments: [
                                        "accountId": .string("u123"),
                                        "notCreated": .object(["send": .object(["type": .string("invalidRecipients")])])
                                    ],
                                    callID: "sub0"
                                )
                            ],
                            sessionState: "sess-1"
                        )
                    )
                }
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "Email/set",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "created": .object(["draft": .object(["id": .string("e-sent-retry")])])
                                ],
                                callID: "es0"
                            ),
                            JMAPInvocation(
                                name: "EmailSubmission/set",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "created": .object(["send": .object(["id": .string("sub-retry")])])
                                ],
                                callID: "sub0"
                            ),
                            JMAPInvocation(
                                name: "Email/set",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "notUpdated": .object(["e-sent-retry": .object(["type": .string("overQuota")])])
                                ],
                                callID: "sub0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            }
            if case .array(let ids) = decoded.methodCalls.first?.arguments["destroy"] {
                let firstID = ids.first?.stringValue ?? ""
                await destroyedIDs.append(firstID)
                if firstID == "e-draft-keep" {
                    return try Self.jsonResponse(
                        JMAPResponse(
                            methodResponses: [
                                JMAPInvocation(
                                    name: "Email/set",
                                    arguments: [
                                        "accountId": .string("u123"),
                                        "notDestroyed": .object(["e-draft-keep": .object(["type": .string("serverFail")])])
                                    ],
                                    callID: "es0"
                                )
                            ],
                            sessionState: "sess-1"
                        )
                    )
                }
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "Email/set",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "destroyed": .array(ids)
                                ],
                                callID: "es0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            }
            return try Self.jsonResponse(
                JMAPResponse(
                    methodResponses: [
                        JMAPInvocation(
                            name: "Email/set",
                            arguments: [
                                "accountId": .string("u123"),
                                "created": .object(["draft": .object(["id": .string("e-draft-keep")])])
                            ],
                            callID: "es0"
                        )
                    ],
                    sessionState: "sess-1"
                )
            )
        }

        let backend = JMAPBackend(
            account: Self.makeAccount(),
            sessionURL: Self.sessionURL,
            tokenProvider: StaticJMAPAccessTokenProvider(token: "tok-123"),
            transport: transport
        )
        try await backend.connect()

        let saved = try await backend.save(
            draft: Draft(
                id: "d-send-retry",
                to: [Correspondent(email: "bad@invalid")],
                subject: "Retry me"
            )
        )
        #expect(saved.remoteID == "e-draft-keep")

        // First send fails in EmailSubmission/set: prior draft must NOT be destroyed, staging copy IS cleaned up.
        await phase.set(1)
        await #expect(throws: MailBackendError.self) {
            _ = try await backend.send(draft: saved)
        }
        #expect(await destroyedIDs.values == ["e-staging-failed"])
        #expect(try await backend.draft(for: "e-draft-keep") != nil)

        // Retry succeeds; Sent-move failure and post-send draft cleanup failure surface as non-fatal warnings.
        await phase.set(2)
        var fixed = saved
        fixed.to = [Correspondent(email: "good@example.org")]
        let result = try await backend.send(draft: fixed)
        #expect(result.sentMessageID == "e-sent-retry")
        #expect(result.warnings.contains(.sentCopyAppendFailed))
        #expect(result.warnings.contains(.remoteDraftCleanupFailed))
        #expect(await destroyedIDs.values == ["e-staging-failed", "e-draft-keep"])
    }

    @Test("server search paginates beyond 50 matches and returns every matching header")
    func serverSearchPaginatesBeyondFiftyMatches() async throws {
        let totalMatches = 120
        let pageCappedSessionJSON = Data("""
        {
          "capabilities": {
            "urn:ietf:params:jmap:core": {
              "maxSizeUpload": 50000000,
              "maxCallsInRequest": 32,
              "maxObjectsInGet": 50
            },
            "urn:ietf:params:jmap:mail": {}
          },
          "accounts": {
            "u123": { "name": "henrik@fastmail.com", "isPersonal": true, "isReadOnly": false,
                      "accountCapabilities": { "urn:ietf:params:jmap:mail": {} } }
          },
          "primaryAccounts": { "urn:ietf:params:jmap:mail": "u123" },
          "username": "henrik@fastmail.com",
          "apiUrl": "https://api.fastmail.com/jmap/api/",
          "downloadUrl": "https://api.fastmail.com/jmap/download/{accountId}/{blobId}/{name}?accept={type}",
          "uploadUrl": "https://api.fastmail.com/jmap/upload/{accountId}/",
          "state": "sess-1"
        }
        """.utf8)
        let pageQueries = RequestCounter()
        let transport = MockJMAPHTTPTransport { request in
            if request.url == Self.sessionURL {
                return JMAPHTTPResponse(statusCode: 200, body: pageCappedSessionJSON, finalURL: request.url)
            }
            let decoded = try JSONDecoder().decode(JMAPRequest.self, from: request.body ?? Data())
            if decoded.methodCalls.first?.name == "Mailbox/get" {
                return try Self.jsonResponse(Self.initialBootstrapResponse())
            }
            await pageQueries.increment()
            let position = decoded.methodCalls[0].arguments["position"]?.intValue ?? 0
            let limit = decoded.methodCalls[0].arguments["limit"]?.intValue ?? 50
            let end = min(position + limit, totalMatches)
            let pageIDs = (position ..< end).map { "e-search-\($0)" }
            let list: [JMAPJSONValue] = pageIDs.map { id in
                .object([
                    "id": .string(id),
                    "mailboxIds": .object(["mb-inbox": .bool(true)]),
                    "receivedAt": .string("2026-11-25T09:00:00Z"),
                    "from": .array([.object(["email": .string("match@example.org")])]),
                    "subject": .string("Match \(id)")
                ])
            }
            return try Self.jsonResponse(
                JMAPResponse(
                    methodResponses: [
                        JMAPInvocation(
                            name: "Email/query",
                            arguments: [
                                "accountId": .string("u123"),
                                "position": .int(position),
                                "ids": .array(pageIDs.map { .string($0) }),
                                "total": .int(totalMatches)
                            ],
                            callID: "q0"
                        ),
                        JMAPInvocation(
                            name: "Email/get",
                            arguments: [
                                "accountId": .string("u123"),
                                "state": .string("es-search"),
                                "list": .array(list)
                            ],
                            callID: "g0"
                        )
                    ],
                    sessionState: "sess-1"
                )
            )
        }

        let backend = JMAPBackend(
            account: Self.makeAccount(),
            sessionURL: Self.sessionURL,
            tokenProvider: StaticJMAPAccessTokenProvider(token: "tok-123"),
            transport: transport
        )
        try await backend.connect()
        let results = try await backend.search(SearchQuery(text: "Match"))
        #expect(results.count == totalMatches)
        #expect(await pageQueries.count == 3)
        #expect(results.first?.id == "e-search-0")
        #expect(results.last?.id == "e-search-119")
    }

    @Test("flushFolder loops past server query caps and chunks Email/set destroy by maxObjectsInSet")
    func flushFolderRespectsServerQueryCapAndMaxObjectsInSet() async throws {
        let cappedSessionJSON = Data("""
        {
          "capabilities": {
            "urn:ietf:params:jmap:core": {
              "maxSizeUpload": 50000000,
              "maxCallsInRequest": 32,
              "maxObjectsInGet": 500,
              "maxObjectsInSet": 2
            },
            "urn:ietf:params:jmap:mail": {}
          },
          "accounts": {
            "u123": { "name": "henrik@fastmail.com", "isPersonal": true, "isReadOnly": false,
                      "accountCapabilities": { "urn:ietf:params:jmap:mail": {} } }
          },
          "primaryAccounts": { "urn:ietf:params:jmap:mail": "u123" },
          "username": "henrik@fastmail.com",
          "apiUrl": "https://api.fastmail.com/jmap/api/",
          "downloadUrl": "https://api.fastmail.com/jmap/download/{accountId}/{blobId}/{name}?accept={type}",
          "uploadUrl": "https://api.fastmail.com/jmap/upload/{accountId}/",
          "state": "sess-1"
        }
        """.utf8)

        let trashBox = RemainingTrashBox(ids: ["t1", "t2", "t3", "t4", "t5"])
        let destroyBatchSizes = RecordedInts()
        let transport = MockJMAPHTTPTransport { request in
            if request.url == Self.sessionURL {
                return JMAPHTTPResponse(statusCode: 200, body: cappedSessionJSON, finalURL: request.url)
            }
            let decoded = try JSONDecoder().decode(JMAPRequest.self, from: request.body ?? Data())
            let first = decoded.methodCalls.first?.name ?? ""
            if first == "Mailbox/get" {
                return try Self.jsonResponse(Self.initialBootstrapResponse())
            }
            if first == "Email/query" {
                // Server caps query to at most 2 IDs per call (far below 500).
                let batch = await trashBox.peek(limit: 2)
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "Email/query",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "position": .int(0),
                                    "ids": .array(batch.map { .string($0) })
                                ],
                                callID: "q0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            }
            if first == "Email/set",
               case .array(let destroyVals) = decoded.methodCalls.first?.arguments["destroy"] {
                let ids = destroyVals.compactMap(\.stringValue)
                await destroyBatchSizes.append(ids.count)
                await trashBox.remove(ids)
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "Email/set",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "newState": .string("es-trash"),
                                    "destroyed": .array(ids.map { .string($0) })
                                ],
                                callID: "es0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            }
            return try Self.jsonResponse(Self.initialBootstrapResponse())
        }

        let backend = JMAPBackend(
            account: Self.makeAccount(),
            sessionURL: Self.sessionURL,
            tokenProvider: StaticJMAPAccessTokenProvider(token: "tok-123"),
            transport: transport
        )
        try await backend.connect()
        try await backend.flushFolder(id: "mb-trash")

        #expect(await trashBox.remaining.isEmpty)
        let sizes = await destroyBatchSizes.values
        #expect(sizes == [2, 2, 1])
        #expect(sizes.allSatisfy { $0 <= 2 })
    }

    @Test("EventSource reconnect reconciles mail delivered during disconnect gap without waiting for a new event")
    func eventSourceReconnectReconcilesGapWithoutNewEvent() async throws {
        let streamOpens = RequestCounter()
        let retryAttempts = RecordedInts()
        let transport = MockJMAPHTTPTransport(
            handler: { request in
                if request.url == Self.sessionURL {
                    return JMAPHTTPResponse(statusCode: 200, body: Self.sampleSessionJSON, finalURL: request.url)
                }
                let decoded = try JSONDecoder().decode(JMAPRequest.self, from: request.body ?? Data())
                let first = decoded.methodCalls.first?.name ?? ""
                if first == "Mailbox/get" {
                    return try Self.jsonResponse(Self.initialBootstrapResponse())
                }
                if first == "Email/query" {
                    return try Self.jsonResponse(
                        JMAPResponse(
                            methodResponses: [
                                JMAPInvocation(
                                    name: "Email/query",
                                    arguments: [
                                        "accountId": .string("u123"),
                                        "position": .int(0),
                                        "ids": .array([.string("e-before-gap")]),
                                        "total": .int(1)
                                    ],
                                    callID: "q0"
                                ),
                                JMAPInvocation(
                                    name: "Email/get",
                                    arguments: [
                                        "accountId": .string("u123"),
                                        "state": .string("es-gap-1"),
                                        "list": .array([
                                            .object([
                                                "id": .string("e-before-gap"),
                                                "mailboxIds": .object(["mb-inbox": .bool(true)]),
                                                "receivedAt": .string("2026-11-25T09:00:00Z"),
                                                "from": .array([.object(["email": .string("a@example.org")])]),
                                                "subject": .string("Before gap")
                                            ])
                                        ])
                                    ],
                                    callID: "g0"
                                )
                            ],
                            sessionState: "sess-1"
                        )
                    )
                }
                if first == "Mailbox/changes" {
                    return try Self.jsonResponse(
                        JMAPResponse(
                            methodResponses: [
                                JMAPInvocation(
                                    name: "Mailbox/changes",
                                    arguments: [
                                        "accountId": .string("u123"),
                                        "oldState": .string("mb-state-1"),
                                        "newState": .string("mb-state-1")
                                    ],
                                    callID: "mc0"
                                )
                            ],
                            sessionState: "sess-1"
                        )
                    )
                }
                if first == "Email/changes" {
                    return try Self.jsonResponse(
                        JMAPResponse(
                            methodResponses: [
                                JMAPInvocation(
                                    name: "Email/changes",
                                    arguments: [
                                        "accountId": .string("u123"),
                                        "oldState": .string("es-gap-1"),
                                        "newState": .string("es-gap-2"),
                                        "created": .array([.string("e-missed-during-gap")])
                                    ],
                                    callID: "ec0"
                                )
                            ],
                            sessionState: "sess-1"
                        )
                    )
                }
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "Email/get",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "state": .string("es-gap-2"),
                                    "list": .array([
                                        .object([
                                            "id": .string("e-missed-during-gap"),
                                            "mailboxIds": .object(["mb-inbox": .bool(true)]),
                                            "receivedAt": .string("2026-11-25T09:05:00Z"),
                                            "from": .array([.object(["email": .string("gap@example.org")])]),
                                            "subject": .string("Arrived during disconnect")
                                        ])
                                    ])
                                ],
                                callID: "g0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            },
            sseHandler: { _ in
                AsyncThrowingStream { continuation in
                    Task {
                        await streamOpens.increment()
                        let openIndex = await streamOpens.count
                        if openIndex == 1 {
                            // First stream closes cleanly (EOF) without sending any state frame.
                            continuation.finish()
                        }
                        // Second stream stays open and completely silent (zero frames emitted).
                    }
                }
            }
        )

        let backend = JMAPBackend(
            account: Self.makeAccount(),
            sessionURL: Self.sessionURL,
            tokenProvider: StaticJMAPAccessTokenProvider(token: "tok-123"),
            transport: transport,
            eventSourceRetryDelay: { attempt in
                Task { await retryAttempts.append(attempt) }
                return 5_000_000
            }
        )
        try await backend.connect()
        let inbox = Folder(id: "mb-inbox", name: "Inbox", role: .inbox)
        _ = try await backend.messages(in: inbox, pageToken: nil)

        var caughtGapMessage = false
        for await event in backend.subscribeToChanges() {
            if case .messagesAdded(let folderID, let ids) = event,
               folderID == "mb-inbox",
               ids.contains("e-missed-during-gap") {
                caughtGapMessage = true
                break
            }
        }
        #expect(caughtGapMessage)
        #expect(await streamOpens.count >= 2)
        #expect(await retryAttempts.values.contains(1))
        await backend.disconnect()
    }

    @Test("accepted submission followed by implicit Sent-move error tuple reports warning without deleting sent copy")
    func acceptedSubmissionFollowedByImplicitErrorReportsSentCopyWarning() async throws {
        let destroyedIDs = RecordedStrings()
        let transport = MockJMAPHTTPTransport { request in
            if request.url == Self.sessionURL {
                return JMAPHTTPResponse(statusCode: 200, body: Self.sampleSessionJSON, finalURL: request.url)
            }
            let decoded = try JSONDecoder().decode(JMAPRequest.self, from: request.body ?? Data())
            let first = decoded.methodCalls.first?.name ?? ""
            if first == "Mailbox/get" {
                return try Self.jsonResponse(Self.initialBootstrapResponse())
            }
            if decoded.methodCalls.count == 2, decoded.methodCalls[1].name == "EmailSubmission/set" {
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "Email/set",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "created": .object(["draft": .object(["id": .string("e-sent-wire-1")])])
                                ],
                                callID: "es0"
                            ),
                            JMAPInvocation(
                                name: "EmailSubmission/set",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "created": .object(["send": .object(["id": .string("sub-wire-1")])])
                                ],
                                callID: "sub0"
                            ),
                            // Method-level error for implicit onSuccessUpdateEmail under the same callID.
                            JMAPInvocation(
                                name: "error",
                                arguments: [
                                    "type": .string("serverFail"),
                                    "description": .string("Sent mailbox temporarily unavailable")
                                ],
                                callID: "sub0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            }
            if case .array(let ids) = decoded.methodCalls.first?.arguments["destroy"] {
                for id in ids {
                    if let str = id.stringValue { await destroyedIDs.append(str) }
                }
            }
            return try Self.jsonResponse(Self.initialBootstrapResponse())
        }

        let backend = JMAPBackend(
            account: Self.makeAccount(),
            sessionURL: Self.sessionURL,
            tokenProvider: StaticJMAPAccessTokenProvider(token: "tok-123"),
            transport: transport
        )
        try await backend.connect()
        let result = try await backend.send(
            draft: Draft(
                id: "d-wire-err",
                to: [Correspondent(email: "bob@example.org")],
                subject: "Important",
                htmlBody: "<p>Sent once</p>"
            )
        )
        #expect(result.sentMessageID == "e-sent-wire-1")
        #expect(result.warnings == [.sentCopyAppendFailed])
        // Must NOT enter failed-submission cleanup and destroy e-sent-wire-1.
        #expect(await destroyedIDs.values.isEmpty)
    }

    @Test("delta sync chunks Email/get and Mailbox/get by maxObjectsInGet after bulk updates")
    func deltaSyncChunksEmailAndMailboxGetByMaxObjectsInGet() async throws {
        let cappedGetSessionJSON = Data("""
        {
          "capabilities": {
            "urn:ietf:params:jmap:core": {
              "maxSizeUpload": 50000000,
              "maxCallsInRequest": 32,
              "maxObjectsInGet": 2,
              "maxObjectsInSet": 100
            },
            "urn:ietf:params:jmap:mail": {}
          },
          "accounts": {
            "u123": { "name": "henrik@fastmail.com", "isPersonal": true, "isReadOnly": false,
                      "accountCapabilities": { "urn:ietf:params:jmap:mail": {} } }
          },
          "primaryAccounts": { "urn:ietf:params:jmap:mail": "u123" },
          "username": "henrik@fastmail.com",
          "apiUrl": "https://api.fastmail.com/jmap/api/",
          "downloadUrl": "https://api.fastmail.com/jmap/download/{accountId}/{blobId}/{name}?accept={type}",
          "uploadUrl": "https://api.fastmail.com/jmap/upload/{accountId}/",
          "state": "sess-1"
        }
        """.utf8)

        let emailGetBatchSizes = RecordedInts()
        let mailboxGetBatchSizes = RecordedInts()
        let transport = MockJMAPHTTPTransport { request in
            if request.url == Self.sessionURL {
                return JMAPHTTPResponse(statusCode: 200, body: cappedGetSessionJSON, finalURL: request.url)
            }
            let decoded = try JSONDecoder().decode(JMAPRequest.self, from: request.body ?? Data())
            let first = decoded.methodCalls.first?.name ?? ""
            if first == "Mailbox/get" {
                if case .array(let idVals) = decoded.methodCalls[0].arguments["ids"] {
                    let ids = idVals.compactMap(\.stringValue)
                    await mailboxGetBatchSizes.append(ids.count)
                    if ids.count > 2 {
                        return try Self.jsonResponse(
                            JMAPResponse(
                                methodResponses: [
                                    JMAPInvocation(name: "error", arguments: ["type": .string("requestTooLarge")], callID: "m0")
                                ],
                                sessionState: "sess-1"
                            )
                        )
                    }
                    let list: [JMAPJSONValue] = ids.map { id in
                        .object([
                            "id": .string(id),
                            "name": .string("Folder \(id)"),
                            "totalEmails": .int(10),
                            "unreadEmails": .int(0)
                        ])
                    }
                    return try Self.jsonResponse(
                        JMAPResponse(
                            methodResponses: [
                                JMAPInvocation(
                                    name: "Mailbox/get",
                                    arguments: [
                                        "accountId": .string("u123"),
                                        "state": .string("mb-state-2"),
                                        "list": .array(list)
                                    ],
                                    callID: "m0"
                                )
                            ],
                            sessionState: "sess-1"
                        )
                    )
                }
                return try Self.jsonResponse(Self.initialBootstrapResponse())
            }
            if first == "Email/query" {
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "Email/query",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "position": .int(0),
                                    "ids": .array([.string("e1")]),
                                    "total": .int(1)
                                ],
                                callID: "q0"
                            ),
                            JMAPInvocation(
                                name: "Email/get",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "state": .string("es-1"),
                                    "list": .array([
                                        .object([
                                            "id": .string("e1"),
                                            "mailboxIds": .object(["mb-inbox": .bool(true)]),
                                            "receivedAt": .string("2026-11-25T09:00:00Z"),
                                            "from": .array([.object(["email": .string("a@example.org")])]),
                                            "subject": .string("Seed")
                                        ])
                                    ])
                                ],
                                callID: "g0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            }
            if first == "Mailbox/changes" {
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "Mailbox/changes",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "oldState": .string("mb-state-1"),
                                    "newState": .string("mb-state-2"),
                                    "updated": .array([.string("mb-inbox"), .string("mb-archive"), .string("mb-custom")])
                                ],
                                callID: "mc0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            }
            if first == "Email/changes" {
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "Email/changes",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "oldState": .string("es-1"),
                                    "newState": .string("es-bulk-2"),
                                    "updated": .array([
                                        .string("e1"), .string("e2"), .string("e3"), .string("e4"), .string("e5")
                                    ])
                                ],
                                callID: "ec0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            }
            if first == "Email/get",
               case .array(let idVals) = decoded.methodCalls[0].arguments["ids"] {
                let ids = idVals.compactMap(\.stringValue)
                await emailGetBatchSizes.append(ids.count)
                if ids.count > 2 {
                    return try Self.jsonResponse(
                        JMAPResponse(
                            methodResponses: [
                                JMAPInvocation(name: "error", arguments: ["type": .string("requestTooLarge")], callID: "g0")
                            ],
                            sessionState: "sess-1"
                        )
                    )
                }
                let list: [JMAPJSONValue] = ids.map { id in
                    .object([
                        "id": .string(id),
                        "mailboxIds": .object(["mb-inbox": .bool(true)]),
                        "keywords": .object(["$seen": .bool(true)]),
                        "receivedAt": .string("2026-11-25T09:00:00Z"),
                        "from": .array([.object(["email": .string("a@example.org")])]),
                        "subject": .string("Bulk \(id)")
                    ])
                }
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "Email/get",
                                arguments: ["accountId": .string("u123"), "state": .string("es-bulk-2"), "list": .array(list)],
                                callID: "g0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            }
            return try Self.jsonResponse(Self.initialBootstrapResponse())
        }

        let backend = JMAPBackend(
            account: Self.makeAccount(),
            sessionURL: Self.sessionURL,
            tokenProvider: StaticJMAPAccessTokenProvider(token: "tok-123"),
            transport: transport
        )
        try await backend.connect()
        let inbox = Folder(id: "mb-inbox", name: "Inbox", role: .inbox)
        _ = try await backend.messages(in: inbox, pageToken: nil)
        try await backend.refresh(folder: inbox)

        #expect(backend.currentEmailState == "es-bulk-2")
        #expect(backend.currentMailboxState == "mb-state-2")
        let emailBatches = await emailGetBatchSizes.values
        let mbBatches = await mailboxGetBatchSizes.values
        #expect(emailBatches.count == 3)
        #expect(emailBatches.allSatisfy { $0 <= 2 })
        #expect(mbBatches.count == 2)
        #expect(mbBatches.allSatisfy { $0 <= 2 })
    }

    @Test("reopening a remote plain-text draft HTML-escapes angle brackets and entities and preserves line breaks")
    func plainTextRemoteDraftEscapesMarkupAndPreservesLineBreaks() async throws {
        let transport = MockJMAPHTTPTransport { request in
            if request.url == Self.sessionURL {
                return JMAPHTTPResponse(statusCode: 200, body: Self.sampleSessionJSON, finalURL: request.url)
            }
            let decoded = try JSONDecoder().decode(JMAPRequest.self, from: request.body ?? Data())
            if decoded.methodCalls.first?.name == "Mailbox/get" {
                return try Self.jsonResponse(Self.initialBootstrapResponse())
            }
            return try Self.jsonResponse(
                JMAPResponse(
                    methodResponses: [
                        JMAPInvocation(
                            name: "Email/get",
                            arguments: [
                                "accountId": .string("u123"),
                                "state": .string("es-1"),
                                "list": .array([
                                    .object([
                                        "id": .string("e-plain-draft"),
                                        "mailboxIds": .object(["mb-drafts": .bool(true)]),
                                        "keywords": .object(["$draft": .bool(true)]),
                                        "subject": .string("Plain template"),
                                        "textBody": .array([.object(["partId": .string("t1"), "type": .string("text/plain")])]),
                                        "bodyValues": .object([
                                            "t1": .object([
                                                "value": .string("Replace <your-name> & \"company\"'s info\r\nLine 2")
                                            ])
                                        ])
                                    ])
                                ])
                            ],
                            callID: "g0"
                        )
                    ],
                    sessionState: "sess-1"
                )
            )
        }

        let backend = JMAPBackend(
            account: Self.makeAccount(),
            sessionURL: Self.sessionURL,
            tokenProvider: StaticJMAPAccessTokenProvider(token: "tok-123"),
            transport: transport
        )
        try await backend.connect()
        let restored = try #require(try await backend.draft(for: "e-plain-draft"))
        #expect(restored.htmlBody == "Replace &lt;your-name&gt; &amp; &quot;company&quot;&#39;s info<br>Line 2")
    }

    @Test("reopening and sending a remote attachment-bearing draft preserves its non-default sender identity")
    func reopenedRemoteDraftPreservesNonDefaultSenderIdentityOnSend() async throws {
        let recordedSubmissionIdentity = RecordedStrings()
        let recordedMailFrom = RecordedStrings()
        let transport = MockJMAPHTTPTransport { request in
            if request.url == Self.sessionURL {
                return JMAPHTTPResponse(statusCode: 200, body: Self.sampleSessionJSON, finalURL: request.url)
            }
            if request.url.absoluteString.contains("/jmap/download/") {
                return JMAPHTTPResponse(statusCode: 200, body: Data("PDF".utf8), finalURL: request.url)
            }
            let decoded = try JSONDecoder().decode(JMAPRequest.self, from: request.body ?? Data())
            let first = decoded.methodCalls.first?.name ?? ""
            if first == "Mailbox/get" {
                return try Self.jsonResponse(Self.initialBootstrapResponse())
            }
            if first == "Email/get" {
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "Email/get",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "state": .string("es-1"),
                                    "list": .array([
                                        .object([
                                            "id": .string("e-alias-draft"),
                                            "mailboxIds": .object(["mb-drafts": .bool(true)]),
                                            "keywords": .object(["$draft": .bool(true)]),
                                            "from": .array([.object([
                                                "name": .string("Henrik Work"),
                                                "email": .string("work@example.org")
                                            ])]),
                                            "to": .array([.object(["email": .string("client@example.org")])]),
                                            "subject": .string("Proposal"),
                                            "htmlBody": .array([.object([
                                                "partId": .string("h1"),
                                                "type": .string("text/html")
                                            ])]),
                                            "bodyValues": .object(["h1": .object(["value": .string("<p>Attached</p>")])]),
                                            "attachments": .array([
                                                .object([
                                                    "partId": .string("p1"),
                                                    "blobId": .string("blob-prop-1"),
                                                    "type": .string("application/pdf"),
                                                    "name": .string("proposal.pdf"),
                                                    "size": .int(3),
                                                    "disposition": .string("attachment")
                                                ])
                                            ])
                                        ])
                                    ])
                                ],
                                callID: "g0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            }
            if decoded.methodCalls.count == 2, decoded.methodCalls[1].name == "EmailSubmission/set" {
                if let sendObj = decoded.methodCalls[1].arguments["create"]?.objectValue?["send"]?.objectValue {
                    if let identityID = sendObj["identityId"]?.stringValue {
                        await recordedSubmissionIdentity.append(identityID)
                    }
                    if let mailFrom = sendObj["envelope"]?.objectValue?["mailFrom"]?.objectValue?["email"]?.stringValue {
                        await recordedMailFrom.append(mailFrom)
                    }
                }
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "Email/set",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "created": .object(["draft": .object(["id": .string("e-sent-alias")])])
                                ],
                                callID: "es0"
                            ),
                            JMAPInvocation(
                                name: "EmailSubmission/set",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "created": .object(["send": .object(["id": .string("sub-alias")])])
                                ],
                                callID: "sub0"
                            ),
                            JMAPInvocation(
                                name: "Email/set",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "updated": .object(["e-sent-alias": .null])
                                ],
                                callID: "sub0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            }
            return try Self.jsonResponse(
                JMAPResponse(
                    methodResponses: [
                        JMAPInvocation(
                            name: "Email/set",
                            arguments: ["accountId": .string("u123"), "destroyed": .array([.string("e-alias-draft")])],
                            callID: "es0"
                        )
                    ],
                    sessionState: "sess-1"
                )
            )
        }

        let backend = JMAPBackend(
            account: Self.makeAccount(),
            sessionURL: Self.sessionURL,
            tokenProvider: StaticJMAPAccessTokenProvider(token: "tok-123"),
            transport: transport
        )
        try await backend.connect()
        let sourceID = MailSourceID(accountID: backend.account.id, mailboxID: backend.account.id)
        let reopened = try #require(try await backend.draft(for: "e-alias-draft", sourceID: sourceID))
        #expect(reopened.identityID == "id-2")

        let sendResult = try await backend.send(draft: reopened)
        #expect(sendResult.sentMessageID == "e-sent-alias")
        #expect(await recordedSubmissionIdentity.values == ["id-2"])
        #expect(await recordedMailFrom.values == ["work@example.org"])
    }

    @Test("flushFolder reconciles partial destroyed IDs before surfacing notDestroyed error")
    func flushFolderReconcilesPartialDestroyedBeforeSurfacingNotDestroyedError() async throws {
        let transport = MockJMAPHTTPTransport { request in
            if request.url == Self.sessionURL {
                return JMAPHTTPResponse(statusCode: 200, body: Self.sampleSessionJSON, finalURL: request.url)
            }
            let decoded = try JSONDecoder().decode(JMAPRequest.self, from: request.body ?? Data())
            let first = decoded.methodCalls.first?.name ?? ""
            if first == "Mailbox/get" {
                return try Self.jsonResponse(Self.initialBootstrapResponse())
            }
            if first == "Email/query", decoded.methodCalls.count == 2 {
                // Initial Trash cache seed.
                let ids = ["t1", "t2", "t3"]
                let list: [JMAPJSONValue] = ids.map { id in
                    .object([
                        "id": .string(id),
                        "mailboxIds": .object(["mb-trash": .bool(true)]),
                        "receivedAt": .string("2026-11-25T09:00:00Z"),
                        "from": .array([.object(["email": .string("trash@example.org")])]),
                        "subject": .string("Trash \(id)")
                    ])
                }
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "Email/query",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "position": .int(0),
                                    "ids": .array(ids.map { .string($0) }),
                                    "total": .int(3)
                                ],
                                callID: "q0"
                            ),
                            JMAPInvocation(
                                name: "Email/get",
                                arguments: ["accountId": .string("u123"), "state": .string("es-trash-1"), "list": .array(list)],
                                callID: "g0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            }
            if first == "Email/query" {
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "Email/query",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "position": .int(0),
                                    "ids": .array([.string("t1"), .string("t2"), .string("t3")])
                                ],
                                callID: "q0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            }
            // Partial success: t1 and t2 destroyed, t3 rejected.
            return try Self.jsonResponse(
                JMAPResponse(
                    methodResponses: [
                        JMAPInvocation(
                            name: "Email/set",
                            arguments: [
                                "accountId": .string("u123"),
                                "destroyed": .array([.string("t1"), .string("t2")]),
                                "notDestroyed": .object(["t3": .object(["type": .string("cannotDestroy")])])
                            ],
                            callID: "es0"
                        )
                    ],
                    sessionState: "sess-1"
                )
            )
        }

        let backend = JMAPBackend(
            account: Self.makeAccount(),
            sessionURL: Self.sessionURL,
            tokenProvider: StaticJMAPAccessTokenProvider(token: "tok-123"),
            transport: transport
        )
        try await backend.connect()
        let trash = Folder(id: "mb-trash", name: "Trash", role: .trash)
        _ = try await backend.messages(in: trash, pageToken: nil)

        await #expect(throws: MailBackendError.self) {
            try await backend.flushFolder(id: "mb-trash")
        }
        let sourceID = MailSourceID(accountID: backend.account.id, mailboxID: backend.account.id)
        let remaining = try await backend.cachedMessageHeaders(in: trash, sourceID: sourceID)
        #expect(remaining.map(\.id) == ["t3"])
    }

    @Test("EventSource reconnect catch-up delta sync waits until stream HTTP readiness completes")
    func eventSourceReconnectCatchUpWaitsForStreamReadiness() async throws {
        let timeline = RecordedStrings()
        let streamOpens = RequestCounter()
        let transport = MockJMAPHTTPTransport(
            handler: { request in
                if request.url == Self.sessionURL {
                    return JMAPHTTPResponse(statusCode: 200, body: Self.sampleSessionJSON, finalURL: request.url)
                }
                let decoded = try JSONDecoder().decode(JMAPRequest.self, from: request.body ?? Data())
                let first = decoded.methodCalls.first?.name ?? ""
                if first == "Mailbox/get" {
                    return try Self.jsonResponse(Self.initialBootstrapResponse())
                }
                if first == "Email/query" {
                    return try Self.jsonResponse(
                        JMAPResponse(
                            methodResponses: [
                                JMAPInvocation(
                                    name: "Email/query",
                                    arguments: [
                                        "accountId": .string("u123"),
                                        "position": .int(0),
                                        "ids": .array([.string("e-init")]),
                                        "total": .int(1)
                                    ],
                                    callID: "q0"
                                ),
                                JMAPInvocation(
                                    name: "Email/get",
                                    arguments: [
                                        "accountId": .string("u123"),
                                        "state": .string("es-r1"),
                                        "list": .array([
                                            .object([
                                                "id": .string("e-init"),
                                                "mailboxIds": .object(["mb-inbox": .bool(true)]),
                                                "receivedAt": .string("2026-11-25T09:00:00Z"),
                                                "from": .array([.object(["email": .string("a@example.org")])]),
                                                "subject": .string("Init")
                                            ])
                                        ])
                                    ],
                                    callID: "g0"
                                )
                            ],
                            sessionState: "sess-1"
                        )
                    )
                }
                if first == "Mailbox/changes" {
                    return try Self.jsonResponse(
                        JMAPResponse(
                            methodResponses: [
                                JMAPInvocation(
                                    name: "Mailbox/changes",
                                    arguments: [
                                        "accountId": .string("u123"),
                                        "oldState": .string("mb-state-1"),
                                        "newState": .string("mb-state-1")
                                    ],
                                    callID: "mc0"
                                )
                            ],
                            sessionState: "sess-1"
                        )
                    )
                }
                if first == "Email/changes" {
                    await timeline.append("delta-sync")
                    return try Self.jsonResponse(
                        JMAPResponse(
                            methodResponses: [
                                JMAPInvocation(
                                    name: "Email/changes",
                                    arguments: [
                                        "accountId": .string("u123"),
                                        "oldState": .string("es-r1"),
                                        "newState": .string("es-r2"),
                                        "created": .array([.string("e-after-ready")])
                                    ],
                                    callID: "ec0"
                                )
                            ],
                            sessionState: "sess-1"
                        )
                    )
                }
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "Email/get",
                                arguments: [
                                    "accountId": .string("u123"),
                                    "state": .string("es-r2"),
                                    "list": .array([
                                        .object([
                                            "id": .string("e-after-ready"),
                                            "mailboxIds": .object(["mb-inbox": .bool(true)]),
                                            "receivedAt": .string("2026-11-25T09:05:00Z"),
                                            "from": .array([.object(["email": .string("ready@example.org")])]),
                                            "subject": .string("Ready gap message")
                                        ])
                                    ])
                                ],
                                callID: "g0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            },
            openSSEHandler: { _ in
                await streamOpens.increment()
                let openIndex = await streamOpens.count
                if openIndex == 1 {
                    return AsyncThrowingStream { $0.finish() }
                }
                // Simulate async HTTP 200 handshake delay before the stream becomes ready.
                try await Task.sleep(nanoseconds: 25_000_000)
                await timeline.append("stream-ready")
                return AsyncThrowingStream { _ in
                    // Silent live stream until disconnected.
                }
            }
        )

        let backend = JMAPBackend(
            account: Self.makeAccount(),
            sessionURL: Self.sessionURL,
            tokenProvider: StaticJMAPAccessTokenProvider(token: "tok-123"),
            transport: transport,
            eventSourceRetryDelay: { _ in 5_000_000 }
        )
        try await backend.connect()
        let inbox = Folder(id: "mb-inbox", name: "Inbox", role: .inbox)
        _ = try await backend.messages(in: inbox, pageToken: nil)

        for await event in backend.subscribeToChanges() {
            if case .messagesAdded(let folderID, let ids) = event,
               folderID == "mb-inbox",
               ids.contains("e-after-ready") {
                break
            }
        }
        #expect(await timeline.values == ["stream-ready", "delta-sync"])
        await backend.disconnect()
    }

    @Test(
        "reopening a remote draft with a From address succeeds when server advertises submission globally but account is mail-only"
    )
    func reopeningDraftSucceedsWhenAccountLacksSubmissionCapability() async throws {
        let mailOnlyAccountSessionJSON = Data("""
        {
          "capabilities": {
            "urn:ietf:params:jmap:core": {},
            "urn:ietf:params:jmap:mail": {},
            "urn:ietf:params:jmap:submission": {}
          },
          "accounts": {
            "u-mail-only": {
              "name": "mail-only@example.org",
              "isPersonal": true,
              "isReadOnly": false,
              "accountCapabilities": {
                "urn:ietf:params:jmap:mail": {}
              }
            }
          },
          "primaryAccounts": {
            "urn:ietf:params:jmap:mail": "u-mail-only"
          },
          "username": "mail-only@example.org",
          "apiUrl": "https://api.fastmail.com/jmap/api/",
          "downloadUrl": "https://api.fastmail.com/jmap/download/{accountId}/{blobId}/{name}?accept={type}",
          "uploadUrl": "https://api.fastmail.com/jmap/upload/{accountId}/",
          "state": "sess-1"
        }
        """.utf8)

        let identityGetAttempts = RequestCounter()
        let transport = MockJMAPHTTPTransport { request in
            if request.url == Self.sessionURL {
                return JMAPHTTPResponse(statusCode: 200, body: mailOnlyAccountSessionJSON, finalURL: request.url)
            }
            let decoded = try JSONDecoder().decode(JMAPRequest.self, from: request.body ?? Data())
            if decoded.methodCalls.contains(where: { $0.name == "Identity/get" }) {
                await identityGetAttempts.increment()
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "error",
                                arguments: ["type": .string("accountNotSupportedByMethod")],
                                callID: "i0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            }
            if decoded.methodCalls.first?.name == "Mailbox/get" {
                return try Self.jsonResponse(
                    JMAPResponse(
                        methodResponses: [
                            JMAPInvocation(
                                name: "Mailbox/get",
                                arguments: [
                                    "accountId": .string("u-mail-only"),
                                    "state": .string("mb-1"),
                                    "list": .array([
                                        .object([
                                            "id": .string("mb-drafts"),
                                            "name": .string("Drafts"),
                                            "role": .string("drafts")
                                        ])
                                    ])
                                ],
                                callID: "m0"
                            )
                        ],
                        sessionState: "sess-1"
                    )
                )
            }
            return try Self.jsonResponse(
                JMAPResponse(
                    methodResponses: [
                        JMAPInvocation(
                            name: "Email/get",
                            arguments: [
                                "accountId": .string("u-mail-only"),
                                "state": .string("es-1"),
                                "list": .array([
                                    .object([
                                        "id": .string("e-mail-only-draft"),
                                        "mailboxIds": .object(["mb-drafts": .bool(true)]),
                                        "keywords": .object(["$draft": .bool(true)]),
                                        "from": .array([.object(["email": .string("mail-only@example.org")])]),
                                        "to": .array([.object(["email": .string("bob@example.org")])]),
                                        "subject": .string("Mail-only draft"),
                                        "textBody": .array([.object(["partId": .string("t1"), "type": .string("text/plain")])]),
                                        "bodyValues": .object(["t1": .object(["value": .string("Hello")])])
                                    ])
                                ])
                            ],
                            callID: "g0"
                        )
                    ],
                    sessionState: "sess-1"
                )
            )
        }

        let backend = JMAPBackend(
            account: Self.makeAccount(email: "mail-only@example.org"),
            sessionURL: Self.sessionURL,
            tokenProvider: StaticJMAPAccessTokenProvider(token: "tok-123"),
            transport: transport
        )
        try await backend.connect()
        let restored = try #require(try await backend.draft(for: "e-mail-only-draft"))
        #expect(restored.remoteID == "e-mail-only-draft")
        #expect(restored.identityID == nil)
        #expect(restored.subject == "Mail-only draft")
        #expect(await identityGetAttempts.count == 0)
    }
}

private actor RecordedStrings {
    private(set) var values: [String] = []
    func append(_ value: String) { values.append(value) }
}

private actor RecordedInts {
    private(set) var values: [Int] = []
    func append(_ value: Int) { values.append(value) }
}

private actor RemainingTrashBox {
    private(set) var remaining: [String]
    init(ids: [String]) { remaining = ids }
    func peek(limit: Int) -> [String] { Array(remaining.prefix(limit)) }
    func remove(_ ids: [String]) {
        let set = Set(ids)
        remaining.removeAll { set.contains($0) }
    }
}

private actor RecordedRequests {
    private(set) var requests: [JMAPRequest] = []
    func append(_ request: JMAPRequest) { requests.append(request) }
}

private actor RecordedURLs {
    private(set) var urls: [URL] = []
    func append(_ url: URL) { urls.append(url) }
}

private actor PhaseBox {
    private(set) var phase = 0
    func set(_ value: Int) { phase = value }
}

private actor FailureSwitch {
    private(set) var fail = false
    func set(_ value: Bool) { fail = value }
}
