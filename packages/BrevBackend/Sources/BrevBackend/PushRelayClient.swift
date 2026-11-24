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

import Foundation

/// Injectable HTTP transport seam for `PushRelayClient` so unit tests remain deterministic.
public protocol PushRelayHTTPTransport: Sendable {
    /// Executes one HTTP request and returns response bytes plus status metadata.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Blocks HTTP redirects so relay registration payloads and Bearer headers
/// can never be forwarded to an unapproved cross-origin host.
final class NoRedirectPushRelaySessionDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// Default `URLSession`-backed transport using an ephemeral configuration
/// (no persistent cookies or disk cache) and strict redirect blocking.
///
/// Uses a shared long-lived default instance (`URLSessionPushRelayTransport.shared`)
/// so constructing Settings views never leaks delegate-backed `URLSession` objects.
/// Custom configuration-owned sessions are invalidated cleanly in `deinit`; caller-supplied
/// `URLSession` instances are never invalidated.
public final class URLSessionPushRelayTransport: PushRelayHTTPTransport, @unchecked Sendable {
    /// Shared long-lived ephemeral, redirect-blocking transport used by default.
    public static let shared = URLSessionPushRelayTransport()

    private let session: URLSession
    private let redirectDelegate: NoRedirectPushRelaySessionDelegate?
    private let ownsSession: Bool

    /// Creates a transport backed by `session` (or a new ephemeral, no-redirect session for `configuration`).
    public init(session: URLSession? = nil, configuration: URLSessionConfiguration? = nil) {
        if let session {
            self.session = session
            redirectDelegate = nil
            ownsSession = false
        } else {
            let config = configuration ?? {
                let ephemeral = URLSessionConfiguration.ephemeral
                ephemeral.timeoutIntervalForRequest = 15
                ephemeral.timeoutIntervalForResource = 30
                ephemeral.httpCookieAcceptPolicy = .never
                ephemeral.httpShouldSetCookies = false
                return ephemeral
            }()
            let delegate = NoRedirectPushRelaySessionDelegate()
            redirectDelegate = delegate
            self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            ownsSession = true
        }
    }

    deinit {
        if ownsSession {
            session.finishTasksAndInvalidate()
        }
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PushRelayClientError.invalidResponse
        }
        return (data, httpResponse)
    }
}

/// Errors produced while registering, refreshing, verifying, or unregistering a closed-app push subscription.
public enum PushRelayClientError: Error, LocalizedError, Equatable, Sendable {
    case disabled
    case invalidEndpoint(PushRelayEndpointValidationError)
    case missingOptedInAccounts
    case missingDevicePushToken
    case missingWebPushDeliveryURL
    case webPushDeliveryURLMatchesAPIEndpoint
    case invalidDeviceClientID
    case missingVerificationCode
    case redirectBlocked(statusCode: Int)
    case httpFailure(statusCode: Int)
    case jmapMethodRejected(String)
    case invalidResponse
    case transportFailure(String)

    public var errorDescription: String? {
        switch self {
        case .disabled:
            String(localized: "Closed-app push is turned off.", bundle: .module)
        case .invalidEndpoint(let validationError):
            validationError.errorDescription
        case .missingOptedInAccounts:
            String(localized: "Choose at least one account before registering with your push relay.", bundle: .module)
        case .missingDevicePushToken:
            String(localized: "No device push token is available for registration.", bundle: .module)
        case .missingWebPushDeliveryURL:
            String(localized: "Enter a separate HTTPS WebPush delivery URL for JMAP push.", bundle: .module)
        case .webPushDeliveryURLMatchesAPIEndpoint:
            String(localized: "The WebPush delivery URL must be distinct from the JMAP API endpoint URL.", bundle: .module)
        case .invalidDeviceClientID:
            String(localized: "Device client identifier is missing.", bundle: .module)
        case .missingVerificationCode:
            String(localized: "Enter the verification code sent to your WebPush delivery URL.", bundle: .module)
        case .redirectBlocked(let statusCode):
            String(localized: "Push relay blocked an HTTP \(statusCode) redirect for security.", bundle: .module)
        case .httpFailure(let statusCode):
            String(localized: "Push relay returned HTTP status \(statusCode).", bundle: .module)
        case .jmapMethodRejected(let reason):
            String(localized: "JMAP server rejected the push subscription request: \(reason)", bundle: .module)
        case .invalidResponse:
            String(localized: "Push relay returned an invalid response.", bundle: .module)
        case .transportFailure(let detail):
            String(localized: "Push relay request failed: \(detail)", bundle: .module)
        }
    }
}

/// Registers, refreshes, verifies, and unregisters device push subscriptions against a
/// user-configured HTTPS push relay or JMAP WebPush server (#11).
///
/// Brev never hardcodes or contacts a Brev-hosted proxy. Every request targets
/// only the user-supplied HTTPS URL after strict validation, and redirects are blocked.
public actor PushRelayClient {
    private static let subscriptionIDHeader = "X-Brev-Subscription-ID"
    private static let jmapClientCreationID = "brev-push-sub"

    private let transport: any PushRelayHTTPTransport

    /// Creates a push relay client with the supplied HTTP transport.
    public init(transport: any PushRelayHTTPTransport = URLSessionPushRelayTransport.shared) {
        self.transport = transport
    }

    /// Registers a device push subscription with the user-configured HTTPS endpoint.
    ///
    /// For `.jmapWebPush`, newly created subscriptions return `.pendingVerification`
    /// per RFC 8620 §7.2.2 until `verifyJMAPSubscription` succeeds.
    public func register(
        endpointURLString: String,
        request: PushRelayRegistrationRequest,
        bearerToken: String?
    ) async throws -> PushRelayRegistrationResponse {
        try validateRegistrationRequest(request)
        let endpointURL = try validatedEndpoint(endpointURLString)

        let urlRequest: URLRequest
        switch request.mode {
        case .disabled:
            throw PushRelayClientError.disabled
        case .userHostedRelay:
            urlRequest = try makeRelayJSONRequest(
                url: endpointURL,
                method: "POST",
                body: request,
                subscriptionID: nil,
                bearerToken: bearerToken
            )
        case .jmapWebPush:
            urlRequest = try makeJMAPCreateRequest(
                endpointURL: endpointURL,
                request: request,
                bearerToken: bearerToken
            )
        }

        let (data, response) = try await perform(urlRequest)
        try ensureNonRedirectSuccess(response)
        return try decodeRegistrationResponse(data: data, mode: request.mode)
    }

    /// Refreshes an existing device push subscription against the same user-configured HTTPS endpoint.
    ///
    /// For `.jmapWebPush`, sends a `PushSubscription/set` `update` targeting `subscriptionID`
    /// so an already verified subscription preserves its `currentState` (`.active`). Falls back
    /// to creating a fresh `.pendingVerification` subscription only if the server reports `notFound`
    /// for `subscriptionID` (or if `subscriptionID` is empty).
    public func refresh(
        endpointURLString: String,
        subscriptionID: String,
        request: PushRelayRegistrationRequest,
        currentState: PushRelaySubscriptionState = .active,
        bearerToken: String?
    ) async throws -> PushRelayRegistrationResponse {
        try validateRegistrationRequest(request)
        let endpointURL = try validatedEndpoint(endpointURLString)
        let trimmedSubID = subscriptionID.trimmingCharacters(in: .whitespacesAndNewlines)

        switch request.mode {
        case .disabled:
            throw PushRelayClientError.disabled
        case .userHostedRelay:
            let urlRequest = try makeRelayJSONRequest(
                url: endpointURL,
                method: "PUT",
                body: request,
                subscriptionID: trimmedSubID.isEmpty ? nil : trimmedSubID,
                bearerToken: bearerToken
            )
            let (data, response) = try await perform(urlRequest)
            try ensureNonRedirectSuccess(response)
            return try decodeRegistrationResponse(data: data, mode: request.mode)
        case .jmapWebPush:
            guard !trimmedSubID.isEmpty else {
                let createRequest = try makeJMAPCreateRequest(
                    endpointURL: endpointURL,
                    request: request,
                    bearerToken: bearerToken
                )
                let (data, response) = try await perform(createRequest)
                try ensureNonRedirectSuccess(response)
                return try parseJMAPCreateResponse(data: data)
            }
            // Validate delivery URL before contacting server even on update.
            guard let deliveryURLString = request.webPushDeliveryURL, !deliveryURLString.isEmpty else {
                throw PushRelayClientError.missingWebPushDeliveryURL
            }
            let deliveryURL = try validatedEndpoint(deliveryURLString)
            guard !PushRelayEndpointValidator.representsSameDestination(endpointURL, deliveryURL) else {
                throw PushRelayClientError.webPushDeliveryURLMatchesAPIEndpoint
            }

            var updateRequest = URLRequest(url: endpointURL)
            updateRequest.httpMethod = "POST"
            updateRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            updateRequest.setValue("application/json", forHTTPHeaderField: "Accept")
            applyBearerHeader(bearerToken, to: &updateRequest)
            updateRequest.httpBody = try JMAPWebPushSubscriptionSpec.encodedSetUpdateRequestData(
                subscriptionID: trimmedSubID
            )
            let (data, response) = try await perform(updateRequest)
            try ensureNonRedirectSuccess(response)

            switch try parseJMAPUpdateResult(data: data, subscriptionID: trimmedSubID) {
            case .updated(let expiresAt):
                return PushRelayRegistrationResponse(
                    subscriptionID: trimmedSubID,
                    expiresAt: expiresAt,
                    verificationCode: nil,
                    state: currentState
                )
            case .notFound:
                let createRequest = try makeJMAPCreateRequest(
                    endpointURL: endpointURL,
                    request: request,
                    bearerToken: bearerToken
                )
                let (createData, createResponse) = try await perform(createRequest)
                try ensureNonRedirectSuccess(createResponse)
                return try parseJMAPCreateResponse(data: createData)
            }
        }
    }

    /// Completes RFC 8620 §7.2.2 JMAP `PushSubscription` verification by sending a
    /// `PushSubscription/set` `update` with the `verificationCode` delivered to the WebPush URL.
    public func verifyJMAPSubscription(
        endpointURLString: String,
        subscriptionID: String,
        verificationCode: String,
        bearerToken: String?
    ) async throws -> PushRelayRegistrationResponse {
        let endpointURL = try validatedEndpoint(endpointURLString)
        let trimmedSubID = subscriptionID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCode = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSubID.isEmpty else {
            throw PushRelayClientError.invalidResponse
        }
        guard !trimmedCode.isEmpty else {
            throw PushRelayClientError.missingVerificationCode
        }

        var req = URLRequest(url: endpointURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        applyBearerHeader(bearerToken, to: &req)
        req.httpBody = try JMAPWebPushSubscriptionSpec.encodedSetVerifyRequestData(
            subscriptionID: trimmedSubID,
            verificationCode: trimmedCode
        )

        let (data, response) = try await perform(req)
        try ensureNonRedirectSuccess(response)
        try parseJMAPVerifyResponse(data: data, subscriptionID: trimmedSubID)
        return PushRelayRegistrationResponse(
            subscriptionID: trimmedSubID,
            expiresAt: nil,
            verificationCode: nil,
            state: .active
        )
    }

    /// Unregisters a device push subscription cleanly.
    ///
    /// - For `.userHostedRelay`: HTTP 2xx and 404 both succeed; 3xx redirects are blocked.
    /// - For `.jmapWebPush`: parses the RFC 8620 `PushSubscription/set` response envelope
    ///   and succeeds only when `subscriptionID` is in `destroyed` or `notDestroyed[id].type == "notFound"`.
    public func unregister(
        endpointURLString: String,
        request: PushRelayUnregistrationRequest,
        mode: PushRelayMode = .userHostedRelay,
        bearerToken: String?
    ) async throws {
        let endpointURL = try validatedEndpoint(endpointURLString)
        guard !request.deviceClientID.isEmpty else {
            throw PushRelayClientError.invalidDeviceClientID
        }

        switch mode {
        case .jmapWebPush:
            guard let subID = request.subscriptionID, !subID.isEmpty else {
                return
            }
            var req = URLRequest(url: endpointURL)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            applyBearerHeader(bearerToken, to: &req)
            req.httpBody = try JMAPWebPushSubscriptionSpec.encodedSetDestroyRequestData(
                subscriptionID: subID
            )
            let (data, response) = try await perform(req)
            try ensureNonRedirectSuccess(response)
            try parseJMAPDestroyResponse(data: data, subscriptionID: subID)

        case .userHostedRelay, .disabled:
            let urlRequest = try makeRelayJSONRequest(
                url: endpointURL,
                method: "DELETE",
                body: request,
                subscriptionID: request.subscriptionID,
                bearerToken: bearerToken
            )
            let (_, response) = try await perform(urlRequest)
            if (300 ... 399).contains(response.statusCode) {
                throw PushRelayClientError.redirectBlocked(statusCode: response.statusCode)
            }
            guard (200 ... 299).contains(response.statusCode) || response.statusCode == 404 else {
                throw PushRelayClientError.httpFailure(statusCode: response.statusCode)
            }
        }
    }

    // MARK: - Private helpers

    private func validateRegistrationRequest(_ request: PushRelayRegistrationRequest) throws {
        guard request.mode != .disabled else {
            throw PushRelayClientError.disabled
        }
        guard !request.deviceClientID.isEmpty else {
            throw PushRelayClientError.invalidDeviceClientID
        }
        guard !request.accountIDs.isEmpty else {
            throw PushRelayClientError.missingOptedInAccounts
        }
        switch request.mode {
        case .userHostedRelay:
            guard !request.devicePushToken.isEmpty,
                  request.devicePushToken != request.deviceClientID
            else {
                throw PushRelayClientError.missingDevicePushToken
            }
        case .jmapWebPush:
            guard let deliveryURL = request.webPushDeliveryURL, !deliveryURL.isEmpty else {
                throw PushRelayClientError.missingWebPushDeliveryURL
            }
        case .disabled:
            throw PushRelayClientError.disabled
        }
    }

    private func validatedEndpoint(_ raw: String) throws -> URL {
        do {
            return try PushRelayEndpointValidator.validate(raw)
        } catch let error as PushRelayEndpointValidationError {
            throw PushRelayClientError.invalidEndpoint(error)
        }
    }

    private func ensureNonRedirectSuccess(_ response: HTTPURLResponse) throws {
        if (300 ... 399).contains(response.statusCode) {
            throw PushRelayClientError.redirectBlocked(statusCode: response.statusCode)
        }
        guard (200 ... 299).contains(response.statusCode) else {
            throw PushRelayClientError.httpFailure(statusCode: response.statusCode)
        }
    }

    private func makeRelayJSONRequest<Body: Encodable>(
        url: URL,
        method: String,
        body: Body,
        subscriptionID: String?,
        bearerToken: String?
    ) throws -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let subscriptionID, !subscriptionID.isEmpty {
            req.setValue(subscriptionID, forHTTPHeaderField: Self.subscriptionIDHeader)
        }
        applyBearerHeader(bearerToken, to: &req)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        req.httpBody = try encoder.encode(body)
        return req
    }

    private func makeJMAPCreateRequest(
        endpointURL: URL,
        request: PushRelayRegistrationRequest,
        bearerToken: String?
    ) throws -> URLRequest {
        guard let deliveryURLString = request.webPushDeliveryURL, !deliveryURLString.isEmpty else {
            throw PushRelayClientError.missingWebPushDeliveryURL
        }
        let deliveryURL = try validatedEndpoint(deliveryURLString)
        guard !PushRelayEndpointValidator.representsSameDestination(endpointURL, deliveryURL) else {
            throw PushRelayClientError.webPushDeliveryURLMatchesAPIEndpoint
        }
        let spec: JMAPWebPushSubscriptionSpec
        do {
            spec = try JMAPWebPushSubscriptionSpec(
                deviceClientID: request.deviceClientID,
                urlString: deliveryURL.absoluteString,
                keys: request.keys,
                types: ["Email"]
            )
        } catch let error as PushRelayEndpointValidationError {
            throw PushRelayClientError.invalidEndpoint(error)
        }

        var req = URLRequest(url: endpointURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        applyBearerHeader(bearerToken, to: &req)
        req.httpBody = try spec.encodedSetCreateRequestData(
            clientCreationID: Self.jmapClientCreationID
        )
        return req
    }

    private func applyBearerHeader(_ bearerToken: String?, to request: inout URLRequest) {
        let trimmed = bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
        }
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request)
        } catch let error as PushRelayClientError {
            throw error
        } catch {
            throw PushRelayClientError.transportFailure(error.localizedDescription)
        }
    }

    private func decodeRegistrationResponse(
        data: Data,
        mode: PushRelayMode
    ) throws -> PushRelayRegistrationResponse {
        switch mode {
        case .jmapWebPush:
            return try parseJMAPCreateResponse(data: data)
        case .userHostedRelay, .disabled:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let direct = try? decoder.decode(PushRelayRegistrationResponse.self, from: data),
               !direct.subscriptionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return direct
            }
            throw PushRelayClientError.invalidResponse
        }
    }

    private func jmapSetResponseArguments(from data: Data) -> [String: Any]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let methodResponses = root["methodResponses"] as? [[Any]]
        else {
            return nil
        }
        for entry in methodResponses {
            guard entry.count >= 2,
                  let methodName = entry[0] as? String,
                  methodName == "PushSubscription/set",
                  let args = entry[1] as? [String: Any]
            else {
                continue
            }
            return args
        }
        return nil
    }

    private func parseJMAPCreateResponse(data: Data) throws -> PushRelayRegistrationResponse {
        guard let args = jmapSetResponseArguments(from: data) else {
            throw PushRelayClientError.invalidResponse
        }
        if let notCreated = args["notCreated"] as? [String: [String: Any]],
           let failure = notCreated[Self.jmapClientCreationID] ?? notCreated.values.first {
            let reason = (failure["description"] as? String)
                ?? (failure["type"] as? String)
                ?? "notCreated"
            throw PushRelayClientError.jmapMethodRejected(reason)
        }
        guard let created = args["created"] as? [String: [String: Any]] else {
            throw PushRelayClientError.invalidResponse
        }
        let createdRecord = created[Self.jmapClientCreationID] ?? created.values.first
        guard let record = createdRecord,
              let subscriptionID = record["id"] as? String,
              !subscriptionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw PushRelayClientError.invalidResponse
        }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let expiresAt: Date? = (record["expires"] as? String).flatMap { isoFormatter.date(from: $0) }
        let verificationCode = record["verificationCode"] as? String
        // RFC 8620 §7.2.2: newly created JMAP PushSubscriptions stay unverified until
        // the server's PushVerification challenge code is returned via PushSubscription/set update.
        return PushRelayRegistrationResponse(
            subscriptionID: subscriptionID,
            expiresAt: expiresAt,
            verificationCode: verificationCode,
            state: .pendingVerification
        )
    }

    private enum JMAPUpdateParseResult {
        case updated(expiresAt: Date?)
        case notFound
    }

    private func parseJMAPUpdateResult(data: Data, subscriptionID: String) throws -> JMAPUpdateParseResult {
        guard let args = jmapSetResponseArguments(from: data) else {
            throw PushRelayClientError.invalidResponse
        }
        if let notUpdated = args["notUpdated"] as? [String: [String: Any]],
           let failure = notUpdated[subscriptionID] {
            let errorType = failure["type"] as? String
            if errorType == "notFound" {
                return .notFound
            }
            let reason = (failure["description"] as? String) ?? errorType ?? "notUpdated"
            throw PushRelayClientError.jmapMethodRejected(reason)
        }
        guard let updated = args["updated"] as? [String: Any],
              updated.keys.contains(subscriptionID)
        else {
            throw PushRelayClientError.invalidResponse
        }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let record = updated[subscriptionID] as? [String: Any]
        let expiresAt: Date? = (record?["expires"] as? String).flatMap { isoFormatter.date(from: $0) }
        return .updated(expiresAt: expiresAt)
    }

    private func parseJMAPVerifyResponse(data: Data, subscriptionID: String) throws {
        guard let args = jmapSetResponseArguments(from: data) else {
            throw PushRelayClientError.invalidResponse
        }
        if let notUpdated = args["notUpdated"] as? [String: [String: Any]],
           let failure = notUpdated[subscriptionID] {
            let reason = (failure["description"] as? String)
                ?? (failure["type"] as? String)
                ?? "notUpdated"
            throw PushRelayClientError.jmapMethodRejected(reason)
        }
        guard let updated = args["updated"] as? [String: Any],
              updated.keys.contains(subscriptionID)
        else {
            throw PushRelayClientError.invalidResponse
        }
    }

    private func parseJMAPDestroyResponse(data: Data, subscriptionID: String) throws {
        guard let args = jmapSetResponseArguments(from: data) else {
            throw PushRelayClientError.invalidResponse
        }
        if let destroyed = args["destroyed"] as? [String],
           destroyed.contains(subscriptionID) {
            return
        }
        if let notDestroyed = args["notDestroyed"] as? [String: [String: Any]],
           let failure = notDestroyed[subscriptionID] {
            let errorType = failure["type"] as? String
            if errorType == "notFound" {
                return
            }
            let reason = (failure["description"] as? String) ?? errorType ?? "notDestroyed"
            throw PushRelayClientError.jmapMethodRejected(reason)
        }
        throw PushRelayClientError.invalidResponse
    }
}
