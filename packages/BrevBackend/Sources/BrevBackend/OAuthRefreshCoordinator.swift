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

/// Serializes OAuth refresh exchanges per account while allowing unrelated
/// accounts to refresh concurrently.
public actor OAuthRefreshCoordinator {
    private var inFlight: [String: Task<Token, Error>] = [:]

    /// Creates an empty refresh coordinator.
    public init() {}

    /// Runs one refresh operation per account at a time.
    ///
    /// Concurrent callers for the same account await the first operation and
    /// receive its exact result. The in-flight entry is removed after success
    /// or failure so a failed exchange can be retried.
    ///
    /// - Parameters:
    ///   - accountID: Stable Brev account identifier used as the single-flight key.
    ///   - operation: The token exchange and persistence operation to run once.
    /// - Returns: The token produced by the shared operation.
    /// - Throws: The operation's error to every caller waiting on that exchange.
    public func run(
        for accountID: String,
        operation: @escaping @Sendable () async throws -> Token
    ) async throws -> Token {
        if let existing = inFlight[accountID] {
            return try await existing.value
        }

        let task = Task { try await operation() }
        inFlight[accountID] = task
        defer { inFlight[accountID] = nil }
        return try await task.value
    }
}
