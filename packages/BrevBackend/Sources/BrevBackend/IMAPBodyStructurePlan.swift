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

struct IMAPBodyStructurePart: Sendable, Equatable {
    let section: String
    let mimeType: String
    let transferEncoding: String
    let sizeBytes: Int
    let charset: String?
    let name: String?
    let isInline: Bool
    let contentID: String?
}

struct IMAPBodyStructurePlan: Sendable, Equatable {
    let plainTextPart: IMAPBodyStructurePart?
    let htmlPart: IMAPBodyStructurePart?
    let readReceiptPart: IMAPBodyStructurePart?
    let attachments: [IMAPBodyStructurePart]

    static func parse(fetchResponses: [String], uid: Int) -> IMAPBodyStructurePlan? {
        guard let response = fetchResponses.first(where: {
            Self.containsUID(uid, in: $0)
                && $0.range(of: "BODYSTRUCTURE", options: .caseInsensitive) != nil
        }),
            let marker = response.range(of: "BODYSTRUCTURE", options: .caseInsensitive)
        else { return nil }

        var parser = IMAPSExpressionParser(String(response[marker.upperBound...]))
        guard case .list(let root)? = parser.parseValue() else { return nil }
        var builder = Builder()
        guard builder.consume(.list(root), section: "") else { return nil }
        return IMAPBodyStructurePlan(
            plainTextPart: builder.plainTextPart,
            htmlPart: builder.htmlPart,
            readReceiptPart: builder.readReceiptPart,
            attachments: builder.attachments
        )
    }

    private static func containsUID(_ uid: Int, in response: String) -> Bool {
        guard let marker = response.range(of: "UID ", options: .caseInsensitive) else { return false }
        var end = marker.upperBound
        while end < response.endIndex, response[end].isNumber {
            response.formIndex(after: &end)
        }
        return response[marker.upperBound ..< end] == Substring(String(uid))
    }

    private struct Builder {
        var plainTextPart: IMAPBodyStructurePart?
        var htmlPart: IMAPBodyStructurePart?
        var readReceiptPart: IMAPBodyStructurePart?
        var attachments: [IMAPBodyStructurePart] = []

        mutating func consume(_ value: IMAPSExpressionValue, section: String) -> Bool {
            guard case .list(let values) = value, !values.isEmpty else { return false }
            if case .list = values[0] {
                return consumeMultipart(values, section: section)
            }
            return consumeLeaf(values, section: section)
        }

        private mutating func consumeMultipart(
            _ values: [IMAPSExpressionValue],
            section: String
        ) -> Bool {
            var childCount = 0
            while childCount < values.count {
                guard case .list = values[childCount] else { break }
                childCount += 1
            }
            guard childCount > 0,
                  values.indices.contains(childCount),
                  let subtype = values[childCount].stringValue?.lowercased(),
                  subtype != "signed",
                  subtype != "encrypted"
            else { return false }

            for childIndex in 0 ..< childCount {
                let childSection: String
                if section.isEmpty {
                    childSection = "\(childIndex + 1)"
                } else {
                    childSection = "\(section).\(childIndex + 1)"
                }
                guard consume(values[childIndex], section: childSection) else { return false }
            }
            return true
        }

        private mutating func consumeLeaf(
            _ values: [IMAPSExpressionValue],
            section: String
        ) -> Bool {
            guard values.count >= 7,
                  let type = values[0].stringValue?.lowercased(),
                  let subtype = values[1].stringValue?.lowercased(),
                  let encoding = values[5].stringValue?.lowercased(),
                  let sizeText = values[6].stringValue,
                  let size = Int(sizeText)
            else { return false }

            let resolvedSection = section.isEmpty ? "1" : section
            let mimeType = "\(type)/\(subtype)"
            if mimeType == "message/rfc822"
                || mimeType == "application/pkcs7-mime"
                || mimeType == "application/x-pkcs7-mime" {
                return false
            }

            let contentParameters = Self.parameters(values[2])
            let disposition = Self.disposition(in: values.dropFirst(7))
            let dispositionParameters = disposition.map { Self.parameters($0.parameters) } ?? [:]
            let name = dispositionParameters["filename"] ?? contentParameters["name"]
            let contentID = values[3].stringValue?
                .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            let isInline = disposition?.kind == "inline"
            let part = IMAPBodyStructurePart(
                section: resolvedSection,
                mimeType: mimeType,
                transferEncoding: encoding,
                sizeBytes: size,
                charset: contentParameters["charset"],
                name: name,
                isInline: isInline,
                contentID: contentID
            )

            let isAttachment = disposition?.kind == "attachment"
                || name != nil
                || (type != "text" && mimeType != "message/disposition-notification")
            if isAttachment {
                attachments.append(part)
            } else if mimeType == "text/plain", plainTextPart == nil {
                plainTextPart = part
            } else if mimeType == "text/html", htmlPart == nil {
                htmlPart = part
            } else if mimeType == "message/disposition-notification", readReceiptPart == nil {
                readReceiptPart = part
            }
            return true
        }

        private static func parameters(_ value: IMAPSExpressionValue) -> [String: String] {
            guard case .list(let values) = value else { return [:] }
            var result: [String: String] = [:]
            var index = 0
            while index + 1 < values.count {
                if let key = values[index].stringValue?.lowercased(),
                   let parameterValue = values[index + 1].stringValue {
                    result[key] = parameterValue
                }
                index += 2
            }
            return result
        }

        private static func disposition(
            in values: ArraySlice<IMAPSExpressionValue>
        ) -> (kind: String, parameters: IMAPSExpressionValue)? {
            for value in values {
                guard case .list(let fields) = value,
                      fields.count >= 2,
                      let kind = fields[0].stringValue?.lowercased(),
                      kind == "inline" || kind == "attachment"
                else { continue }
                return (kind, fields[1])
            }
            return nil
        }
    }
}

struct IMAPMessagePartReference: Sendable, Equatable {
    private static let prefix = "imap-part:"

    let messageID: MessageHeader.ID
    let section: String
    let transferEncoding: String

    var resource: String {
        let encodedID = Data(messageID.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "\(Self.prefix)\(encodedID):\(section):\(transferEncoding)"
    }

    init(messageID: MessageHeader.ID, section: String, transferEncoding: String) {
        self.messageID = messageID
        self.section = section
        self.transferEncoding = transferEncoding
    }

    init(resource: String) throws {
        guard resource.hasPrefix(Self.prefix) else { throw ParseError.invalidResource }
        let fields = resource.dropFirst(Self.prefix.count).split(separator: ":", omittingEmptySubsequences: false)
        guard fields.count == 3,
              !fields[0].isEmpty,
              fields[1].allSatisfy({ $0.isNumber || $0 == "." }),
              !fields[2].isEmpty
        else { throw ParseError.invalidResource }
        var base64 = String(fields[0])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let messageID = String(data: data, encoding: .utf8),
              !messageID.isEmpty
        else { throw ParseError.invalidResource }
        self.messageID = messageID
        section = String(fields[1])
        transferEncoding = String(fields[2]).lowercased()
    }

    enum ParseError: Error {
        case invalidResource
    }
}
