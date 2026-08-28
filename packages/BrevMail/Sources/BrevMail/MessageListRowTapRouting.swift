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

import CoreGraphics

/// Routes a message-row tap to the control it landed on.
///
/// The row owns a `highPriorityGesture` so single-click selection stays
/// instant inside a `List`, but that gesture also wins over buttons nested
/// in the row — which left the thread chevron unable to collapse an
/// expanded thread. Routing by hit frame keeps row selection responsive
/// while giving the chevron its own tap target.
enum MessageListRowTapRouting {
    /// What a row tap should do.
    enum Destination {
        /// Expand or collapse the tapped row's thread.
        case toggleThread
        /// Select (or open) the tapped message.
        case activate
    }

    /// Extra hit slop around the chevron, in points. The glyph is small and
    /// sits between text runs, so an exact frame is easy to miss.
    private static let hitSlop: CGFloat = 4

    /// Returns the destination for a tap at `location`, expressed in the
    /// row's coordinate space.
    ///
    /// - Parameters:
    ///   - location: Tap location in the row's coordinate space.
    ///   - threadToggleFrame: The chevron's frame in that same space, or
    ///     `.zero` when the row shows no thread chevron.
    static func destination(
        for location: CGPoint,
        threadToggleFrame: CGRect
    ) -> Destination {
        guard !threadToggleFrame.isEmpty else { return .activate }
        let target = threadToggleFrame.insetBy(dx: -hitSlop, dy: -hitSlop)
        return target.contains(location) ? .toggleThread : .activate
    }
}
