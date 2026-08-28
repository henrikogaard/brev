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

/// Best-effort CTE decode for IMAP listing BODY[TEXT] peeks (no MIME headers).
enum IMAPListingSnippetTransferEncoding {
    /// Decodes quoted-printable when the peek looks QP-encoded; otherwise returns input.
    static func decodeIfNeeded(_ rawSnippet: String) -> String {
        let trimmed = rawSnippet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeQuotedPrintable(trimmed) else {
            return rawSnippet
        }
        let decoded = MIMEQuotedPrintableDecoder.decode(trimmed)
        return String(data: decoded, encoding: .utf8)
            ?? String(data: decoded, encoding: .isoLatin1)
            ?? rawSnippet
    }

    /// Requires soft breaks or repeated strong QP tokens (`=0A`/`=0D`/`=20`/`=3D`).
    /// A lone `code=10` / `retry=20` pair must not count as quoted-printable.
    static func looksLikeQuotedPrintable(_ value: String) -> Bool {
        if value.contains("=\n") || value.contains("=\r\n") {
            return true
        }

        var strongEscapeCount = 0
        var index = value.startIndex
        while index < value.endIndex {
            guard value[index] == "=",
                  value.distance(from: index, to: value.endIndex) >= 3 else {
                index = value.index(after: index)
                continue
            }
            let high = value.index(after: index)
            let low = value.index(after: high)
            let escape = String(value[high ... low]).lowercased()
            if escape == "0a" || escape == "0d" || escape == "20" || escape == "3d" {
                strongEscapeCount += 1
                if strongEscapeCount >= 2 {
                    return true
                }
            }
            index = value.index(after: low)
        }
        return false
    }
}
