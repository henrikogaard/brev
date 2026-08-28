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

/// Shared MIME wire-format helpers for SMTP DATA and IMAP APPEND payloads.
enum MIMEWireEncoding {
    /// Returns message bytes with every line ending normalized to CRLF.
    ///
    /// Fastmail and other strict IMAP servers reject APPEND literals that
    /// contain bare LF (`0x0A`) or lone CR (`0x0D`). SMTP already normalizes
    /// before DATA; IMAP APPEND must do the same for Sent-copy/draft/fixture
    /// payloads that were built with Swift multiline strings.
    static func crlfNormalizedMessageData(_ data: Data) -> Data {
        var output = Data()
        output.reserveCapacity(data.count + max(8, data.count / 32))

        var index = data.startIndex
        while index < data.endIndex {
            let byte = data[index]
            let nextIndex = data.index(after: index)

            if byte == 0x0D {
                if nextIndex < data.endIndex, data[nextIndex] == 0x0A {
                    output.append(contentsOf: [0x0D, 0x0A])
                    index = data.index(after: nextIndex)
                } else {
                    output.append(contentsOf: [0x0D, 0x0A])
                    index = nextIndex
                }
            } else if byte == 0x0A {
                output.append(contentsOf: [0x0D, 0x0A])
                index = nextIndex
            } else {
                output.append(byte)
                index = nextIndex
            }
        }

        return output
    }
}
