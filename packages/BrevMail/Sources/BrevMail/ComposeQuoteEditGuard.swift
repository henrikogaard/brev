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

/// Marks the region of the compose body that carries the quoted original
/// message so the platform editors can refuse edits landing inside it.
struct ComposeQuoteProtection: Equatable {
    /// Which side of the typing zone the quote occupies.
    enum Edge {
        /// Quote is the trailing region from the marker to the end (reply
        /// "below reply" and forwarded message layouts).
        case bottom
        /// Quote is the leading region: marker line plus following
        /// `> `-prefixed lines (reply "above reply" layout).
        case top
    }

    /// First line of the quote block, matched literally in the storage.
    var marker: String
    var edge: Edge
}

/// Computes the read-only quote region of a compose body and decides whether
/// a pending text change may proceed.
enum ComposeQuoteEditGuard {
    /// The quote region protected from editing, or `nil` when the storage
    /// does not contain the marker (plain compose, drafts without a quote).
    static func protectedRange(
        in storage: NSString,
        protection: ComposeQuoteProtection
    ) -> NSRange? {
        let markerRange: NSRange
        switch protection.edge {
        case .bottom:
            // Last match wins so marker text pasted into the user's own
            // region can't shadow the real quote below it.
            markerRange = storage.range(of: protection.marker, options: [.literal, .backwards])
        case .top:
            markerRange = storage.range(of: protection.marker, options: [.literal])
        }
        guard markerRange.location != NSNotFound else { return nil }

        switch protection.edge {
        case .bottom:
            return NSRange(location: markerRange.location, length: storage.length - markerRange.location)
        case .top:
            // Quote block = marker line plus the following `> `-prefixed
            // lines; the blank gap after them is the user's typing zone.
            var quoteEnd = markerRange.location + markerRange.length
            let tail = storage.substring(from: quoteEnd)
            for line in tail.components(separatedBy: "\n").dropFirst() {
                guard line.hasPrefix("> ") else { break }
                quoteEnd += (line as NSString).length + 1
            }
            return NSRange(location: 0, length: min(quoteEnd, storage.length))
        }
    }

    /// Whether a `shouldChangeTextIn` edit may proceed. A caret insert is
    /// refused only when strictly inside the quote — at either edge of the
    /// region it lands in the typing zone. Any nonzero-length change is
    /// refused when it intersects the quote at all.
    static func allows(
        changeRange: NSRange,
        in storage: NSString,
        protection: ComposeQuoteProtection?
    ) -> Bool {
        guard let protection,
              let protected = protectedRange(in: storage, protection: protection) else {
            return true
        }
        if changeRange.length == 0 {
            return changeRange.location <= protected.location
                || changeRange.location >= NSMaxRange(protected)
        }
        return NSIntersectionRange(changeRange, protected).length == 0
    }
}
