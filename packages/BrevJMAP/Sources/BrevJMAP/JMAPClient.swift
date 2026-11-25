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
import Foundation

/// RFC 8620 / RFC 8621 batched JSON API client over an injectable `JMAPHTTPTransport`.
public struct JMAPClient: Sendable {
    /// Standard property list fetched for message list headers.
    public static let headerProperties: [String] = [
        "id",
        "blobId",
        "threadId",
        "mailboxIds",
        "keywords",
        "size",
        "receivedAt",
        "sentAt",
        "messageId",
        "inReplyTo",
        "references",
        "from",
        "to",
        "cc",
        "bcc",
        "replyTo",
        "subject",
        "hasAttachment",
        "preview"
    ]

    /// Standard property list fetched for full message bodies, attachments, and security/unsubscribe headers.
    public static let bodyProperties: [String] = [
        "id",
        "blobId",
        "threadId",
        "mailboxIds",
        "keywords",
        "size",
        "receivedAt",
        "sentAt",
        "from",
        "to",
        "cc",
        "bcc",
        "replyTo",
        "subject",
        "hasAttachment",
        "preview",
        "bodyStructure",
        "bodyValues",
        "textBody",
        "htmlBody",
        "attachments",
        "headers"
    ]

    private let transport: any JMAPHTTPTransport
    private let tokenProvider: any JMAPAccessTokenProvider

    /// Creates a JMAP API client backed by `transport` and `tokenProvider`.
    public init(
        transport: any JMAPHTTPTransport = URLSessionJMAPHTTPTransport.shared,
        tokenProvider: any JMAPAccessTokenProvider
    ) {
        self.transport = transport
        self.tokenProvider = tokenProvider
    }

    /// Executes an arbitrary batched `JMAPRequest` against `session.apiUrl`.
    public func execute(
        _ request: JMAPRequest,
        session: JMAPSession
    ) async throws -> JMAPResponse {
        let token = try await tokenProvider.bearerToken()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = try encoder.encode(request)
        let httpRequest = JMAPHTTPRequest(
            url: session.apiUrl,
            method: "POST",
            headers: [
                "Authorization": "Bearer \(token)",
                "Content-Type": "application/json",
                "Accept": "application/json"
            ],
            body: payload
        )
        let response = try await transport.send(httpRequest)
        try JMAPSessionClient.validateHTTPStatus(response)
        do {
            return try JSONDecoder().decode(JMAPResponse.self, from: response.body)
        } catch {
            throw JMAPError.invalidResponse
        }
    }

    // MARK: - Initial Bootstrap

    /// Fetches mailboxes and sending identities in a single batched JMAP round-trip.
    public func fetchInitialState(
        session: JMAPSession,
        accountId: String
    ) async throws -> (mailboxes: JMAPGetResponse<JMAPMailbox>, identities: JMAPGetResponse<JMAPIdentity>?) {
        var using = [JMAPCapability.core, JMAPCapability.mail]
        var calls: [JMAPInvocation] = [
            JMAPInvocation(
                name: "Mailbox/get",
                arguments: ["accountId": .string(accountId)],
                callID: "m0"
            )
        ]
        let fetchIdentities = session.supportsSubmission
        if fetchIdentities {
            using.append(JMAPCapability.submission)
            calls.append(
                JMAPInvocation(
                    name: "Identity/get",
                    arguments: ["accountId": .string(accountId)],
                    callID: "i0"
                )
            )
        }
        let response = try await execute(JMAPRequest(using: using, methodCalls: calls), session: session)
        let mailboxInvocation = try response.response(forCallID: "m0")
        let mailboxes = try mailboxInvocation.decodeArguments(JMAPGetResponse<JMAPMailbox>.self)

        var identities: JMAPGetResponse<JMAPIdentity>?
        if fetchIdentities {
            if let identityInvocation = try? response.response(forCallID: "i0") {
                identities = try? identityInvocation.decodeArguments(JMAPGetResponse<JMAPIdentity>.self)
            }
        }
        return (mailboxes, identities)
    }

    // MARK: - Mailboxes

    /// Fetches mailboxes (`Mailbox/get`).
    public func getMailboxes(
        session: JMAPSession,
        accountId: String,
        ids: [String]? = nil
    ) async throws -> JMAPGetResponse<JMAPMailbox> {
        var arguments: [String: JMAPJSONValue] = ["accountId": .string(accountId)]
        if let ids {
            arguments["ids"] = .array(ids.map { .string($0) })
        }
        let response = try await execute(
            JMAPRequest(
                using: [JMAPCapability.core, JMAPCapability.mail],
                methodCalls: [JMAPInvocation(name: "Mailbox/get", arguments: arguments, callID: "m0")]
            ),
            session: session
        )
        return try response.response(forCallID: "m0").decodeArguments(JMAPGetResponse<JMAPMailbox>.self)
    }

    /// Queries incremental mailbox changes (`Mailbox/changes`).
    public func mailboxChanges(
        session: JMAPSession,
        accountId: String,
        sinceState: String,
        maxChanges: Int? = nil
    ) async throws -> JMAPChangesResponse {
        var arguments: [String: JMAPJSONValue] = [
            "accountId": .string(accountId),
            "sinceState": .string(sinceState)
        ]
        if let maxChanges {
            arguments["maxChanges"] = .int(maxChanges)
        }
        let response = try await execute(
            JMAPRequest(
                using: [JMAPCapability.core, JMAPCapability.mail],
                methodCalls: [JMAPInvocation(name: "Mailbox/changes", arguments: arguments, callID: "mc0")]
            ),
            session: session
        )
        return try response.response(forCallID: "mc0").decodeArguments(JMAPChangesResponse.self)
    }

    /// Creates, updates, or destroys mailboxes (`Mailbox/set`).
    public func setMailboxes(
        session: JMAPSession,
        accountId: String,
        create: [String: [String: JMAPJSONValue]]? = nil,
        update: [String: [String: JMAPJSONValue]]? = nil,
        destroy: [String]? = nil
    ) async throws -> JMAPSetResponse {
        var arguments: [String: JMAPJSONValue] = ["accountId": .string(accountId)]
        if let create {
            arguments["create"] = .object(create.mapValues { .object($0) })
        }
        if let update {
            arguments["update"] = .object(update.mapValues { .object($0) })
        }
        if let destroy {
            arguments["destroy"] = .array(destroy.map { .string($0) })
        }
        let response = try await execute(
            JMAPRequest(
                using: [JMAPCapability.core, JMAPCapability.mail],
                methodCalls: [JMAPInvocation(name: "Mailbox/set", arguments: arguments, callID: "ms0")]
            ),
            session: session
        )
        let result = try response.response(forCallID: "ms0").decodeArguments(JMAPSetResponse.self)
        try validateSetResponse(result)
        return result
    }

    // MARK: - Emails

    /// Executes a single-round-trip batched `Email/query` + `Email/get` using `#ids` (`JMAPResultReference`).
    public func queryAndGetEmails(
        session: JMAPSession,
        accountId: String,
        filter: [String: JMAPJSONValue]? = nil,
        sort: [[String: JMAPJSONValue]] = [
            ["property": .string("receivedAt"), "isAscending": .bool(false)]
        ],
        position: Int = 0,
        limit: Int = 50,
        properties: [String] = JMAPClient.headerProperties
    ) async throws -> (query: JMAPQueryResponse, get: JMAPGetResponse<JMAPEmail>) {
        var queryArgs: [String: JMAPJSONValue] = [
            "accountId": .string(accountId),
            "sort": .array(sort.map { .object($0) }),
            "position": .int(max(0, position)),
            "limit": .int(max(1, limit)),
            "calculateTotal": .bool(true)
        ]
        if let filter, !filter.isEmpty {
            queryArgs["filter"] = .object(filter)
        }
        let idsRef = JMAPResultReference(resultOf: "q0", name: "Email/query", path: "/ids")
        let getArgs: [String: JMAPJSONValue] = [
            "accountId": .string(accountId),
            "#ids": idsRef.jsonValue,
            "properties": .array(properties.map { .string($0) })
        ]
        let response = try await execute(
            JMAPRequest(
                using: [JMAPCapability.core, JMAPCapability.mail],
                methodCalls: [
                    JMAPInvocation(name: "Email/query", arguments: queryArgs, callID: "q0"),
                    JMAPInvocation(name: "Email/get", arguments: getArgs, callID: "g0")
                ]
            ),
            session: session
        )
        let query = try response.response(forCallID: "q0").decodeArguments(JMAPQueryResponse.self)
        let get = try response.response(forCallID: "g0").decodeArguments(JMAPGetResponse<JMAPEmail>.self)
        return (query, get)
    }

    /// Queries email identifiers only (`Email/query`).
    public func queryEmailIDs(
        session: JMAPSession,
        accountId: String,
        filter: [String: JMAPJSONValue]? = nil,
        position: Int = 0,
        limit: Int = 500
    ) async throws -> JMAPQueryResponse {
        var queryArgs: [String: JMAPJSONValue] = [
            "accountId": .string(accountId),
            "position": .int(max(0, position)),
            "limit": .int(max(1, limit))
        ]
        if let filter, !filter.isEmpty {
            queryArgs["filter"] = .object(filter)
        }
        let response = try await execute(
            JMAPRequest(
                using: [JMAPCapability.core, JMAPCapability.mail],
                methodCalls: [JMAPInvocation(name: "Email/query", arguments: queryArgs, callID: "q0")]
            ),
            session: session
        )
        return try response.response(forCallID: "q0").decodeArguments(JMAPQueryResponse.self)
    }

    /// Fetches full or partial `Email` objects (`Email/get`).
    public func getEmails(
        session: JMAPSession,
        accountId: String,
        ids: [String],
        properties: [String] = JMAPClient.bodyProperties,
        fetchTextBodyValues: Bool = false,
        fetchHTMLBodyValues: Bool = false,
        maxBodyValueBytes: Int? = nil
    ) async throws -> JMAPGetResponse<JMAPEmail> {
        var arguments: [String: JMAPJSONValue] = [
            "accountId": .string(accountId),
            "ids": .array(ids.map { .string($0) }),
            "properties": .array(properties.map { .string($0) })
        ]
        if fetchTextBodyValues {
            arguments["fetchTextBodyValues"] = .bool(true)
        }
        if fetchHTMLBodyValues {
            arguments["fetchHTMLBodyValues"] = .bool(true)
        }
        if let maxBodyValueBytes {
            arguments["maxBodyValueBytes"] = .int(maxBodyValueBytes)
        }
        let response = try await execute(
            JMAPRequest(
                using: [JMAPCapability.core, JMAPCapability.mail],
                methodCalls: [JMAPInvocation(name: "Email/get", arguments: arguments, callID: "g0")]
            ),
            session: session
        )
        return try response.response(forCallID: "g0").decodeArguments(JMAPGetResponse<JMAPEmail>.self)
    }

    /// Queries incremental email state changes (`Email/changes`).
    public func emailChanges(
        session: JMAPSession,
        accountId: String,
        sinceState: String,
        maxChanges: Int? = nil
    ) async throws -> JMAPChangesResponse {
        var arguments: [String: JMAPJSONValue] = [
            "accountId": .string(accountId),
            "sinceState": .string(sinceState)
        ]
        if let maxChanges {
            arguments["maxChanges"] = .int(maxChanges)
        }
        let response = try await execute(
            JMAPRequest(
                using: [JMAPCapability.core, JMAPCapability.mail],
                methodCalls: [JMAPInvocation(name: "Email/changes", arguments: arguments, callID: "ec0")]
            ),
            session: session
        )
        return try response.response(forCallID: "ec0").decodeArguments(JMAPChangesResponse.self)
    }

    /// Creates, updates, or destroys emails (`Email/set`).
    public func setEmails(
        session: JMAPSession,
        accountId: String,
        create: [String: [String: JMAPJSONValue]]? = nil,
        update: [String: [String: JMAPJSONValue]]? = nil,
        destroy: [String]? = nil
    ) async throws -> JMAPSetResponse {
        var arguments: [String: JMAPJSONValue] = ["accountId": .string(accountId)]
        if let create, !create.isEmpty {
            arguments["create"] = .object(create.mapValues { .object($0) })
        }
        if let update, !update.isEmpty {
            arguments["update"] = .object(update.mapValues { .object($0) })
        }
        if let destroy, !destroy.isEmpty {
            arguments["destroy"] = .array(destroy.map { .string($0) })
        }
        let response = try await execute(
            JMAPRequest(
                using: [JMAPCapability.core, JMAPCapability.mail],
                methodCalls: [JMAPInvocation(name: "Email/set", arguments: arguments, callID: "es0")]
            ),
            session: session
        )
        let result = try response.response(forCallID: "es0").decodeArguments(JMAPSetResponse.self)
        try validateSetResponse(result)
        return result
    }

    /// Fetches sending identities (`Identity/get`).
    public func getIdentities(
        session: JMAPSession,
        accountId: String
    ) async throws -> JMAPGetResponse<JMAPIdentity> {
        let response = try await execute(
            JMAPRequest(
                using: [JMAPCapability.core, JMAPCapability.submission],
                methodCalls: [
                    JMAPInvocation(
                        name: "Identity/get",
                        arguments: ["accountId": .string(accountId)],
                        callID: "i0"
                    )
                ]
            ),
            session: session
        )
        return try response.response(forCallID: "i0").decodeArguments(JMAPGetResponse<JMAPIdentity>.self)
    }

    /// Creates an outbound email and submits it atomically in a single batched `Email/set` + `EmailSubmission/set` request.
    public func createAndSubmitEmail(
        session: JMAPSession,
        accountId: String,
        creationID: String = "draft",
        emailObject: [String: JMAPJSONValue],
        destroyPreviousDraftID: String? = nil,
        identityId: String,
        mailFrom: String,
        rcptTo: [String],
        onSuccessUpdateEmail: [String: JMAPJSONValue]
    ) async throws -> (emailSet: JMAPSetResponse, submissionSet: JMAPSetResponse) {
        var emailSetArgs: [String: JMAPJSONValue] = [
            "accountId": .string(accountId),
            "create": .object([creationID: .object(emailObject)])
        ]
        if let destroyPreviousDraftID, !destroyPreviousDraftID.isEmpty {
            emailSetArgs["destroy"] = .array([.string(destroyPreviousDraftID)])
        }

        let submissionObject: [String: JMAPJSONValue] = [
            "identityId": .string(identityId),
            "emailId": .string("#\(creationID)"),
            "envelope": .object([
                "mailFrom": .object(["email": .string(mailFrom)]),
                "rcptTo": .array(rcptTo.map { .object(["email": .string($0)]) })
            ])
        ]
        let submissionArgs: [String: JMAPJSONValue] = [
            "accountId": .string(accountId),
            "create": .object(["send": .object(submissionObject)]),
            "onSuccessUpdateEmail": .object([
                "#send": .object(onSuccessUpdateEmail)
            ])
        ]

        let response = try await execute(
            JMAPRequest(
                using: [JMAPCapability.core, JMAPCapability.mail, JMAPCapability.submission],
                methodCalls: [
                    JMAPInvocation(name: "Email/set", arguments: emailSetArgs, callID: "es0"),
                    JMAPInvocation(name: "EmailSubmission/set", arguments: submissionArgs, callID: "sub0")
                ]
            ),
            session: session
        )
        let emailSet = try response.response(forCallID: "es0").decodeArguments(JMAPSetResponse.self)
        try validateSetResponse(emailSet)
        let submissionSet = try response.response(forCallID: "sub0").decodeArguments(JMAPSetResponse.self)
        try validateSetResponse(submissionSet)
        return (emailSet, submissionSet)
    }

    // MARK: - Blobs (Upload & Download)

    /// Uploads binary attachment bytes to the session's `uploadUrl` (RFC 8620 §6.1).
    public func uploadBlob(
        session: JMAPSession,
        accountId: String,
        data: Data,
        mimeType: String
    ) async throws -> JMAPBlobUploadResponse {
        if let maxSize = session.maxSizeUpload, data.count > maxSize {
            throw JMAPError.uploadTooLarge(limit: maxSize)
        }
        let uploadURL: URL
        do {
            uploadURL = try JMAPURLValidator.expandURITemplate(
                session.uploadUrl,
                parameters: ["accountId": accountId]
            )
        } catch {
            throw JMAPError.invalidUploadURL
        }
        let token = try await tokenProvider.bearerToken()
        let request = JMAPHTTPRequest(
            url: uploadURL,
            method: "POST",
            headers: [
                "Authorization": "Bearer \(token)",
                "Content-Type": mimeType,
                "Accept": "application/json"
            ],
            body: data
        )
        let response = try await transport.send(request)
        try JMAPSessionClient.validateHTTPStatus(response)
        do {
            return try JSONDecoder().decode(JMAPBlobUploadResponse.self, from: response.body)
        } catch {
            throw JMAPError.invalidResponse
        }
    }

    /// Downloads raw message or attachment bytes using RFC 8620 §6.2 `downloadUrl` template expansion.
    public func downloadBlob(
        session: JMAPSession,
        accountId: String,
        blobId: String,
        name: String,
        mimeType: String
    ) async throws -> Data {
        let downloadURL: URL
        do {
            downloadURL = try JMAPURLValidator.expandURITemplate(
                session.downloadUrl,
                parameters: [
                    "accountId": accountId,
                    "blobId": blobId,
                    "name": name,
                    "type": mimeType
                ]
            )
        } catch {
            throw JMAPError.invalidDownloadURL
        }
        let token = try await tokenProvider.bearerToken()
        let request = JMAPHTTPRequest(
            url: downloadURL,
            method: "GET",
            headers: [
                "Authorization": "Bearer \(token)",
                "Accept": "*/*"
            ]
        )
        let response = try await transport.send(request)
        try JMAPSessionClient.validateHTTPStatus(response)
        return response.body
    }

    // MARK: - WebPush & EventSource

    /// Submits a pre-encoded RFC 8620 §7.2 `PushSubscription/set` JSON body (from `JMAPWebPushSubscriptionSpec`).
    public func sendPushSubscriptionRequest(
        session: JMAPSession,
        requestData: Data
    ) async throws -> JMAPResponse {
        let token = try await tokenProvider.bearerToken()
        let request = JMAPHTTPRequest(
            url: session.apiUrl,
            method: "POST",
            headers: [
                "Authorization": "Bearer \(token)",
                "Content-Type": "application/json",
                "Accept": "application/json"
            ],
            body: requestData
        )
        let response = try await transport.send(request)
        try JMAPSessionClient.validateHTTPStatus(response)
        do {
            return try JSONDecoder().decode(JMAPResponse.self, from: response.body)
        } catch {
            throw JMAPError.invalidResponse
        }
    }

    /// Opens an RFC 8620 §7.3 `EventSource` SSE stream for live `StateChange` notifications.
    public func openEventSource(
        session: JMAPSession,
        types: String = "Email,Mailbox",
        closeAfter: String = "no",
        ping: Int = 30
    ) async throws -> AsyncThrowingStream<JMAPEventSourceEvent, Error> {
        guard let template = session.eventSourceUrl, !template.isEmpty else {
            throw JMAPError.invalidResponse
        }
        let eventURL = try JMAPURLValidator.expandURITemplate(
            template,
            parameters: [
                "types": types,
                "closeafter": closeAfter,
                "ping": String(ping)
            ]
        )
        let token = try await tokenProvider.bearerToken()
        let request = JMAPHTTPRequest(
            url: eventURL,
            method: "GET",
            headers: [
                "Authorization": "Bearer \(token)",
                "Accept": "text/event-stream",
                "Cache-Control": "no-cache"
            ]
        )
        return transport.streamEvents(request)
    }

    // MARK: - Helpers

    private func validateSetResponse(_ response: JMAPSetResponse) throws {
        if let failure = response.notCreated?.values.first {
            throw JMAPError.methodError(type: failure.type, description: failure.description)
        }
        if let failure = response.notUpdated?.values.first {
            if failure.type == "notFound" {
                throw JMAPError.notFound(id: response.notUpdated?.keys.first ?? "")
            }
            throw JMAPError.methodError(type: failure.type, description: failure.description)
        }
        if let failure = response.notDestroyed?.values.first {
            if failure.type == "notFound" {
                throw JMAPError.notFound(id: response.notDestroyed?.keys.first ?? "")
            }
            throw JMAPError.methodError(type: failure.type, description: failure.description)
        }
    }
}
