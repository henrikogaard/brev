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

enum ComposeSignatureBodyPolicy {
    static func body(
        afterSelecting signatureBody: String?,
        in currentBody: String,
        replacing previousSignatureBody: String?
    ) -> String {
        let bodyWithoutPrevious = body(
            removing: previousSignatureBody,
            from: currentBody
        )
        guard let signatureBlock = signatureBlock(for: signatureBody) else {
            return bodyWithoutPrevious
        }
        guard !containsManagedSignatureBlock(signatureBlock, in: bodyWithoutPrevious) else {
            return bodyWithoutPrevious
        }
        return inserting(signatureBlock, into: bodyWithoutPrevious)
    }

    static func body(removing signatureBody: String?, from currentBody: String) -> String {
        guard let signatureBlock = signatureBlock(for: signatureBody) else {
            return currentBody
        }
        return removingManagedSignatureBlock(signatureBlock, from: currentBody)
    }

    static func managedSignatureBody(from signatureBody: String?) -> String? {
        let trimmed = signatureBody?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func signatureBlock(for signatureBody: String?) -> String? {
        guard let signatureBody = managedSignatureBody(from: signatureBody) else {
            return nil
        }
        return "\n\n-- \n\(signatureBody)"
    }

    private static func inserting(_ signatureBlock: String, into body: String) -> String {
        guard let quoteStart = quotedOriginalStart(in: body) else {
            return body + signatureBlock
        }
        return String(body[..<quoteStart]) + signatureBlock + String(body[quoteStart...])
    }

    private static func removingManagedSignatureBlock(
        _ signatureBlock: String,
        from body: String
    ) -> String {
        var searchRange = body.startIndex ..< body.endIndex
        while let range = body.range(of: signatureBlock, range: searchRange) {
            if range.upperBound == body.endIndex || quotedOriginalFollows(range.upperBound, in: body) {
                var updated = body
                updated.removeSubrange(range)
                return updated
            }
            searchRange = range.upperBound ..< body.endIndex
        }
        return body
    }

    private static func containsManagedSignatureBlock(
        _ signatureBlock: String,
        in body: String
    ) -> Bool {
        var searchRange = body.startIndex ..< body.endIndex
        while let range = body.range(of: signatureBlock, range: searchRange) {
            if range.upperBound == body.endIndex || quotedOriginalFollows(range.upperBound, in: body) {
                return true
            }
            searchRange = range.upperBound ..< body.endIndex
        }
        return false
    }

    private static func quotedOriginalFollows(_ index: String.Index, in body: String) -> Bool {
        let suffix = body[index...]
        return isReplyQuotePrefix(suffix) || isForwardedMessagePrefix(suffix)
    }

    private static func quotedOriginalStart(in body: String) -> String.Index? {
        let candidates = [
            replyQuoteStart(in: body),
            body.range(of: "\n\n---------- Forwarded message ----------")?.lowerBound
        ].compactMap { $0 }

        return candidates.min()
    }

    private static func replyQuoteStart(in body: String) -> String.Index? {
        var searchRange = body.startIndex ..< body.endIndex
        while let range = body.range(of: "\n\nOn ", range: searchRange) {
            let markerLineStart = body.index(range.lowerBound, offsetBy: 2)
            let markerLineEnd = body[markerLineStart...].firstIndex(of: "\n") ?? body.endIndex
            let markerLine = body[markerLineStart ..< markerLineEnd]
            if markerLine.range(of: " wrote:") != nil {
                return range.lowerBound
            }
            searchRange = range.upperBound ..< body.endIndex
        }
        return nil
    }

    private static func isReplyQuotePrefix(_ value: Substring) -> Bool {
        guard value.hasPrefix("\n\nOn ") else { return false }
        let markerLineStart = value.index(value.startIndex, offsetBy: 2)
        let markerLineEnd = value[markerLineStart...].firstIndex(of: "\n") ?? value.endIndex
        return value[markerLineStart ..< markerLineEnd].range(of: " wrote:") != nil
    }

    private static func isForwardedMessagePrefix(_ value: Substring) -> Bool {
        value.hasPrefix("\n\n---------- Forwarded message ----------")
    }
}
