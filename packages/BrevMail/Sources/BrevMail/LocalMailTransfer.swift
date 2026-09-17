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

/// Outcome of a Copy/Move to Local Folder run (ADR-0077 decision 4).
public struct LocalMailTransferResult: Sendable {
    /// Message IDs successfully written to the local folder.
    public var copiedIDs: [MessageHeader.ID] = []
    /// Source message IDs whose server delete actually ran. Only these may be
    /// removed from the source listing — a write that succeeded while the
    /// delete failed is in `copiedIDs` but not here.
    public var removedSourceIDs: [MessageHeader.ID] = []
    /// Per-message failures, surfaced in the existing banner pattern.
    public var failures: [(id: MessageHeader.ID, error: String)] = []

    public init() {}

    public var succeeded: Int { copiedIDs.count }
    public var isClean: Bool { failures.isEmpty }
}

/// Copy/Move-to-local-folder orchestration. Pure coordination — the raw
/// fetch, the local write, and the source delete are all injected, so tests
/// can prove Move never deletes a server copy whose local write failed.
public struct LocalMailTransfer: Sendable {
    /// Fetches the message's original bytes (ADR-0045 raw-source seam).
    public let fetchRaw: @Sendable (MessageHeader.ID) async throws -> Data
    /// Writes raw bytes into the local folder; returns the local message ID.
    public let writeLocal: @Sendable (Data) async throws -> MessageHeader.ID
    /// The existing undoable delete on the source account — run only after a
    /// local write succeeded, so Undo restores from Trash exactly like a
    /// delete today (ADR-0077 decision 4).
    public let deleteSource: @Sendable (MessageHeader.ID) async throws -> Void

    public init(
        fetchRaw: @escaping @Sendable (MessageHeader.ID) async throws -> Data,
        writeLocal: @escaping @Sendable (Data) async throws -> MessageHeader.ID,
        deleteSource: @escaping @Sendable (MessageHeader.ID) async throws -> Void = { _ in }
    ) {
        self.fetchRaw = fetchRaw
        self.writeLocal = writeLocal
        self.deleteSource = deleteSource
    }

    /// Copy: fetch → local write. Source is never touched.
    public func copy(_ messageIDs: [MessageHeader.ID]) async -> LocalMailTransferResult {
        var result = LocalMailTransferResult()
        for id in messageIDs {
            do {
                let data = try await fetchRaw(id)
                let localID = try await writeLocal(data)
                result.copiedIDs.append(localID)
            } catch {
                result.failures.append((id, error.localizedDescription))
            }
        }
        return result
    }

    /// Move: fetch → local write → undoable source delete, per message.
    /// A failed local write leaves the server copy untouched.
    public func move(_ messageIDs: [MessageHeader.ID]) async -> LocalMailTransferResult {
        var result = LocalMailTransferResult()
        for id in messageIDs {
            let localID: MessageHeader.ID
            do {
                let data = try await fetchRaw(id)
                localID = try await writeLocal(data)
            } catch {
                result.failures.append((id, error.localizedDescription))
                continue
            }
            // The local copy exists now — even if the source delete fails the
            // message was moved semantically, so report it distinctly.
            result.copiedIDs.append(localID)
            do {
                try await deleteSource(id)
                result.removedSourceIDs.append(id)
            } catch {
                result.failures.append((
                    id,
                    String(
                        localized: "Copied, but could not be removed from the source account.",
                        bundle: .module
                    )
                ))
            }
        }
        return result
    }
}
