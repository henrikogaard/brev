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
import OSLog

enum MailPerformanceDiagnostics {
    enum StartupRestorePath: String, Sendable {
        case cache
        case remote
    }

    enum SearchScope: String, Sendable {
        case singleFolder
        case allFolders
    }

    enum SearchPath: String, Sendable {
        case cacheOnly
        case cacheThenServerHit
        case server
        case cacheFallback
        case failure
    }

    enum MessagePagePath: String, Sendable {
        case cacheHit
        case server
        case cacheFallback
        case offlinePaginationEnd
        case failure
    }

    enum BodySourcePath: String, Sendable {
        case cacheHit
        case server
        case cacheFallback
        case failure
    }

    struct SearchSnapshot: Equatable, Sendable {
        let execution: SearchExecution
        let scope: SearchScope
        let searchedFolderCount: Int
        let shape: String

        var publicDescription: String {
            "execution=\(execution.rawValue) scope=\(scope.rawValue) folders=\(searchedFolderCount) shape=\(shape)"
        }
    }

    struct Interval {
        fileprivate let name: StaticString
        fileprivate let state: OSSignpostIntervalState
        let startedAt: Date
    }

    private static let logger = Logger(
        subsystem: "eu.brevmail.brev",
        category: "Performance"
    )

    private static let signposter = OSSignposter(logger: logger)

    static func searchSnapshot(
        for query: SearchQuery,
        searchedFolderCount: Int
    ) -> SearchSnapshot {
        SearchSnapshot(
            execution: query.execution,
            scope: query.folderID == nil ? .allFolders : .singleFolder,
            searchedFolderCount: searchedFolderCount,
            shape: searchShape(for: query)
        )
    }

    static func beginInterval(_ name: StaticString) -> Interval {
        Interval(
            name: name,
            state: signposter.beginInterval(name),
            startedAt: Date()
        )
    }

    static func endInterval(_ interval: Interval) {
        signposter.endInterval(interval.name, interval.state)
    }

    static func durationMilliseconds(since start: Date, now: Date = Date()) -> Int {
        max(0, Int((now.timeIntervalSince(start) * 1000).rounded()))
    }

    static func logStartupRestore(
        path: StartupRestorePath,
        durationMilliseconds: Int
    ) {
        logger.info(
            "mail.startup.restore finished path=\(path.rawValue, privacy: .public) durationMs=\(durationMilliseconds, privacy: .public)"
        )
    }

    static func logSearchFinished(
        snapshot: SearchSnapshot,
        path: SearchPath,
        resultCount: Int,
        durationMilliseconds: Int
    ) {
        logger.info(
            "mail.search finished \(snapshot.publicDescription, privacy: .public) path=\(path.rawValue, privacy: .public) resultCount=\(resultCount, privacy: .public) durationMs=\(durationMilliseconds, privacy: .public)"
        )
    }

    static func logSearchFailed(
        snapshot: SearchSnapshot,
        error: any Error,
        durationMilliseconds: Int
    ) {
        logger.warning(
            "mail.search failed \(snapshot.publicDescription, privacy: .public) path=\(SearchPath.failure.rawValue, privacy: .public) error=\(errorCategory(for: error), privacy: .public) durationMs=\(durationMilliseconds, privacy: .public)"
        )
    }

    static func logSearchCacheRead(
        snapshot: SearchSnapshot,
        resultCount: Int,
        durationMilliseconds: Int
    ) {
        logger.debug(
            "mail.search.cacheRead \(snapshot.publicDescription, privacy: .public) resultCount=\(resultCount, privacy: .public) durationMs=\(durationMilliseconds, privacy: .public)"
        )
    }

    static func logMessagePageFinished(
        path: MessagePagePath,
        pageTokenPresent: Bool,
        resultCount: Int,
        hasNextPage: Bool,
        durationMilliseconds: Int
    ) {
        logger.info(
            "mail.messages.page finished path=\(path.rawValue, privacy: .public) pageTokenPresent=\(pageTokenPresent, privacy: .public) resultCount=\(resultCount, privacy: .public) hasNextPage=\(hasNextPage, privacy: .public) durationMs=\(durationMilliseconds, privacy: .public)"
        )
    }

    static func logMessagePageFailed(
        pageTokenPresent: Bool,
        error: any Error,
        durationMilliseconds: Int
    ) {
        logger.warning(
            "mail.messages.page failed path=\(MessagePagePath.failure.rawValue, privacy: .public) pageTokenPresent=\(pageTokenPresent, privacy: .public) error=\(errorCategory(for: error), privacy: .public) durationMs=\(durationMilliseconds, privacy: .public)"
        )
    }

    static func logBodySourceFinished(
        path: BodySourcePath,
        durationMilliseconds: Int
    ) {
        logger.info(
            "mail.body.source finished path=\(path.rawValue, privacy: .public) durationMs=\(durationMilliseconds, privacy: .public)"
        )
    }

    static func logBodySourceFailed(
        error: any Error,
        durationMilliseconds: Int
    ) {
        logger.warning(
            "mail.body.source failed path=\(BodySourcePath.failure.rawValue, privacy: .public) error=\(errorCategory(for: error), privacy: .public) durationMs=\(durationMilliseconds, privacy: .public)"
        )
    }

    static func logBodyCacheRead(
        hit: Bool,
        durationMilliseconds: Int
    ) {
        logger.debug(
            "mail.body.cacheRead hit=\(hit, privacy: .public) durationMs=\(durationMilliseconds, privacy: .public)"
        )
    }

    static func errorCategory(for error: any Error) -> String {
        if let backendError = error as? MailBackendError {
            return backendErrorCategory(backendError)
        }
        if let imapError = error as? IMAPClientError {
            return imapErrorCategory(imapError)
        }
        if error is CancellationError {
            return "task.cancelled"
        }
        return String(describing: type(of: error))
    }

    private static func searchShape(for query: SearchQuery) -> String {
        var fields: [String] = []
        if !query.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields.append("text")
        }
        if query.from != nil {
            fields.append("from")
        }
        if query.to != nil {
            fields.append("to")
        }
        if query.subject != nil {
            fields.append("subject")
        }
        if query.dateRange != nil {
            fields.append("date")
        }
        if query.hasAttachments != nil {
            fields.append("attachment")
        }
        if query.isUnread != nil {
            fields.append("read")
        }
        if query.isFlagged != nil {
            fields.append("flag")
        }
        return fields.isEmpty ? "none" : fields.joined(separator: ",")
    }

    private static func backendErrorCategory(_ error: MailBackendError) -> String {
        switch error {
        case .notConnected:
            "backend.notConnected"
        case .authenticationRequired:
            "backend.authenticationRequired"
        case .notSupported:
            "backend.notSupported"
        case .notFound:
            "backend.notFound"
        case .permissionDenied:
            "backend.permissionDenied"
        case .quotaExceeded:
            "backend.quotaExceeded"
        case .rateLimited:
            "backend.rateLimited"
        case .network:
            "backend.network"
        case .credentialStoreUnavailable:
            "backend.credentialStoreUnavailable"
        case .backendSpecific:
            "backend.specific"
        }
    }

    private static func imapErrorCategory(_ error: IMAPClientError) -> String {
        switch error {
        case .invalidServerKind:
            "imap.invalidServerKind"
        case .unsupportedTLSMode:
            "imap.unsupportedTLSMode"
        case .unsupportedSearchCriterion:
            "imap.unsupportedSearchCriterion"
        case .connectionRejected:
            "imap.connectionRejected"
        case .authenticationFailed:
            "imap.authenticationFailed"
        case .connectionLimitExceeded:
            "imap.connectionLimitExceeded"
        case .commandFailed:
            "imap.commandFailed"
        case .commandNotSupported:
            "imap.commandNotSupported"
        case .malformedResponse:
            "imap.malformedResponse"
        case .transport:
            "imap.transport"
        case .serverBye:
            "imap.serverBye"
        case .idleNotSupported:
            "imap.idleNotSupported"
        }
    }
}
