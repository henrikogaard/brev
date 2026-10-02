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

enum MessageListRowIndicator: Hashable, Sendable {
    case answered
    case forwarded

    /// Indicators for a header, in display order.
    ///
    /// Rows call this once per render for the status glyphs and once for the
    /// compact accessibility value; the array is tiny but the calls sit on the
    /// scrolling hot path, so the result is cheap to rebuild and stable for
    /// a given header.
    static func indicators(for header: MessageHeader) -> [MessageListRowIndicator] {
        var result: [MessageListRowIndicator] = []
        result.reserveCapacity(2)
        if header.isAnswered {
            result.append(.answered)
        }
        if header.isForwarded {
            result.append(.forwarded)
        }
        return result
    }

    var symbolName: String {
        switch self {
        case .answered:
            "arrowshape.turn.up.left.fill"
        case .forwarded:
            "arrowshape.turn.up.right.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .answered:
            "Answered"
        case .forwarded:
            "Forwarded"
        }
    }
}
