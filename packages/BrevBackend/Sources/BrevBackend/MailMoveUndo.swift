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

/// A reversal bound to the provider and mailbox that performed a move.
public struct MailMoveUndo: Sendable {
    public let sourceID: MailSourceID
    public let originalFolder: Folder
    private let action: @Sendable () async throws -> [MessageHeader.ID: MessageHeader.ID]

    /// Captures provider-specific restoration without exposing provider models to views.
    public init(sourceID: MailSourceID, originalFolder: Folder,
                action: @escaping @Sendable () async throws -> [MessageHeader.ID: MessageHeader.ID]) {
        self.sourceID = sourceID
        self.originalFolder = originalFolder
        self.action = action
    }

    /// Restores moved messages and maps original IDs to their current restored IDs.
    public func restore() async throws -> [MessageHeader.ID: MessageHeader.ID] {
        try await action()
    }
}
