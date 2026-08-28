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

/// Splits a flat RFC 5322 message into outer headers and the MIME content
/// entity whose bytes are signed or encrypted.
struct MIMEEntitySplit: Equatable {
    let topHeaderLines: [String]
    let contentEntity: Data

    static let crlf = "\r\n"

    static func make(from messageData: Data) -> MIMEEntitySplit {
        let split = headerAndBody(in: messageData)
        let headerBlock = canonicalCRLF(String(decoding: split.headers, as: UTF8.self))

        let logicalHeaders = foldedHeaderLines(in: headerBlock)
        var topHeaders: [String] = []
        var contentHeaders: [String] = []
        for header in logicalHeaders {
            if headerName(header).lowercased().hasPrefix("content-") {
                contentHeaders.append(header)
            } else {
                topHeaders.append(header)
            }
        }
        if contentHeaders.isEmpty {
            contentHeaders = ["Content-Type: text/plain; charset=utf-8"]
        }

        let contentHeader = contentHeaders.joined(separator: crlf) + crlf + crlf
        var contentEntity = Data(contentHeader.utf8)
        contentEntity.append(split.body)
        return MIMEEntitySplit(
            topHeaderLines: topHeaders,
            contentEntity: contentEntity
        )
    }

    /// Locates the first common RFC 5322 header/body delimiter without decoding
    /// body bytes. Headers are textual and may be canonicalized; the body must
    /// remain byte-for-byte identical before signing or encryption.
    private static func headerAndBody(in messageData: Data) -> (headers: Data, body: Data) {
        let delimiters = [
            Data([0x0D, 0x0A, 0x0D, 0x0A]),
            Data([0x0A, 0x0A]),
            Data([0x0D, 0x0D]),
        ]
        let match = delimiters.compactMap { delimiter -> (range: Range<Data.Index>, size: Int)? in
            messageData.range(of: delimiter).map { ($0, delimiter.count) }
        }.min { lhs, rhs in
            if lhs.range.lowerBound != rhs.range.lowerBound {
                return lhs.range.lowerBound < rhs.range.lowerBound
            }
            return lhs.size > rhs.size
        }

        guard let match else { return (Data(), messageData) }
        return (
            Data(messageData[..<match.range.lowerBound]),
            Data(messageData[match.range.upperBound...])
        )
    }

    static func canonicalCRLF(_ text: String) -> String {
        var output = text.replacingOccurrences(of: "\r\n", with: "\n")
        output = output.replacingOccurrences(of: "\r", with: "\n")
        return output.replacingOccurrences(of: "\n", with: crlf)
    }

    private static func foldedHeaderLines(in headerBlock: String) -> [String] {
        var result: [String] = []
        for line in headerBlock.components(separatedBy: crlf) {
            if let first = line.first, first == " " || first == "\t", !result.isEmpty {
                result[result.count - 1] += crlf + line
            } else if !line.isEmpty {
                result.append(line)
            }
        }
        return result
    }

    private static func headerName(_ header: String) -> String {
        guard let colon = header.firstIndex(of: ":") else { return header }
        return String(header[header.startIndex ..< colon])
    }
}

enum MIMESecurityAssembler {
    static func message(topHeaderLines: [String], entity: Data) -> Data {
        let header = topHeaderLines.isEmpty
            ? ""
            : topHeaderLines.joined(separator: MIMEEntitySplit.crlf) + MIMEEntitySplit.crlf
        return Data(header.utf8) + entity
    }
}

enum OutboundAddressNormalizer {
    static func normalize(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let address: String
        if let start = trimmed.lastIndex(of: "<"),
           let end = trimmed[start...].firstIndex(of: ">") {
            address = String(trimmed[trimmed.index(after: start) ..< end])
        } else {
            address = trimmed
        }
        return address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
