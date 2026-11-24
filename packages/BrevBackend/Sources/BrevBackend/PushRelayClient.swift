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

/// Default `URLSession`-backed transport using an ephemeral configuration (no persistent cookies or disk cache).
public struct URLSessionPushRelayTransport: PushRelayHTTPTransport {
    private let session: URLSession

    /// Creates a transport backed by `session` (defaults to an ephemeral session).
    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 30
            configuration.httpCookieAcceptPolicy = .never
            configuration.httpShouldSetCookies = false
            self.session = URLSession(configuration: configuration)
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

/// Errors produced while registering, refreshing, or unregistering a closed-app push subscription.
public enum PushRelayClientError: Error, LocalizedError, Equatable, Sendable {
    case disabled
    case invalidEndpoint(PushRelayEndpointValidationError)
    case missingOptedInAccounts
    case missingDevicePushToken
    case invalidDeviceClientID
    case httpFailure(statusCode: Int)
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
        case .invalidDeviceClientID:
            String(localized: "Device client identifier is missing.", bundle: .module)
        case .httpFailure(let statusCode):
            String(localized: "Push relay returned HTTP status \(statusCode).", bundle: .module)
        case .invalidResponse:
            String(localized: "Push relay returned an invalid response.", bundle: .module)
        case .transportFailure(let detail):
            String(localized: "Push relay request failed: \(detail)", bundle: .module)
        }
    }
}

/// Registers, refreshes, and unregisters device push subscriptions against a
/// user-configured HTTPS push relay or JMAP WebPush server (#11).
///
/// Brev never hardcodes or contacts a Brev-hosted proxy. Every request targets
/// only the user-supplied HTTPS URL after strict validation.
public actor PushRelayClient {
    private static let subscriptionIDHeader = "X-Brev-Subscription-ID"
    private static let jmapClientCreationID = "brev-push-sub"

    private let transport: any PushRelayHTTPTransport

    /// Creates a push relay client with the supplied HTTP transport.
    public init(transport: any PushRelayHTTPTransport = URLSessionPushRelayTransport()) {
        self.transport = transport
    }

    /// Registers a device push subscription with the user-configured HTTPS endpoint.
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
        guard (200 ... 299).contains(response.statusCode) else {
            throw PushRelayClientError.httpFailure(statusCode: response.statusCode)
        }
        return try decodeRegistrationResponse(data: data, mode: request.mode)
    }

    /// Refreshes an existing device push subscription against the user-configured HTTPS endpoint.
    public func refresh(
        endpointURLString: String,
        subscriptionID: String,
        request: PushRelayRegistrationRequest,
        bearerToken: String?
    ) async throws -> PushRelayRegistrationResponse {
        try validateRegistrationRequest(request)
        let endpointURL = try validatedEndpoint(endpointURLString)
        let trimmedSubID = subscriptionID.trimmingCharacters(in: .whitespacesAndNewlines)

        let urlRequest: URLRequest
        switch request.mode {
        case .disabled:
            throw PushRelayClientError.disabled
        case .userHostedRelay:
            urlRequest = try makeRelayJSONRequest(
                url: endpointURL,
                method: "PUT",
                body: request,
                subscriptionID: trimmedSubID.isEmpty ? nil : trimmedSubID,
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
        guard (200 ... 299).contains(response.statusCode) else {
            throw PushRelayClientError.httpFailure(statusCode: response.statusCode)
        }
        return try decodeRegistrationResponse(data: data, mode: request.mode)
    }

    /// Unregisters a device push subscription cleanly. HTTP 2xx and 404 both succeed.
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

        let urlRequest: URLRequest
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
            urlRequest = req
        case .userHostedRelay, .disabled:
            urlRequest = try makeRelayJSONRequest(
                url: endpointURL,
                method: "DELETE",
                body: request,
                subscriptionID: request.subscriptionID,
                bearerToken: bearerToken
            )
        }

        let (_, response) = try await perform(urlRequest)
        guard (200 ... 299).contains(response.statusCode) || response.statusCode == 404 else {
            throw PushRelayClientError.httpFailure(statusCode: response.statusCode)
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
        guard !request.devicePushToken.isEmpty else {
            throw PushRelayClientError.missingDevicePushToken
        }
        guard !request.accountIDs.isEmpty else {
            throw PushRelayClientError.missingOptedInAccounts
        }
    }

    private func validatedEndpoint(_ raw: String) throws -> URL {
        do {
            return try PushRelayEndpointValidator.validate(raw)
        } catch let error as PushRelayEndpointValidationError {
            throw PushRelayClientError.invalidEndpoint(error)
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
        let pushDeliveryURLString: String = if (try? PushRelayEndpointValidator.validate(request.devicePushToken)) != nil {
            request.devicePushToken
        } else {
            endpointURL.absoluteString
        }
        let spec: JMAPWebPushSubscriptionSpec
        do {
            spec = try JMAPWebPushSubscriptionSpec(
                deviceClientID: request.deviceClientID,
                urlString: pushDeliveryURLString,
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
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let direct = try? decoder.decode(PushRelayRegistrationResponse.self, from: data),
           !direct.subscriptionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return direct
        }
        if mode == .jmapWebPush, let jmapResponse = parseJMAPSetResponse(data: data) {
            return jmapResponse
        }
        throw PushRelayClientError.invalidResponse
    }

    private func parseJMAPSetResponse(data: Data) -> PushRelayRegistrationResponse? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let methodResponses = root["methodResponses"] as? [[Any]]
        else {
            return nil
        }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        for entry in methodResponses {
            guard entry.count >= 2,
                  let methodName = entry[0] as? String,
                  methodName == "PushSubscription/set",
                  let args = entry[1] as? [String: Any],
                  let created = args["created"] as? [String: [String: Any]]
            else {
                continue
            }
            let createdRecord = created[Self.jmapClientCreationID] ?? created.values.first
            guard let record = createdRecord,
                  let subscriptionID = record["id"] as? String,
                  !subscriptionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                continue
            }
            let expiresAt: Date? = (record["expires"] as? String).flatMap { isoFormatter.date(from: $0) }
            let verificationCode = record["verificationCode"] as? String
            return PushRelayRegistrationResponse(
                subscriptionID: subscriptionID,
                expiresAt: expiresAt,
                verificationCode: verificationCode
            )
        }
        return nil
    }
}
