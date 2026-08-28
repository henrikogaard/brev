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
import OSLog

enum MailUIPerformanceDiagnostics {
    enum StartupSurface: String, Sendable {
        case sessionRestore
        case workspace
    }

    enum Surface: String, Sendable {
        case messageList
        case unifiedInbox
        case messageBody
        case bodyRenderer
    }

    enum ListPath: String, Sendable {
        case reload
        case loadMore
        case search
        case failure
    }

    enum BodyVisibilityRenderer: String, Sendable {
        case bodyState
        case webView
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

    static func logStartupReady(
        surface: StartupSurface,
        usableContent: Bool,
        durationMilliseconds: Int
    ) {
        logger.info(
            "ui.startup.ready surface=\(surface.rawValue, privacy: .public) usableContent=\(usableContent, privacy: .public) durationMs=\(durationMilliseconds, privacy: .public)"
        )
    }

    static func logListFinished(
        surface: Surface,
        path: ListPath,
        resultCount: Int,
        hasMore: Bool,
        durationMilliseconds: Int
    ) {
        logger.info(
            "ui.list finished surface=\(surface.rawValue, privacy: .public) path=\(path.rawValue, privacy: .public) resultCount=\(resultCount, privacy: .public) hasMore=\(hasMore, privacy: .public) durationMs=\(durationMilliseconds, privacy: .public)"
        )
    }

    static func logListSearchFinished(
        surface: Surface,
        execution: SearchExecution,
        resultCount: Int,
        skippedSourceCount: Int,
        durationMilliseconds: Int
    ) {
        logger.info(
            "ui.search finished surface=\(surface.rawValue, privacy: .public) execution=\(execution.rawValue, privacy: .public) resultCount=\(resultCount, privacy: .public) skippedSourceCount=\(skippedSourceCount, privacy: .public) durationMs=\(durationMilliseconds, privacy: .public)"
        )
    }

    static func logListFailed(
        surface: Surface,
        path: ListPath,
        error: any Error,
        durationMilliseconds: Int
    ) {
        logger.warning(
            "ui.list failed surface=\(surface.rawValue, privacy: .public) path=\(path.rawValue, privacy: .public) error=\(errorCategory(for: error), privacy: .public) durationMs=\(durationMilliseconds, privacy: .public)"
        )
    }

    static func logBodyFetchFinished(
        durationMilliseconds: Int
    ) {
        logger.info(
            "ui.body.fetch finished surface=\(Surface.messageBody.rawValue, privacy: .public) durationMs=\(durationMilliseconds, privacy: .public)"
        )
    }

    static func logBodyFetchFailed(
        error: any Error,
        durationMilliseconds: Int
    ) {
        logger.warning(
            "ui.body.fetch failed surface=\(Surface.messageBody.rawValue, privacy: .public) error=\(errorCategory(for: error), privacy: .public) durationMs=\(durationMilliseconds, privacy: .public)"
        )
    }

    static func logBodyRenderFinished(
        hasHTML: Bool,
        hasPlainText: Bool,
        attachmentCount: Int,
        durationMilliseconds: Int
    ) {
        logger.info(
            "ui.body.render finished surface=\(Surface.bodyRenderer.rawValue, privacy: .public) hasHTML=\(hasHTML, privacy: .public) hasPlainText=\(hasPlainText, privacy: .public) attachmentCount=\(attachmentCount, privacy: .public) durationMs=\(durationMilliseconds, privacy: .public)"
        )
    }

    static func logBodyVisible(
        interval: Interval,
        renderer: BodyVisibilityRenderer
    ) {
        endInterval(interval)
        logger.info(
            "ui.body.visible surface=\(Surface.messageBody.rawValue, privacy: .public) renderer=\(renderer.rawValue, privacy: .public) durationMs=\(durationMilliseconds(since: interval.startedAt), privacy: .public)"
        )
    }

    static func logBodyOpenFailed(interval: Interval, error: any Error) {
        endInterval(interval)
        logger.warning(
            "ui.body.open failed surface=\(Surface.messageBody.rawValue, privacy: .public) error=\(errorCategory(for: error), privacy: .public) durationMs=\(durationMilliseconds(since: interval.startedAt), privacy: .public)"
        )
    }

    static func logHTMLImportFinished(
        resultPresent: Bool,
        durationMilliseconds: Int
    ) {
        logger.info(
            "ui.body.htmlImport finished surface=\(Surface.bodyRenderer.rawValue, privacy: .public) resultPresent=\(resultPresent, privacy: .public) durationMs=\(durationMilliseconds, privacy: .public)"
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
        case .commandNotSupported:
            "imap.commandNotSupported"
        case .connectionRejected:
            "imap.connectionRejected"
        case .authenticationFailed:
            "imap.authenticationFailed"
        case .connectionLimitExceeded:
            "imap.connectionLimitExceeded"
        case .commandFailed:
            "imap.commandFailed"
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
