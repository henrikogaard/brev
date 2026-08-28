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

// MARK: - Credential

/// Authentication material for a single CalDAV write request.
///
/// Resolved from the Keychain immediately before a request and never
/// retained beyond the call. HTTP Basic is only permitted for localhost
/// development servers (mirrors `CalDAVConfiguration.AuthMode`).
public enum CalDAVCredential: Sendable, Hashable {
    /// OAuth2 Bearer token (preferred).
    case bearer(token: String)
    /// HTTP Basic — only for localhost dev servers.
    case basic(username: String, password: String)

    /// The value for the `Authorization` request header.
    public var authorizationHeaderValue: String {
        switch self {
        case .bearer(let token):
            return "Bearer \(token)"
        case .basic(let username, let password):
            let raw = "\(username):\(password)"
            let encoded = Data(raw.utf8).base64EncodedString()
            return "Basic \(encoded)"
        }
    }
}

// MARK: - Write target

/// A narrow CalDAV write target: a single calendar collection into which
/// accepted invites are PUT as calendar object resources.
///
/// This deliberately models *only* what is needed to add one event. It
/// does not represent a browseable calendar list or a sync collection —
/// This writer does not provide calendar browsing or full CalDAV sync.
public struct CalDAVWriteTarget: Sendable, Hashable, Codable {
    /// URL of the calendar collection, e.g.
    /// `https://caldav.example.com/calendars/user/personal/`.
    /// A trailing slash is recommended; the writer tolerates its absence.
    public var collectionURL: URL
    /// Authentication mode for the target server.
    public var authMode: CalDAVConfiguration.AuthMode

    public init(collectionURL: URL, authMode: CalDAVConfiguration.AuthMode = .oauth2) {
        self.collectionURL = collectionURL
        self.authMode = authMode
    }

    /// Builds the calendar object resource URL for an event UID.
    ///
    /// Per RFC 4791 §5.3.2 the resource name is arbitrary but using the
    /// UID with a `.ics` suffix is the universal convention and makes the
    /// PUT idempotent for a given event.
    func resourceURL(forUID uid: String) -> URL {
        let safeName = Self.sanitize(uid) + ".ics"
        var base = collectionURL
        if !base.absoluteString.hasSuffix("/") {
            base = URL(string: base.absoluteString + "/") ?? base
        }
        return base.appendingPathComponent(safeName)
    }

    /// Replaces path-hostile characters in a UID so it can be used as a
    /// single URL path segment.
    static func sanitize(_ uid: String) -> String {
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.")
        let scalars = uid.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(scalars)
        return collapsed.isEmpty ? "event" : collapsed
    }
}

// MARK: - Result and errors

/// Outcome of a successful CalDAV PUT.
public struct CalDAVWriteResult: Sendable, Hashable {
    public enum Outcome: Sendable, Hashable {
        /// The event resource did not exist and was created (201).
        case created
        /// An existing event resource was replaced (200/204).
        case updated
    }

    public let outcome: Outcome
    /// Server-assigned ETag, if returned. Used for later conditional writes.
    public let etag: String?
    public let resourceURL: URL
}

/// Errors surfaced by `CalDAVEventWriter`.
public enum CalDAVWriteError: Error, Equatable, Sendable {
    /// The event ICS had no usable UID, so no stable resource path exists.
    case missingUID
    /// HTTP Basic was requested for a non-localhost host.
    case insecureBasicAuth
    /// Authentication failed (401/403).
    case authenticationFailed
    /// The conditional create failed because the resource already exists
    /// and the caller asked not to overwrite (412 with If-None-Match).
    case conflict
    /// Any other non-2xx status. The body is intentionally omitted to
    /// avoid leaking credentials echoed by misbehaving servers.
    case unexpectedStatus(Int)
    /// Transport-level failure (DNS, offline, TLS). Message is the
    /// localized description with no credential material.
    case transport(String)
}

// MARK: - Writer

/// PUTs accepted-invite events into a single configured CalDAV
/// collection. This is the only network-write surface in `BrevCalendar`;
/// everything else (parsing, iMIP) is local-only.
///
/// Usage is feature-flagged and opt-in: callers construct a writer only
/// when the user has configured a target. When no target is configured,
/// callers fall back to the local iMIP reply path (`IMIPReplyComposer`).
public actor CalDAVEventWriter {
    private let target: CalDAVWriteTarget
    private let credential: CalDAVCredential
    private let urlSession: URLSession

    /// Creates a writer bound to one collection and one credential.
    ///
    /// - Parameters:
    ///   - target: The calendar collection to write into.
    ///   - credential: Auth material, resolved from Keychain by the caller.
    ///   - urlSession: Injected for testability; defaults to `.shared`.
    public init(
        target: CalDAVWriteTarget,
        credential: CalDAVCredential,
        urlSession: URLSession = .shared
    ) {
        self.target = target
        self.credential = credential
        self.urlSession = urlSession
    }

    /// PUTs a calendar object resource for `event`.
    ///
    /// - Parameters:
    ///   - event: Parsed invite whose UID names the resource.
    ///   - ics: The full `VCALENDAR` payload to store (typically the
    ///     original invite with the user's `PARTSTAT` applied).
    ///   - overwriteExisting: When `false` (default), a conditional create
    ///     (`If-None-Match: *`) is used so an existing event is never
    ///     silently clobbered; a `412` maps to `.conflict`.
    /// - Returns: The write outcome and any server ETag.
    public func putEvent(
        _ event: ICSParser.ParsedEvent,
        ics: String,
        overwriteExisting: Bool = false
    ) async throws -> CalDAVWriteResult {
        let uid = event.uid?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uid, !uid.isEmpty else {
            throw CalDAVWriteError.missingUID
        }
        return try await put(uid: uid, ics: ics, overwriteExisting: overwriteExisting)
    }

    /// PUTs raw ICS under an explicit UID. Lower-level entry point used by
    /// `putEvent(_:ics:)` and directly by tests.
    public func put(
        uid: String,
        ics: String,
        overwriteExisting: Bool = false
    ) async throws -> CalDAVWriteResult {
        // Guard against HTTP Basic over the public internet.
        if case .basic = credential {
            let host = target.collectionURL.host?.lowercased() ?? ""
            guard host == "localhost" || host == "127.0.0.1" || host == "::1" else {
                throw CalDAVWriteError.insecureBasicAuth
            }
        }

        let resourceURL = target.resourceURL(forUID: uid)
        var request = URLRequest(
            url: resourceURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )
        request.httpMethod = "PUT"
        request.setValue("text/calendar; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(credential.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        if !overwriteExisting {
            // RFC 4791 §5.3.2: conditional create.
            request.setValue("*", forHTTPHeaderField: "If-None-Match")
        }
        request.httpBody = Data(ics.utf8)

        let response: URLResponse
        do {
            (_, response) = try await urlSession.data(for: request)
        } catch {
            throw CalDAVWriteError.transport(error.localizedDescription)
        }

        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? -1
        let etag = http?.value(forHTTPHeaderField: "ETag")

        switch status {
        case 201:
            return CalDAVWriteResult(outcome: .created, etag: etag, resourceURL: resourceURL)
        case 200, 204:
            return CalDAVWriteResult(outcome: .updated, etag: etag, resourceURL: resourceURL)
        case 401, 403:
            throw CalDAVWriteError.authenticationFailed
        case 412:
            throw CalDAVWriteError.conflict
        default:
            throw CalDAVWriteError.unexpectedStatus(status)
        }
    }
}
