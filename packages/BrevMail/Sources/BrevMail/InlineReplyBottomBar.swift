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

/// The docked reply's bottom bar (#302): Send, Later and Write lead; attach
/// and format trail. Later and Write appear only when the account can use
/// them, so the bar never shows a control that cannot work.
enum InlineReplyBottomBar {
    enum Item: Hashable, Sendable {
        case send
        case later
        case write
        case attach
        case format
    }

    /// The bar's items, in order.
    static func items(canScheduleSend: Bool, offersAIWriter: Bool) -> [Item] {
        var items: [Item] = [.send]
        if canScheduleSend { items.append(.later) }
        if offersAIWriter { items.append(.write) }
        return items + [.attach, .format]
    }
}
