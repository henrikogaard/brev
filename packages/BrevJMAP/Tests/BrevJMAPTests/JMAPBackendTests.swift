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

        // Sending reuses uploaded blob without re-uploading, destroys old draft, and submits atomically.
        let sendResult = try await backend.send(draft: saved)
        #expect(sendResult.sentMessageID == "e-sent-1")
        #expect(await uploadedBlobs.count == 1)

        let lastRequest = try #require(await recordedRequests.requests.last)
        #expect(lastRequest.using.contains(JMAPCapability.submission))
        #expect(lastRequest.methodCalls.count == 2)
        #expect(lastRequest.methodCalls[0].name == "Email/set")
        #expect(lastRequest.methodCalls[0].arguments["destroy"] == .array([.string("e-draft-1")]))
        #expect(lastRequest.methodCalls[1].name == "EmailSubmission/set")
        let onSuccess = lastRequest.methodCalls[1].arguments["onSuccessUpdateEmail"]?.objectValue?["#send"]?.objectValue
        #expect(onSuccess?["keywords/$draft"] == .null)
        #expect(onSuccess?["mailboxIds/mb-sent"] == .bool(true))
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
        #expect(await tokenStore.token(for: accountID)?.accessToken == secretToken)

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
        #expect(await tokenStore.token(for: accountID) == nil)
        #expect(await configStore.configuration(for: accountID) == nil)
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
