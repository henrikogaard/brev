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

/// A typed folder clause. Its role is portable; an actual folder ID belongs to a single mailbox.
struct SearchFolderPhrase: Hashable, Sendable {
    let role: FolderRole
    let text: String
    let name: String

    var title: String { String(format: String(localized: "Folder: %@", bundle: .module), name) }

    private static let roles: [String: FolderRole] = [
        "sent": .sent, "sendt": .sent, "inbox": .inbox, "innboks": .inbox,
        "drafts": .drafts, "utkast": .drafts, "archive": .archive, "arkiv": .archive,
        "trash": .trash, "papirkurv": .trash, "spam": .spam, "søppelpost": .spam,
    ]

    private static let expression = try? NSRegularExpression(
        pattern: #"(?<!\S)(?:in|i)\s+("# + roles.keys.sorted().joined(separator: "|") + #")(?=\s|$)"#,
        options: .caseInsensitive
    )

    static func extract(from text: inout String) -> Self? {
        guard let match = expression?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text), let word = Range(match.range(at: 1), in: text),
              let role = roles[text[word].lowercased()] else { return nil }
        let phrase = Self(role: role, text: String(text[range]), name: String(text[word]))
        text.replaceSubrange(range, with: " ")
        return phrase
    }
}
