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

/// Supplies a current access token for one Gmail API request.
public protocol GmailAccessTokenProvider: Sendable {
    /// Returns a current bearer token, refreshing it when the provider needs to.
    func accessToken() async throws -> String
}

/// Executes an HTTP request without imposing a concrete networking stack on
/// `GmailAPITransport`.
public protocol GmailAPIHTTPExecutor: Sendable {
    /// Executes `request` and returns its bytes and URL response.
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

/// Identifies whether a transport error happened before dispatch or after the
/// provider may have accepted a request.
public enum GmailAPIRequestFailurePhase: Error, Sendable, Equatable {
    /// DNS, offline, or request-construction failure before bytes were sent.
    case preDispatch
    /// The request was dispatched, but no response was delivered.
    case postDispatch
}

/// Strict RFC 3986 component encoding shared by the Gmail REST clients.
enum GmailAPIPathComponentEncoder {
    static func encode(_ value: String) -> String {
        // Keep opaque provider IDs from becoming URL dot-segments even when a
        // caller constructs a low-level request directly.
        if value == "." { return "%2E" }
        if value == ".." { return "%2E%2E" }
        return value.utf8.reduce(into: String()) { result, byte in
            if isUnreserved(byte) {
                result.append(Character(UnicodeScalar(byte)))
            } else {
                result += String(format: "%%%02X", byte)
            }
        }
    }

    private static func isUnreserved(_ byte: UInt8) -> Bool {
        (byte >= 0x41 && byte <= 0x5A)
            || (byte >= 0x61 && byte <= 0x7A)
            || (byte >= 0x30 && byte <= 0x39)
            || byte == 0x2D || byte == 0x2E || byte == 0x5F || byte == 0x7E
    }
}

/// High-level Gmail operations required by the Gmail API backend.
public protocol GmailAPITransporting: Sendable {
    /// Returns the authenticated mailbox profile.
    func profile() async throws -> GmailProfile
    /// Returns the current system and user label catalog.
    func listLabels() async throws -> [GmailLabel]
    /// Lists messages by a Gmail label and/or Gmail search query.
    func listMessages(
        labelID: String?,
        query: String?,
        pageToken: String?,
        maxResults: Int
    ) async throws -> GmailMessagePage

    /// Lists messages with Gmail's explicit spam/trash inclusion switch.
    func listMessages(
        labelID: String?,
        query: String?,
        pageToken: String?,
        maxResults: Int,
        includeSpamTrash: Bool
    ) async throws -> GmailMessagePage
    /// Loads one account-wide Gmail message.
    func getMessage(messageID: String, format: GmailMessageFormat) async throws -> GmailMessage
    /// Loads one attachment payload.
    func getAttachment(messageID: String, attachmentID: String) async throws -> GmailAttachment
    /// Creates a Gmail draft from raw MIME source.
    func createDraft(rawMIME: String, threadID: String?) async throws -> GmailDraft
    /// Replaces a Gmail draft's raw MIME source.
    func updateDraft(id: String, rawMIME: String, threadID: String?) async throws -> GmailDraft
    /// Deletes a Gmail draft.
    func deleteDraft(id: String) async throws
    /// Sends an existing Gmail draft.
    func sendDraft(id: String) async throws -> GmailMessage
    /// Sends raw MIME through Gmail.
    func sendMessage(rawMIME: String, threadID: String?) async throws -> GmailMessage
    /// Lists send-as aliases and signatures.
    func listSendAs() async throws -> [GmailSendAs]
}

public extension GmailAPITransporting {
    func listMessages(
        labelID: String?,
        query: String?,
        pageToken: String?,
        maxResults: Int,
        includeSpamTrash: Bool
    ) async throws -> GmailMessagePage {
        _ = includeSpamTrash
        return try await listMessages(
            labelID: labelID,
            query: query,
            pageToken: pageToken,
            maxResults: maxResults
        )
    }

    func createDraft(rawMIME: String, threadID: String? = nil) async throws -> GmailDraft {
        throw GmailAPIError.invalidRequest
    }

    func updateDraft(id: String, rawMIME: String, threadID: String? = nil) async throws -> GmailDraft {
        throw GmailAPIError.invalidRequest
    }

    func deleteDraft(id: String) async throws { throw GmailAPIError.invalidRequest }
    func sendDraft(id: String) async throws -> GmailMessage { throw GmailAPIError.invalidRequest }

    func sendMessage(rawMIME: String, threadID: String? = nil) async throws -> GmailMessage {
        throw GmailAPIError.invalidRequest
    }

    func listSendAs() async throws -> [GmailSendAs] { throw GmailAPIError.invalidRequest }
}

/// The HTTP verb and path/query used by a Gmail API request.
public struct GmailAPIRequest: Sendable, Equatable {
    /// Supported Gmail API HTTP methods.
    public enum Method: String, Sendable, Equatable {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case patch = "PATCH"
        case delete = "DELETE"
    }

    /// HTTP method for the request.
    public let method: Method
    /// Path relative to `https://gmail.googleapis.com/gmail/v1`.
    public let path: String
    /// Query parameters encoded by `URLComponents`.
    public let queryItems: [URLQueryItem]
    /// Optional request body. Callers own the MIME/JSON encoding.
    public let body: Data?
    /// Additional headers. Authorization is owned by the transport.
    public let headers: [String: String]

    /// Creates a Gmail API request.
    public init(
        method: Method,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        headers: [String: String] = [:]
    ) {
        self.method = method
        self.path = path
        self.queryItems = queryItems
        self.body = body
        self.headers = headers
    }
}

/// Limits and endpoint configuration for the Gmail REST transport.
public struct GmailAPITransportConfiguration: Sendable, Equatable {
    /// Gmail's REST API root for user-scoped requests.
    public var baseURL: URL
    /// Maximum response body accepted by the transport.
    public var maxResponseBytes: Int
    /// Maximum number of attempts for idempotent transient failures.
    public var maxRetryAttempts: Int
    /// Initial exponential backoff delay in seconds.
    public var retryBaseDelay: TimeInterval
    /// Maximum delay, including a provider Retry-After value.
    public var retryMaxDelay: TimeInterval

    /// Creates transport configuration.
    public init(
        baseURL: URL = URL(string: "https://gmail.googleapis.com/gmail/v1")!,
        maxResponseBytes: Int = 4 * 1024 * 1024,
        maxRetryAttempts: Int = 3,
        retryBaseDelay: TimeInterval = 0.5,
        retryMaxDelay: TimeInterval = 30
    ) {
        self.baseURL = baseURL
        self.maxResponseBytes = max(1, maxResponseBytes)
        self.maxRetryAttempts = max(1, maxRetryAttempts)
        self.retryBaseDelay = max(0, retryBaseDelay)
        self.retryMaxDelay = max(0, retryMaxDelay)
    }
}

/// Allowlisted Gmail quota reasons safe to retain in local diagnostics.
public enum GmailAPIQuotaReason: String, Sendable, Equatable {
    /// The Google Cloud project's daily Gmail API quota is exhausted.
    case dailyLimitExceeded
    /// Gmail's shared request-rate limit is exhausted.
    case rateLimitExceeded
    /// The signed-in user's Gmail request-rate limit is exhausted.
    case userRateLimitExceeded
    /// Gmail returned its generic quota exhaustion reason.
    case quotaExceeded
}

/// Safe classification of a Gmail API transport failure.
public enum GmailAPIError: Error, Sendable, Equatable, LocalizedError, IMAPFallbackEligibleError {
    /// No access token was available for the request.
    case missingAccessToken
    /// The configured endpoint or request path could not form a URL.
    case invalidRequest
    /// The server response was not an HTTP response.
    case invalidResponse
    /// The response body exceeded the configured safety limit.
    case responseTooLarge(limit: Int)
    /// Google rejected the credential and the account must authenticate again.
    case reauthenticationRequired
    /// Workspace administrator policy prevents this operation.
    case domainPolicy
    /// The access token did not include a Gmail scope required by the request.
    case insufficientPermissions
    /// The Gmail API is unavailable for the configured Google Cloud project.
    case apiAccessNotConfigured
    /// Google denied the request without a more specific safe reason.
    case forbidden
    /// The request can be retried after the provider's transient failure clears.
    case retryable(statusCode: Int, retryAfter: TimeInterval?)
    /// Gmail rejected the request for one allowlisted quota reason.
    case quotaExceeded(reason: GmailAPIQuotaReason, retryAfter: TimeInterval?)
    /// A non-retryable HTTP response without exposing provider response content.
    case httpFailure(statusCode: Int)
    /// The response was HTTP 200 but could not be decoded as the requested model.
    case malformedResponse
    /// The URL session failed before a provider response was received.
    case transportFailure
    /// A send request was dispatched but its response was lost; delivery is
    /// unknown and the caller must not retry automatically.
    case ambiguousSendOutcome
    /// A draft create/update was dispatched but its response was lost; the
    /// caller must preserve local staging and ask the user to reconcile it.
    case ambiguousDraftWriteOutcome

    /// Whether the caller should obtain a new Google authorization.
    public var requiresReauthentication: Bool {
        if case .reauthenticationRequired = self { return true }
        return false
    }

    /// Whether a bounded retry policy may retry the request.
    public var isRetryable: Bool {
        if case .retryable = self { return true }
        if case .quotaExceeded = self { return true }
        if case .transportFailure = self { return true }
        return false
    }

    /// Provider-supplied delay for a transient response.
    public var retryAfter: TimeInterval? {
        if case .retryable(_, let retryAfter) = self { return retryAfter }
        if case .quotaExceeded(_, let retryAfter) = self { return retryAfter }
        return nil
    }

    /// Whether Workspace administrator policy blocked the request.
    public var isDomainPolicy: Bool {
        if case .domainPolicy = self { return true }
        return false
    }

    /// Whether Google IMAP/XOAUTH2 is an explicit viable fallback for this
    /// native API failure.
    public var isIMAPFallbackEligible: Bool {
        switch self {
        case .domainPolicy, .apiAccessNotConfigured, .forbidden, .transportFailure, .invalidResponse:
            true
        case .httpFailure(let statusCode):
            statusCode == 403 || statusCode == 404
        default:
            false
        }
    }

    /// Whether a send may have reached Gmail even though its response was lost.
    public var isAmbiguousSend: Bool {
        if case .ambiguousSendOutcome = self { return true }
        return false
    }

    /// Whether a draft write may have reached Gmail without confirmation.
    public var isAmbiguousDraftWrite: Bool {
        if case .ambiguousDraftWriteOutcome = self { return true }
        return false
    }

    /// A redacted, user-safe description. Provider bodies and tokens are never
    /// included.
    public var errorDescription: String? {
        switch self {
        case .missingAccessToken: return String(localized: "Gmail authentication is unavailable.", bundle: .module)
        case .invalidRequest: return String(localized: "The Gmail request could not be created.", bundle: .module)
        case .invalidResponse: return String(localized: "Gmail returned an invalid response.", bundle: .module)
        case .responseTooLarge(let limit): return String(
                localized: "Gmail returned more data than allowed (limit \(limit) bytes).",
                bundle: .module
            )
        case .reauthenticationRequired: return String(
                localized: "Gmail authorization has expired or was revoked.",
                bundle: .module
            )
        case .domainPolicy: return String(
                localized: "Google Workspace policy prevents Brev from accessing Gmail.",
                bundle: .module
            )
        case .insufficientPermissions: return String(
                localized: "Google did not grant the Gmail permission required by Brev.",
                bundle: .module
            )
        case .apiAccessNotConfigured: return String(
                localized: "The Gmail API is not enabled for Brev's Google project.",
                bundle: .module
            )
        case .forbidden: return String(
                localized: "Google denied Brev access to Gmail.",
                bundle: .module
            )
        case .retryable(let statusCode, _): return String(
                localized: "Gmail is temporarily unavailable (HTTP \(statusCode)).",
                bundle: .module
            )
        case .quotaExceeded(let reason, _): return String(
                localized: "Gmail quota is temporarily unavailable (\(reason.rawValue), HTTP 403).",
                bundle: .module
            )
        case .httpFailure(let statusCode): return String(
                localized: "Gmail rejected the request (HTTP \(statusCode)).",
                bundle: .module
            )
        case .malformedResponse: return String(localized: "Gmail returned data Brev could not read.", bundle: .module)
        case .transportFailure: return String(localized: "Brev could not reach Gmail.", bundle: .module)
        case .ambiguousSendOutcome: return String(
                localized: "Gmail may have received the message, but Brev did not receive confirmation.",
                bundle: .module
            )
        case .ambiguousDraftWriteOutcome: return String(
                localized: "Gmail may have saved the draft, but Brev did not receive confirmation.",
                bundle: .module
            )
        }
    }
}

/// URLSession-backed HTTP executor used by the production transport.
public final class URLSessionGmailAPIHTTPExecutor: GmailAPIHTTPExecutor, @unchecked Sendable {
    private let session: URLSession

    /// Creates an executor backed by `session`.
    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Executes a request through URLSession.
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

/// Small, dependency-injected Gmail REST transport.
public final class GmailAPITransport: GmailAPITransporting, @unchecked Sendable {
    private let accessTokenProvider: any GmailAccessTokenProvider
    private let httpExecutor: any GmailAPIHTTPExecutor
    private let configuration: GmailAPITransportConfiguration
    private let sleep: @Sendable (UInt64) async throws -> Void
    private let jitter: @Sendable (TimeInterval) -> TimeInterval

    /// Creates a transport with injected credentials and HTTP execution.
    public init(
        accessTokenProvider: any GmailAccessTokenProvider,
        httpExecutor: any GmailAPIHTTPExecutor = URLSessionGmailAPIHTTPExecutor(),
        configuration: GmailAPITransportConfiguration = .init(),
        sleep: @escaping @Sendable (UInt64) async throws -> Void = { nanoseconds in
            try await Task.sleep(nanoseconds: nanoseconds)
        },
        jitter: @escaping @Sendable (TimeInterval) -> TimeInterval = { upperBound in
            guard upperBound > 0 else { return 0 }
            return Double.random(in: 0 ... upperBound)
        }
    ) {
        self.accessTokenProvider = accessTokenProvider
        self.httpExecutor = httpExecutor
        self.configuration = configuration
        self.sleep = sleep
        self.jitter = jitter
    }

    /// Resolves a request against the Gmail API root without fetching it.
    public func url(for request: GmailAPIRequest) throws -> URL {
        let normalizedPath = request.path.hasPrefix("/") ? request.path : "/" + request.path
        guard var components = URLComponents(
            url: configuration.baseURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw GmailAPIError.invalidRequest
        }
        let prefix = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.percentEncodedPath = "/" + prefix + normalizedPath
        components.queryItems = nil
        if !request.queryItems.isEmpty {
            components.percentEncodedQuery = request.queryItems.map { item in
                let name = Self.percentEncodeQueryComponent(item.name)
                let value = Self.percentEncodeQueryComponent(item.value ?? "")
                return "\(name)=\(value)"
            }.joined(separator: "&")
        }
        guard let url = components.url else { throw GmailAPIError.invalidRequest }
        return url
    }

    /// Sends `request` and decodes a bounded JSON response.
    public func send<Response: Decodable>(
        _ request: GmailAPIRequest,
        decoding type: Response.Type
    ) async throws -> Response {
        let data = try await perform(request)
        guard !data.isEmpty else { throw GmailAPIError.malformedResponse }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw GmailAPIError.malformedResponse
        }
    }

    /// Sends a request whose successful response has no JSON body, such as a
    /// Gmail delete or batch-modify operation.
    public func send(_ request: GmailAPIRequest) async throws {
        _ = try await perform(request)
    }

    private func perform(_ request: GmailAPIRequest) async throws -> Data {
        let token: String
        do {
            token = try await accessTokenProvider.accessToken()
        } catch let error as GmailAPIError {
            throw error
        } catch {
            throw GmailAPIError.missingAccessToken
        }
        guard !token.isEmpty else { throw GmailAPIError.missingAccessToken }

        let urlRequest = try makeURLRequest(for: request, accessToken: token)
        let canRetry = Self.isIdempotent(request)
        var attempt = 0
        while true {
            attempt += 1
            let result: (Data, URLResponse)
            do {
                result = try await httpExecutor.data(for: urlRequest)
            } catch let phase as GmailAPIRequestFailurePhase {
                if phase == .postDispatch {
                    if Self.isSendRequest(request) {
                        throw GmailAPIError.ambiguousSendOutcome
                    }
                    if Self.isDraftWriteRequest(request) {
                        throw GmailAPIError.ambiguousDraftWriteOutcome
                    }
                }
                throw GmailAPIError.transportFailure
            } catch {
                // URLSession's ordinary offline/DNS errors are pre-dispatch
                // from this seam; never call a send ambiguous without explicit
                // post-dispatch evidence.
                throw GmailAPIError.transportFailure
            }

            guard let response = result.1 as? HTTPURLResponse else {
                throw GmailAPIError.invalidResponse
            }
            guard result.0.count <= configuration.maxResponseBytes else {
                throw GmailAPIError.responseTooLarge(limit: configuration.maxResponseBytes)
            }

            guard !(200 ..< 300).contains(response.statusCode) else { return result.0 }
            let error = classify(response: response, body: result.0)
            guard canRetry, error.isRetryable, attempt < configuration.maxRetryAttempts else {
                throw error
            }
            let exponential = configuration.retryBaseDelay * pow(2, Double(attempt - 1))
            let providerDelay = error.retryAfter ?? 0
            let jitteredExponential = min(
                configuration.retryMaxDelay,
                max(0, jitter(exponential))
            )
            let delay = min(configuration.retryMaxDelay, max(jitteredExponential, providerDelay))
            if delay > 0 {
                try await sleep(UInt64(delay * 1_000_000_000))
            } else {
                try Task.checkCancellation()
            }
        }
    }

    public func profile() async throws -> GmailProfile {
        try await send(
            GmailAPIRequest(method: .get, path: "/users/me/profile"),
            decoding: GmailProfile.self
        )
    }

    public func listLabels() async throws -> [GmailLabel] {
        let response = try await send(
            GmailAPIRequest(method: .get, path: "/users/me/labels"),
            decoding: GmailLabelListResponse.self
        )
        return response.labels
    }

    public func listMessages(
        labelID: String?,
        query: String?,
        pageToken: String?,
        maxResults: Int
    ) async throws -> GmailMessagePage {
        try await listMessages(
            labelID: labelID,
            query: query,
            pageToken: pageToken,
            maxResults: maxResults,
            includeSpamTrash: false
        )
    }

    public func listMessages(
        labelID: String?,
        query: String?,
        pageToken: String?,
        maxResults: Int,
        includeSpamTrash: Bool
    ) async throws -> GmailMessagePage {
        var queryItems = [URLQueryItem(name: "maxResults", value: "\(max(1, min(maxResults, 500)))")]
        if let labelID {
            queryItems.append(URLQueryItem(name: "labelIds", value: labelID))
        }
        if let query, !query.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: query))
        }
        if let pageToken {
            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        if includeSpamTrash {
            queryItems.append(URLQueryItem(name: "includeSpamTrash", value: "true"))
        }
        return try await send(
            GmailAPIRequest(
                method: .get,
                path: "/users/me/messages",
                queryItems: queryItems
            ),
            decoding: GmailMessagePage.self
        )
    }

    public func getMessage(messageID: String, format: GmailMessageFormat) async throws -> GmailMessage {
        guard !messageID.isEmpty, messageID != ".", messageID != ".." else {
            throw GmailAPIError.invalidRequest
        }
        return try await send(
            GmailAPIRequest(
                method: .get,
                path: "/users/me/messages/\(Self.pathComponent(messageID))",
                queryItems: [URLQueryItem(name: "format", value: format.rawValue)]
            ),
            decoding: GmailMessage.self
        )
    }

    public func getAttachment(messageID: String, attachmentID: String) async throws -> GmailAttachment {
        guard !messageID.isEmpty, !attachmentID.isEmpty,
              messageID != ".", messageID != "..",
              attachmentID != ".", attachmentID != ".."
        else { throw GmailAPIError.invalidRequest }
        return try await send(
            GmailAPIRequest(
                method: .get,
                path: "/users/me/messages/\(Self.pathComponent(messageID))/attachments/\(Self.pathComponent(attachmentID))"
            ),
            decoding: GmailAttachment.self
        )
    }

    /// Builds an authenticated request. The access token is intentionally kept
    /// local to this method and is never included in diagnostics.
    public func makeURLRequest(for request: GmailAPIRequest, accessToken: String) throws -> URLRequest {
        guard !accessToken.isEmpty else { throw GmailAPIError.missingAccessToken }
        var urlRequest = try URLRequest(url: url(for: request))
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        for (name, value) in request.headers where name.caseInsensitiveCompare("authorization") != .orderedSame {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        if request.body != nil, urlRequest.value(forHTTPHeaderField: "Content-Type") == nil {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return urlRequest
    }

    private func classify(response: HTTPURLResponse, body: Data) -> GmailAPIError {
        let providerError = parseProviderError(from: body)
        if response.statusCode == 401 {
            return .reauthenticationRequired
        }
        if response.statusCode == 403 {
            if let reason = providerError.reason.flatMap(GmailAPIQuotaReason.init(rawValue:)) {
                return .quotaExceeded(reason: reason, retryAfter: retryAfter(from: response))
            }
            switch providerError.reason {
            case "domainPolicy": return .domainPolicy
            case "insufficientPermissions": return .insufficientPermissions
            case "accessNotConfigured": return .apiAccessNotConfigured
            case "forbidden": return .forbidden
            default: break
            }
        }
        if response.statusCode == 429 || (500 ... 599).contains(response.statusCode) {
            return .retryable(statusCode: response.statusCode, retryAfter: retryAfter(from: response))
        }
        return .httpFailure(statusCode: response.statusCode)
    }

    private func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        if let seconds = TimeInterval(value), seconds >= 0 { return seconds }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: value) {
            return max(0, date.timeIntervalSinceNow)
        }
        return nil
    }

    private func parseProviderError(from body: Data) -> (reason: String?, code: Int?) {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let error = object["error"] as? [String: Any]
        else { return (nil, nil) }
        let code = error["code"] as? Int
        let errors = error["errors"] as? [[String: Any]]
        let reason = errors?.compactMap { $0["reason"] as? String }.first
        return (reason, code)
    }

    private static func percentEncodeQueryComponent(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~:@")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    private static func pathComponent(_ value: String) -> String {
        GmailAPIPathComponentEncoder.encode(value)
    }

    private static func isSendRequest(_ request: GmailAPIRequest) -> Bool {
        request.method == .post
            && (request.path.hasSuffix("/messages/send") || request.path.hasSuffix("/drafts/send"))
    }

    private static func isDraftWriteRequest(_ request: GmailAPIRequest) -> Bool {
        (request.method == .post && request.path.hasSuffix("/drafts"))
            || (request.method == .put && request.path.contains("/drafts/"))
    }

    private static func isIdempotent(_ request: GmailAPIRequest) -> Bool {
        switch request.method {
        case .get, .put, .delete: return true
        case .post, .patch: return false
        }
    }
}

private struct GmailLabelListResponse: Decodable {
    let labels: [GmailLabel]

    private enum CodingKeys: String, CodingKey { case labels }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        labels = try container.decodeIfPresent([GmailLabel].self, forKey: .labels) ?? []
    }
}
