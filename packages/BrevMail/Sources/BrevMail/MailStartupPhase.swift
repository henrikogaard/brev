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

/// Ordered startup phases for Apple Mail-class cold/warm launch.
///
/// Work advances only forward. Callers gate network-heavy or non-critical tasks
/// by phase so first usable content stays on the critical path.
public enum MailStartupPhase: Int, Sendable, Comparable {
    /// Process just launched; no workspace snapshot yet.
    case cold = 0
    /// Local cache/workspace is good enough for first paint.
    case cachedUsable = 1
    /// User can interact; live change streams / IDLE may start.
    case interactive = 2
    /// Non-critical background maintenance is allowed.
    case background = 3

    public static func < (lhs: MailStartupPhase, rhs: MailStartupPhase) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

@MainActor
public final class MailStartupPhaseController {
    public private(set) var phase: MailStartupPhase = .cold

    public init() {}

    @discardableResult
    public func advance(to newPhase: MailStartupPhase) -> Bool {
        guard newPhase > phase else { return false }
        phase = newPhase
        return true
    }

    public func allows(_ minimum: MailStartupPhase) -> Bool {
        phase >= minimum
    }
}
