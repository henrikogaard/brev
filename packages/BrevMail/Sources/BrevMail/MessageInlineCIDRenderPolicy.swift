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

struct MessageInlineCIDImagePayload: Equatable, Sendable {
    let contentID: String
    let mimeType: String
    let data: Data
}

enum MessageInlineCIDRenderPolicy {
    static func rewriteCIDImageSources(
        in html: String,
        payloads: [MessageInlineCIDImagePayload]
    ) -> String {
        var payloadsByContentID: [String: MessageInlineCIDImagePayload] = [:]
        for payload in payloads where payload.mimeType.lowercased().hasPrefix("image/") {
            let contentID = normalizedContentID(payload.contentID)
            if payloadsByContentID[contentID] == nil {
                payloadsByContentID[contentID] = payload
            }
        }
        guard !payloadsByContentID.isEmpty else { return html }
        let pattern = #"(\bsrc\s*=\s*["'])cid:([^"']+)(["'])"#
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return html
        }

        var rewritten = html
        let matches = expression.matches(
            in: html,
            range: NSRange(html.startIndex..., in: html)
        )
        for match in matches.reversed() {
            guard let fullRange = Range(match.range(at: 0), in: rewritten),
                  let prefixRange = Range(match.range(at: 1), in: html),
                  let cidRange = Range(match.range(at: 2), in: html),
                  let suffixRange = Range(match.range(at: 3), in: html)
            else {
                continue
            }
            let cid = normalizedContentID(String(html[cidRange]))
            guard let payload = payloadsByContentID[cid] else { continue }
            let replacement = String(html[prefixRange])
                + dataURL(for: payload)
                + String(html[suffixRange])
            rewritten.replaceSubrange(fullRange, with: replacement)
        }
        return rewritten
    }

    static func payloads(
        from attachments: [Attachment],
        download: (Attachment) async throws -> Data
    ) async -> [MessageInlineCIDImagePayload] {
        var payloads: [MessageInlineCIDImagePayload] = []
        for attachment in attachments where attachment.isInline {
            guard let contentID = attachment.contentID,
                  attachment.mimeType.lowercased().hasPrefix("image/"),
                  attachment.resource != nil
            else {
                continue
            }
            guard let data = try? await download(attachment) else {
                continue
            }
            payloads.append(MessageInlineCIDImagePayload(
                contentID: contentID,
                mimeType: attachment.mimeType,
                data: data
            ))
        }
        return payloads
    }

    static func rewriteCIDImageSources(
        in html: String?,
        attachments: [Attachment],
        download: (Attachment) async throws -> Data
    ) async -> String? {
        guard let html else { return nil }
        guard html.range(of: "cid:", options: [.caseInsensitive]) != nil else { return html }
        let payloads = await payloads(from: attachments, download: download)
        return rewriteCIDImageSources(in: html, payloads: payloads)
    }

    private static func dataURL(for payload: MessageInlineCIDImagePayload) -> String {
        let mimeType = sanitizedImageMIMEType(payload.mimeType)
        return "data:\(mimeType);base64,\(payload.data.base64EncodedString())"
    }

    private static func normalizedContentID(_ contentID: String) -> String {
        var normalized = (contentID.removingPercentEncoding ?? contentID)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("<") {
            normalized.removeFirst()
        }
        if normalized.hasSuffix(">") {
            normalized.removeLast()
        }
        return normalized.lowercased()
    }

    private static func sanitizedImageMIMEType(_ mimeType: String) -> String {
        let trimmed = mimeType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-+./")
        guard trimmed.hasPrefix("image/"),
              !trimmed.isEmpty,
              trimmed.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else {
            return "image/png"
        }
        return trimmed
    }
}
