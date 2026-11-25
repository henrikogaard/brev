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

/// Value-type HTTP request passed through `JMAPHTTPTransport`.
public struct JMAPHTTPRequest: Sendable, Equatable {
    /// Target HTTPS URL.
    public let url: URL
    /// HTTP method (`GET`, `POST`, etc.).
    public let method: String
    /// HTTP request headers.
    public let headers: [String: String]
    /// Optional HTTP request body bytes.
    public let body: Data?
    /// Whether cross-origin redirects are permitted (with credentials stripped).
    /// Set `false` for session discovery and authenticated API calls so redirect destinations
    /// cannot supply spoofed endpoints or hijack credentialed flows.
    public let allowCrossOriginRedirects: Bool

    /// Creates an HTTP request descriptor.
    public init(
        url: URL,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil,
        allowCrossOriginRedirects: Bool = true
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.allowCrossOriginRedirects = allowCrossOriginRedirects
    }
}

/// Value-type HTTP response returned by `JMAPHTTPTransport`.
public struct JMAPHTTPResponse: Sendable, Equatable {
    /// HTTP status code.
    public let statusCode: Int
    /// Case-preserving HTTP response headers.
    public let headers: [String: String]
    /// Response body bytes.
    public let body: Data
    /// Final resolved URL after any safe redirects.
    public let finalURL: URL

    /// Creates an HTTP response value.
    public init(
        statusCode: Int,
        headers: [String: String] = [:],
        body: Data,
        finalURL: URL
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.finalURL = finalURL
    }

    /// Reads a response header case-insensitively.
    public func headerValue(for name: String) -> String? {
        headers.first(where: { $0.key.caseInsensitiveCompare(name) == .orderedSame })?.value
    }

    /// Parses an integer `Retry-After` header in seconds when present.
    public var retryAfterSeconds: TimeInterval? {
        guard let raw = headerValue(for: "Retry-After")?.trimmingCharacters(in: .whitespacesAndNewlines),
              let seconds = TimeInterval(raw),
              seconds >= 0
        else {
            return nil
        }
        return seconds
    }
}

/// Single parsed Server-Sent Event frame from an RFC 8620 §7.3 JMAP `EventSource` stream.
public struct JMAPEventSourceEvent: Sendable, Equatable {
    /// Event type name (`event:` field), e.g. `"state"`.
    public let event: String?
    /// Last event ID (`id:` field), if supplied.
    public let id: String?
    /// Concatenated `data:` payload lines joined by `\n`.
    public let data: String

    /// Creates a parsed SSE event frame.
    public init(event: String? = nil, id: String? = nil, data: String) {
        self.event = event
        self.id = id
        self.data = data
    }
}

/// Injectable HTTP + EventSource transport seam for `BrevJMAP`.
///
/// Production code uses `URLSessionJMAPHTTPTransport`; unit tests inject deterministic
/// offline mocks with zero live network calls.
public protocol JMAPHTTPTransport: Sendable {
    /// Executes a single HTTP request and returns its status, headers, and body.
    func send(_ request: JMAPHTTPRequest) async throws -> JMAPHTTPResponse
    /// Opens a streaming RFC 8620 §7.3 `EventSource` SSE connection.
    func streamEvents(_ request: JMAPHTTPRequest) -> AsyncThrowingStream<JMAPEventSourceEvent, Error>
    /// Opens an RFC 8620 §7.3 `EventSource` SSE stream and suspends until the HTTP 200 handshake completes.
    func openEventStream(_ request: JMAPHTTPRequest) async throws -> AsyncThrowingStream<JMAPEventSourceEvent, Error>
}

public extension JMAPHTTPTransport {
    /// Default fallback delegating to `streamEvents(_:)` for lightweight transports.
    func openEventStream(_ request: JMAPHTTPRequest) async throws -> AsyncThrowingStream<JMAPEventSourceEvent, Error> {
        streamEvents(request)
    }
}

/// Strict HTTPS validator, RFC 8620 §2 well-known URL resolver, and RFC 6570 template expander.
public enum JMAPURLValidator {
    private static let unreservedCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    /// Validates that `url` uses strict `https://`, has a non-empty host, and carries no embedded credentials.
    public static func validateHTTPSURL(_ url: URL) throws -> URL {
        do {
            return try JMAPSetupURLValidator.validateHTTPSURL(url)
        } catch let error as JMAPSetupURLValidationError {
            switch error {
            case .invalid(let reason):
                throw JMAPError.invalidSessionURL(reason)
            }
        }
    }

    /// Resolves a user-entered JMAP session URL or bare domain/host into a strict HTTPS discovery URL.
    ///
    /// - Explicit `https://host/path` URLs are validated and preserved as entered (if the path is empty or `/`,
    ///   `/.well-known/jmap` is appended per RFC 8620 §2).
    /// - Bare hostnames or domains such as `fastmail.com` or `mail.example.org` become
    ///   `https://<host>/.well-known/jmap`.
    /// - Non-HTTPS schemes (such as `http://`) and embedded credentials are rejected.
    public static func discoveryURL(from rawInput: String) throws -> URL {
        do {
            return try JMAPSetupURLValidator.discoveryURL(from: rawInput)
        } catch let error as JMAPSetupURLValidationError {
            switch error {
            case .invalid(let reason):
                throw JMAPError.invalidSessionURL(reason)
            }
        }
    }

    /// Returns canonical `(scheme, lowercased host, effective port)` origin string for redirect comparison.
    public static func origin(for url: URL) -> String {
        let scheme = (url.scheme ?? "").lowercased()
        let host = (url.host ?? "").lowercased()
        let defaultPort = (scheme == "https") ? 443 : (scheme == "http" ? 80 : nil)
        let effectivePort = url.port ?? defaultPort
        if let effectivePort {
            return "\(scheme)://\(host):\(effectivePort)"
        }
        return "\(scheme)://\(host)"
    }

    /// Checks whether two URLs share the same scheme, lowercased host, and effective port.
    public static func isSameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        origin(for: lhs) == origin(for: rhs)
    }

    /// Percent-encodes a single URI template parameter value using RFC 3986 unreserved characters only.
    public static func percentEncodeTemplateValue(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreservedCharacters) ?? value
    }

    /// Expands an RFC 6570 Level 1 URI template (`{accountId}`, `{blobId}`, `{name}`, `{type}`, etc.)
    /// with strict RFC 3986 percent-encoding and validates the resulting URL as strict HTTPS.
    public static func expandURITemplate(
        _ template: String,
        parameters: [String: String]
    ) throws -> URL {
        var expanded = ""
        var cursor = template.startIndex
        while cursor < template.endIndex {
            if template[cursor] == "{" {
                guard let close = template[cursor...].firstIndex(of: "}") else {
                    throw JMAPError.invalidDownloadURL
                }
                let rawKey = String(template[template.index(after: cursor) ..< close])
                guard let value = parameters[rawKey] else {
                    throw JMAPError.invalidDownloadURL
                }
                expanded.append(percentEncodeTemplateValue(value))
                cursor = template.index(after: close)
            } else {
                expanded.append(template[cursor])
                cursor = template.index(after: cursor)
            }
        }
        guard let url = URL(string: expanded) else {
            throw JMAPError.invalidDownloadURL
        }
        return try validateHTTPSURL(url)
    }
}

/// Pure stateful parser for WHATWG Server-Sent Events (`text/event-stream`) frames used by RFC 8620 §7.3.
public struct JMAPEventSourceParser: Sendable {
    private var currentEvent: String?
    private var currentID: String?
    private var dataLines: [String] = []

    /// Creates a fresh SSE frame parser.
    public init() {}

    /// Feeds one line (without trailing `\r` / `\n`) and returns a completed event when a blank separator line arrives.
    public mutating func feedLine(_ rawLine: String) -> JMAPEventSourceEvent? {
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
        if line.isEmpty {
            return flush()
        }
        if line.hasPrefix(":") {
            // Comment / keepalive heartbeat line.
            return nil
        }
        let field: String
        let value: String
        if let colonIndex = line.firstIndex(of: ":") {
            field = String(line[..<colonIndex])
            var afterColon = line[line.index(after: colonIndex)...]
            if afterColon.first == " " {
                afterColon = afterColon.dropFirst()
            }
            value = String(afterColon)
        } else {
            field = line
            value = ""
        }
        switch field {
        case "event":
            currentEvent = value
        case "id":
            if !value.contains("\0") {
                currentID = value
            }
        case "data":
            dataLines.append(value)
        default:
            break
        }
        return nil
    }

    /// Flushes any pending event accumulated so far.
    public mutating func flush() -> JMAPEventSourceEvent? {
        guard !dataLines.isEmpty else {
            currentEvent = nil
            return nil
        }
        let event = JMAPEventSourceEvent(
            event: currentEvent,
            id: currentID,
            data: dataLines.joined(separator: "\n")
        )
        currentEvent = nil
        dataLines.removeAll(keepingCapacity: true)
        return event
    }
}

/// Evaluates HTTP redirects for JMAP requests: rejects non-HTTPS or credential-bearing redirects,
/// enforces a hop cap, and strips `Authorization` headers when crossing origins.
public enum JMAPRedirectPolicy {
    /// Maximum allowed HTTP redirect hops for a single JMAP request.
    public static let maxRedirects = 5

    /// Validates and rewrites a redirected `URLRequest`.
    ///
    /// - Parameters:
    ///   - originalRequest: The request prior to redirection.
    ///   - proposedRequest: The system-proposed redirected request.
    ///   - redirectCount: Number of redirects already followed for this task.
    ///   - allowCrossOrigin: When `false`, cross-origin redirects throw `JMAPError.untrustedRedirect`.
    /// - Returns: The sanitized redirected request, with `Authorization` stripped on cross-origin hops.
    public static func evaluateRedirect(
        from originalRequest: URLRequest,
        to proposedRequest: URLRequest,
        redirectCount: Int,
        allowCrossOrigin: Bool = true
    ) throws -> URLRequest {
        guard redirectCount < maxRedirects else {
            throw JMAPError.tooManyRedirects
        }
        guard let targetURL = proposedRequest.url else {
            throw JMAPError.insecureRedirect
        }
        do {
            _ = try JMAPURLValidator.validateHTTPSURL(targetURL)
        } catch {
            throw JMAPError.insecureRedirect
        }
        var sanitized = proposedRequest
        if let originalURL = originalRequest.url,
           !JMAPURLValidator.isSameOrigin(originalURL, targetURL) {
            guard allowCrossOrigin else {
                throw JMAPError.untrustedRedirect
            }
            sanitized.setValue(nil, forHTTPHeaderField: "Authorization")
            sanitized.setValue(nil, forHTTPHeaderField: "Cookie")
        }
        return sanitized
    }
}

/// Production `URLSession`-backed `JMAPHTTPTransport` enforcing strict HTTPS and safe cross-origin redirects.
public final class URLSessionJMAPHTTPTransport: NSObject, JMAPHTTPTransport, @unchecked Sendable {
    /// Shared production transport instance to avoid leaking `URLSession` delegates.
    public static let shared = URLSessionJMAPHTTPTransport()

    private let lock = NSLock()
    private var redirectCounts: [Int: Int] = [:]
    private var redirectErrors: [Int: JMAPError] = [:]
    private var session: URLSession!
    private var strictOriginSession: URLSession!
    private let ownsSession: Bool

    /// Creates a transport with dedicated ephemeral `URLSession`s.
    public init(configuration: URLSessionConfiguration = .ephemeral) {
        ownsSession = true
        super.init()
        let copy = configuration.copy() as? URLSessionConfiguration ?? .ephemeral
        copy.httpShouldSetCookies = false
        copy.httpCookieAcceptPolicy = .never
        copy.timeoutIntervalForRequest = 30
        copy.timeoutIntervalForResource = 120
        let strictCopy = copy.copy() as? URLSessionConfiguration ?? .ephemeral
        session = URLSession(configuration: copy, delegate: self, delegateQueue: nil)
        strictOriginSession = URLSession(configuration: strictCopy, delegate: self, delegateQueue: nil)
    }

    deinit {
        if ownsSession {
            session?.invalidateAndCancel()
            strictOriginSession?.invalidateAndCancel()
        }
    }

    /// Sends a single HTTPS request with safe redirect handling.
    public func send(_ request: JMAPHTTPRequest) async throws -> JMAPHTTPResponse {
        let validatedURL = try JMAPURLValidator.validateHTTPSURL(request.url)
        var urlRequest = URLRequest(url: validatedURL)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (field, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }

        let targetSession: URLSession = request.allowCrossOriginRedirects ? session : strictOriginSession
        let data: Data
        let rawResponse: URLResponse
        do {
            (data, rawResponse) = try await targetSession.data(for: urlRequest)
        } catch {
            if let captured = takeLastRedirectError() {
                throw captured
            }
            if error is CancellationError {
                throw error
            }
            throw JMAPError.networkFailure
        }

        if let captured = takeLastRedirectError() {
            throw captured
        }
        guard let http = rawResponse as? HTTPURLResponse,
              let finalURL = http.url
        else {
            throw JMAPError.invalidResponse
        }
        _ = try JMAPURLValidator.validateHTTPSURL(finalURL)
        if !request.allowCrossOriginRedirects,
           !JMAPURLValidator.isSameOrigin(validatedURL, finalURL) {
            throw JMAPError.untrustedRedirect
        }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            headers[String(describing: key)] = String(describing: value)
        }
        return JMAPHTTPResponse(
            statusCode: http.statusCode,
            headers: headers,
            body: data,
            finalURL: finalURL
        )
    }

    /// Opens an RFC 8620 §7.3 `EventSource` endpoint and awaits HTTP 200 readiness before returning the stream.
    public func openEventStream(
        _ request: JMAPHTTPRequest
    ) async throws -> AsyncThrowingStream<JMAPEventSourceEvent, Error> {
        let validatedURL = try JMAPURLValidator.validateHTTPSURL(request.url)
        var urlRequest = URLRequest(url: validatedURL)
        urlRequest.httpMethod = request.method
        urlRequest.timeoutInterval = 300
        for (field, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        let targetSession: URLSession = request.allowCrossOriginRedirects ? session : strictOriginSession
        let bytes: URLSession.AsyncBytes
        let rawResponse: URLResponse
        do {
            (bytes, rawResponse) = try await targetSession.bytes(for: urlRequest)
        } catch {
            if let captured = takeLastRedirectError() {
                throw captured
            }
            if error is CancellationError {
                throw error
            }
            throw JMAPError.networkFailure
        }
        if let captured = takeLastRedirectError() {
            throw captured
        }
        guard let http = rawResponse as? HTTPURLResponse else {
            throw JMAPError.invalidResponse
        }
        if let finalURL = http.url,
           !request.allowCrossOriginRedirects,
           !JMAPURLValidator.isSameOrigin(validatedURL, finalURL) {
            throw JMAPError.untrustedRedirect
        }
        try Self.throwIfNonSuccessStatus(http.statusCode, retryAfter: nil)
        try Self.validateEventSourceContentType(http.value(forHTTPHeaderField: "Content-Type"))

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var parser = JMAPEventSourceParser()
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        if let event = parser.feedLine(line) {
                            continuation.yield(event)
                        }
                    }
                    if let trailing = parser.flush() {
                        continuation.yield(trailing)
                    }
                    continuation.finish()
                } catch {
                    if let captured = self.takeLastRedirectError() {
                        continuation.finish(throwing: captured)
                    } else if error is JMAPError {
                        continuation.finish(throwing: error)
                    } else if error is CancellationError {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: JMAPError.networkFailure)
                    }
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Streams Server-Sent Events from an RFC 8620 §7.3 `EventSource` endpoint.
    public func streamEvents(_ request: JMAPHTTPRequest) -> AsyncThrowingStream<JMAPEventSourceEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let readyStream = try await self.openEventStream(request)
                    for try await event in readyStream {
                        if Task.isCancelled { break }
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    if error is CancellationError {
                        continuation.finish()
                    } else if error is JMAPError {
                        continuation.finish(throwing: error)
                    } else {
                        continuation.finish(throwing: JMAPError.networkFailure)
                    }
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Validates that an EventSource 2xx HTTP response advertises the `text/event-stream` media type
    /// (case-insensitive, ignoring parameters such as `; charset=utf-8`).
    public static func validateEventSourceContentType(_ contentTypeHeader: String?) throws {
        guard let raw = contentTypeHeader else {
            throw JMAPError.invalidResponse
        }
        let mediaType = raw
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard mediaType == "text/event-stream" else {
            throw JMAPError.invalidResponse
        }
    }

    private static func throwIfNonSuccessStatus(_ statusCode: Int, retryAfter: TimeInterval?) throws {
        switch statusCode {
        case 200 ... 299:
            return
        case 401:
            throw JMAPError.authenticationRequired
        case 403:
            throw JMAPError.forbidden
        case 429:
            throw JMAPError.rateLimited(retryAfter: retryAfter)
        case 500 ... 599:
            throw JMAPError.serverError(statusCode: statusCode)
        default:
            throw JMAPError.httpError(statusCode: statusCode)
        }
    }

    private func takeLastRedirectError() -> JMAPError? {
        lock.withLock {
            guard let firstKey = redirectErrors.keys.first else { return nil }
            return redirectErrors.removeValue(forKey: firstKey)
        }
    }
}

extension URLSessionJMAPHTTPTransport: URLSessionTaskDelegate {
    public func urlSession(
        _ urlSession: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let taskID = task.taskIdentifier
        let currentCount = lock.withLock { redirectCounts[taskID] ?? 0 }
        let allowCrossOrigin = (urlSession !== strictOriginSession)
        do {
            let sourceRequest = task.currentRequest ?? task.originalRequest ?? request
            let nextRequest = try JMAPRedirectPolicy.evaluateRedirect(
                from: sourceRequest,
                to: request,
                redirectCount: currentCount,
                allowCrossOrigin: allowCrossOrigin
            )
            lock.withLock {
                redirectCounts[taskID] = currentCount + 1
            }
            completionHandler(nextRequest)
        } catch let error as JMAPError {
            lock.withLock {
                redirectErrors[taskID] = error
            }
            completionHandler(nil)
            task.cancel()
        } catch {
            lock.withLock {
                redirectErrors[taskID] = .insecureRedirect
            }
            completionHandler(nil)
            task.cancel()
        }
    }

    public func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError _: Error?) {
        let taskID = task.taskIdentifier
        lock.withLock {
            _ = redirectCounts.removeValue(forKey: taskID)
        }
    }
}
