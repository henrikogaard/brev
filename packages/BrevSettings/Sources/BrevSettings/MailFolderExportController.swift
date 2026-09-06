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
import Observation

/// Presentation state for a single user-initiated folder export.
public enum MailFolderExportState: Equatable, Sendable {
    case idle
    case exporting(Int)
    case cancelling
    case completed(URL, Int)
    case cancelled
    case failed(String)
}

/// Captures session validity while a destination picker is open.
public struct MailFolderExportSessionToken: Sendable, Equatable {
    fileprivate let id: UUID
}

/// Shares export progress and cancellation behavior between Mail and Settings.
@Observable
@MainActor
public final class MailFolderExportController {
    public private(set) var state: MailFolderExportState = .idle
    public private(set) var sourceTitle = ""
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var requestID: UUID?
    @ObservationIgnored private var sessionID = UUID()

    /// Capture before presenting a destination picker.
    public var sessionToken: MailFolderExportSessionToken { MailFolderExportSessionToken(id: sessionID) }

    /// Retires pending picker callbacks and cancels source work.
    public func invalidateSession() { sessionID = UUID(); cancel() }

    /// Retires exports when any owning backend disappears, preserving account navigation and additions.
    public func reconcileSessions(previous: [ObjectIdentifier], current: [ObjectIdentifier]) {
        if !Set(previous).isSubset(of: Set(current)) { invalidateSession() }
    }

    @ObservationIgnored private var lastProgressUpdate: ContinuousClock.Instant?

    /// Creates an idle export controller.
    public init() {}

    /// Whether a new export can start after the current task settles.
    public var isRunning: Bool {
        switch state {
        case .exporting, .cancelling: true
        default: false
        }
    }

    /// Starts one export with a source description captured alongside the request.
    @discardableResult
    public func start(_ exporter: MailFolderExporter, to destination: URL, format: MailFolderExportFormat,
                      sourceTitle: String, replacingExistingFile: Bool = true,
                      accessing securityScopedURL: URL? = nil,
                      sessionToken: MailFolderExportSessionToken? = nil) -> Task<Void, Never>? {
        guard !isRunning else { return nil }
        if let sessionToken, sessionToken.id != sessionID {
            reportSelectionFailure(String(localized: "The mailbox session changed. Start the export again.", bundle: .module),
                                   sourceTitle: sourceTitle)
            return nil
        }
        let id = UUID()
        requestID = id
        self.sourceTitle = sourceTitle
        state = .exporting(0)
        lastProgressUpdate = nil
        let work = Task.detached(priority: .background) { [weak self] in
            do {
                let result = try await exporter.export(
                    to: destination,
                    format: format,
                    replacingExistingFile: replacingExistingFile,
                    accessing: securityScopedURL
                ) { [weak self] completed in
                    await self?.recordProgress(completed, requestID: id)
                }
                await self?.finish(.completed(result.url, result.messageCount), requestID: id)
            } catch is CancellationError {
                await self?.finish(.cancelled, requestID: id)
            } catch {
                await self?.finish(.failed(error.localizedDescription), requestID: id)
            }
        }
        task = work
        return work
    }

    private func recordProgress(_ completed: Int, requestID id: UUID) {
        guard requestID == id, case .exporting = state else { return }
        let now = ContinuousClock.now
        // Fast cache exports should not redraw the surrounding mailbox per message.
        if let lastProgressUpdate, now - lastProgressUpdate < .milliseconds(100) { return }
        state = .exporting(completed)
        lastProgressUpdate = now
    }

    private func finish(_ result: MailFolderExportState, requestID id: UUID) {
        guard requestID == id else { return }
        state = result
        task = nil
        requestID = nil
    }

    deinit { task?.cancel() }

    /// Shows a destination-picker failure without replacing running export progress.
    public func reportSelectionFailure(_ message: String, sourceTitle: String) {
        guard !isRunning else { return }
        self.sourceTitle = sourceTitle
        state = .failed(message)
    }

    /// Requests cancellation; publication decides whether completion or cancellation won.
    public func cancel() {
        guard isRunning else { return }
        state = .cancelling
        task?.cancel()
    }

    /// Dismisses a settled result without interrupting running work.
    public func dismiss() { if !isRunning { state = .idle } }
}
