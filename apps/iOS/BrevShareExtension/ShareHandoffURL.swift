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

/// Thread-safe budget for staged share attachments.
///
/// Each accepted attachment reserves its byte count up front so the per-share
/// count and total-size caps hold even though `NSItemProvider` loads files
/// concurrently. A reservation is never released: staged files are deleted
/// with the handoff directory after the app imports them.
final class ShareHandoffReservation: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var bytes = 0
    private let maximumCount: Int
    private let maximumBytes: Int

    init(maximumCount: Int, maximumBytes: Int) {
        self.maximumCount = maximumCount
        self.maximumBytes = maximumBytes
    }

    /// Atomically claims `bytes` of the remaining budget. Returns `false`
    /// without mutating state when the count or byte cap would be exceeded.
    func reserve(bytes: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard count < maximumCount, self.bytes + bytes <= maximumBytes else { return false }
        count += 1
        self.bytes += bytes
        return true
    }
}

/// Builds the `brev://compose?shared=…` handoff URL the share extension uses
/// to pass shared content to the app. Parsed on the app side by
/// `SharedComposePayload.prefill(from:)` in BrevMail.
///
/// Kept free of UIKit and extension-context dependencies so the same source
/// file is compiled into `BrevIOSTests` — an app extension cannot be linked
/// by a test bundle.
enum ShareHandoffURL {
    /// Upper bound for text handed to the app through the `brev://compose`
    /// URL. The OS drops oversized custom-scheme URLs, so larger shares are
    /// excluded up front instead of failing the handoff.
    static let maximumSharedTextBytes = 256 * 1024

    /// Whether `text` fits inside the handoff URL budget.
    static func canHandoff(text: String) -> Bool {
        text.utf8.count <= maximumSharedTextBytes
    }

    /// Builds the percent-encoded `shared` payload: one `text=` item plus a
    /// `url=` item per shared link and an `attachment=` item per staged file.
    /// Returns an empty string when there is nothing to hand off.
    static func payload(text: String?, urls: [URL], attachments: [URL]) -> String {
        var queryItems: [URLQueryItem] = []

        if let text, !text.isEmpty {
            queryItems.append(URLQueryItem(name: "text", value: text))
        }

        for url in urls {
            queryItems.append(URLQueryItem(name: "url", value: url.absoluteString))
        }

        for url in attachments {
            queryItems.append(URLQueryItem(name: "attachment", value: url.absoluteString))
        }

        var components = URLComponents()
        components.queryItems = queryItems
        return components.percentEncodedQuery ?? ""
    }

    /// Builds the `brev://compose?shared=…` URL, or `nil` when the payload
    /// is empty.
    static func url(text: String?, urls: [URL], attachments: [URL]) -> URL? {
        let sharedPayload = payload(text: text, urls: urls, attachments: attachments)
        guard !sharedPayload.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "brev"
        components.host = "compose"
        components.queryItems = [
            URLQueryItem(name: "shared", value: sharedPayload)
        ]
        return components.url
    }
}
