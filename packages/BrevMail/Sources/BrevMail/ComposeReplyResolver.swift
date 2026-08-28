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

public enum ComposeReplyMode: Hashable, Sendable {
    case sender
    case all
}

public enum ComposeReplyResolver {
    public static func recipients(
        for header: MessageHeader,
        mode: ComposeReplyMode,
        accountEmail: String
    ) -> [String] {
        let replyTargets = header.replyTo.isEmpty
            ? [header.from.email]
            : header.replyTo.map(\.email)
        switch mode {
        case .sender:
            return uniqueEmails(replyTargets, excluding: accountEmail)
        case .all:
            let candidates = replyTargets
                + header.to.map(\.email)
                + header.cc.map(\.email)
            return uniqueEmails(candidates, excluding: accountEmail)
        }
    }

    private static func uniqueEmails(
        _ emails: [String],
        excluding accountEmail: String
    ) -> [String] {
        let excluded = normalized(accountEmail)
        var seen = Set<String>()
        var result: [String] = []
        for email in emails {
            let normalizedEmail = normalized(email)
            guard !normalizedEmail.isEmpty,
                  normalizedEmail != excluded,
                  seen.insert(normalizedEmail).inserted
            else {
                continue
            }
            result.append(email)
        }
        return result
    }

    private static func normalized(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
