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

/// The collection searched, independent of whether all its pages have arrived.
public enum MailSearchCoverage: String, Sendable {
    case cached, server, unverified
}

/// One source-owned search update. A coverage change replaces earlier results.
public struct MailSearchUpdate: Sendable {
    /// New matching headers; incremental server pages do not repeat prior pages.
    public let headers: [MessageHeader]
    /// The collection supplying this update; completeness is tracked separately.
    public let coverage: MailSearchCoverage
    /// Replaces earlier results from this source, including same-coverage cached fallback.
    public let replacesResults: Bool
    /// No more updates are expected on successful completion of this search.
    public let isComplete: Bool
    /// Attachment names for results matched by local attachment content only
    /// (ADR-0078 §5). Messages that also matched the message index are absent.
    public let attachmentMatchNames: [MessageHeader.ID: String]

    /// Creates an incremental update or an explicit result replacement.
    public init(
        headers: [MessageHeader],
        coverage: MailSearchCoverage,
        replacesResults: Bool = false,
        isComplete: Bool = false,
        attachmentMatchNames: [MessageHeader.ID: String] = [:]
    ) {
        self.headers = headers
        self.coverage = coverage
        self.replacesResults = replacesResults
        self.isComplete = isComplete
        self.attachmentMatchNames = attachmentMatchNames
    }
}

/// An awaited, request-owned callback providing backpressure between search pages.
public typealias MailSearchProgressHandler = @Sendable (MailSearchUpdate) async -> Void

/// Optional progressive search with explicit cache/server coverage and normal task cancellation.
public protocol ProgressiveMailSearching: BackendExtensionService {
    /// Publishes cached matches and provider pages while retaining the final array contract.
    /// - Parameters:
    ///   - query: Explicit user search and its cache/server execution policy.
    ///   - sourceID: Optional owning mailbox, validated before any search work.
    ///   - onUpdate: Awaited after each batch; callers reject updates from stale requests.
    func searchWithProgress(_ query: SearchQuery, sourceID: MailSourceID?,
                            onUpdate: @escaping MailSearchProgressHandler) async throws -> [MessageHeader]
}
