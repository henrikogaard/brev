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

enum RFC2047HeaderDecoder {
    static func decode(_ value: String) -> String {
        var output = ""
        var index = value.startIndex
        var previousTokenWasEncoded = false

        while let marker = value.range(of: "=?", range: index ..< value.endIndex) {
            let prefix = String(value[index ..< marker.lowerBound])
            if !(previousTokenWasEncoded && prefix.allSatisfy(\.isWhitespace)) {
                output += prefix
            }

            guard let token = parseToken(in: value, at: marker.lowerBound) else {
                output += "=?"
                index = marker.upperBound
                previousTokenWasEncoded = false
                continue
            }

            output += token.decoded
            index = token.endIndex
            previousTokenWasEncoded = true
        }

        output += String(value[index...])
        return output
    }

    private static func parseToken(
        in value: String,
        at start: String.Index
    ) -> (decoded: String, endIndex: String.Index)? {
        let charsetStart = value.index(start, offsetBy: 2)
        guard let charsetEnd = value.range(of: "?", range: charsetStart ..< value.endIndex)?.lowerBound else {
            return nil
        }
        let encodingStart = value.index(after: charsetEnd)
        guard let encodingEnd = value.range(of: "?", range: encodingStart ..< value.endIndex)?.lowerBound else {
            return nil
        }
        let textStart = value.index(after: encodingEnd)
        guard let terminator = value.range(of: "?=", range: textStart ..< value.endIndex) else {
            return nil
        }

        let charset = String(value[charsetStart ..< charsetEnd])
        let encoding = String(value[encodingStart ..< encodingEnd]).uppercased()
        let encodedText = String(value[textStart ..< terminator.lowerBound])
        let rawToken = String(value[start ..< terminator.upperBound])

        guard let data = decodedData(encodedText, encoding: encoding),
              let decoded = String(data: data, encoding: MIMECharset.encoding(for: charset))
              ?? String(data: data, encoding: .utf8)
              ?? String(data: data, encoding: .isoLatin1)
        else {
            return (rawToken, terminator.upperBound)
        }

        return (decoded, terminator.upperBound)
    }

    private static func decodedData(_ value: String, encoding: String) -> Data? {
        switch encoding {
        case "B":
            let compact = value
                .components(separatedBy: .whitespacesAndNewlines)
                .joined()
            return Data(base64Encoded: compact)
        case "Q":
            return decodeQEncodedWord(value)
        default:
            return nil
        }
    }

    private static func decodeQEncodedWord(_ value: String) -> Data {
        let bytes = Array(value.utf8)
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)
        var index = 0

        while index < bytes.count {
            let byte = bytes[index]
            if byte == HeaderCharacterCode.underscore {
                output.append(HeaderCharacterCode.space)
                index += 1
                continue
            }
            if byte == HeaderCharacterCode.equals,
               index + 2 < bytes.count,
               let high = hexValue(bytes[index + 1]),
               let low = hexValue(bytes[index + 2]) {
                output.append((high << 4) | low)
                index += 3
                continue
            }

            output.append(byte)
            index += 1
        }

        return Data(output)
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case HeaderCharacterCode.zero ... HeaderCharacterCode.nine:
            byte - HeaderCharacterCode.zero
        case HeaderCharacterCode.uppercaseA ... HeaderCharacterCode.uppercaseF:
            byte - HeaderCharacterCode.uppercaseA + 10
        case HeaderCharacterCode.lowercaseA ... HeaderCharacterCode.lowercaseF:
            byte - HeaderCharacterCode.lowercaseA + 10
        default:
            nil
        }
    }
}

private enum HeaderCharacterCode {
    static let equals = UInt8(ascii: "=")
    static let underscore = UInt8(ascii: "_")
    static let space = UInt8(ascii: " ")
    static let zero = UInt8(ascii: "0")
    static let nine = UInt8(ascii: "9")
    static let uppercaseA = UInt8(ascii: "A")
    static let uppercaseF = UInt8(ascii: "F")
    static let lowercaseA = UInt8(ascii: "a")
    static let lowercaseF = UInt8(ascii: "f")
}
