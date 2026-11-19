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

/// Text for the macOS thread header (#306 slice 4): who is in the conversation.
enum ThreadConversationHeaderPresentation {
    /// Names up to three participants; beyond that, two names and a count.
    /// A participant without a display name is shown by address. The keys
    /// match the catalog's existing name-list strings (ADR-0058).
    static func participantLine(_ participants: [Correspondent]) -> String? {
        let names = participants.map(\.displayName)
        switch names.count {
        case 0:
            return nil
        case 1:
            return names[0]
        case 2:
            return String(localized: "\(names[0]) and \(names[1])", bundle: .module)
        case 3:
            return String(localized: "\(names[0]), \(names[1]), and \(names[2])", bundle: .module)
        default:
            let others = names.count - 2
            return String(localized: "\(names[0]), \(names[1]), and \(others) others", bundle: .module)
        }
    }
}
