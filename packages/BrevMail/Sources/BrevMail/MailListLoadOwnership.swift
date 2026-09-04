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

/// Owns publication rights for one visible list; pages share their parent load's token.
@MainActor
final class MailListLoadOwnership {
    private(set) var current = UUID()

    func begin() -> UUID {
        current = UUID()
        return current
    }

    func invalidate() { current = UUID() }

    func debounceSearch(_ request: UUID, sleep: @Sendable (UInt64) async throws -> Void = {
        try await Task.sleep(nanoseconds: $0)
    }) async -> Bool {
        let elapsed = await MessageListSearchDebouncePolicy.waitForDebounce(sleep: sleep)
        return elapsed && accepts(request)
    }

    func accepts(_ request: UUID) -> Bool { !Task.isCancelled && current == request }
}
