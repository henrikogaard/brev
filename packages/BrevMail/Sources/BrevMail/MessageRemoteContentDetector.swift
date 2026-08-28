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

struct MessageRemoteContentAssetReport: Equatable, Sendable {
    let assetCount: Int
    let likelyTrackerCount: Int
    let hosts: [String]

    static let empty = MessageRemoteContentAssetReport(
        assetCount: 0,
        likelyTrackerCount: 0,
        hosts: []
    )

    var hasRemoteAssets: Bool {
        assetCount > 0
    }

    var hasLikelyTrackers: Bool {
        likelyTrackerCount > 0
    }
}

enum MessageRemoteContentDetector {
    static func hasRemoteAssets(_ html: String) -> Bool {
        remoteAssetReport(html).hasRemoteAssets
    }

    static func remoteAssetHosts(_ html: String) -> [String] {
        remoteAssetReport(html).hosts
    }

    /// Reports are pure functions of the document, and the reading pane
    /// derives one several times per render; each scan is three regex
    /// passes over the whole body, so results are memoized per document.
    private final class CachedReport {
        let report: MessageRemoteContentAssetReport
        init(_ report: MessageRemoteContentAssetReport) { self.report = report }
    }

    private static let reportCache: NSCache<NSString, CachedReport> = {
        let cache = NSCache<NSString, CachedReport>()
        cache.countLimit = 64
        return cache
    }()

    static func remoteAssetReport(_ html: String) -> MessageRemoteContentAssetReport {
        let key = html as NSString
        if let cached = reportCache.object(forKey: key) {
            return cached.report
        }
        let assets = remoteAssets(in: html)
        let report: MessageRemoteContentAssetReport = assets.isEmpty
            ? .empty
            : MessageRemoteContentAssetReport(
                assetCount: assets.count,
                likelyTrackerCount: assets.filter(\.isLikelyTracker).count,
                hosts: Set(assets.map(\.host)).sorted()
            )
        reportCache.setObject(CachedReport(report), forKey: key)
        return report
    }

    private struct RemoteAsset {
        let host: String
        let urlText: String
        let tagName: String?
        let elementHTML: String?

        var isLikelyTracker: Bool {
            let tag = tagName?.lowercased()
            if tag == "img",
               Self.imageLooksHiddenOrTiny(elementHTML ?? "") {
                return true
            }
            if tag == "img",
               Self.urlLooksTracker(urlText) {
                return true
            }
            return false
        }

        private static func imageLooksHiddenOrTiny(_ html: String) -> Bool {
            let lower = html.lowercased()
            if lower.contains("display:none")
                || lower.contains("display: none")
                || lower.contains("visibility:hidden")
                || lower.contains("visibility: hidden")
                || lower.contains("opacity:0")
                || lower.contains("opacity: 0") {
                return true
            }

            let width = numericAttribute("width", in: lower)
            let height = numericAttribute("height", in: lower)
            return width.map { $0 <= 1 } == true
                && height.map { $0 <= 1 } == true
        }

        private static func numericAttribute(_ name: String, in html: String) -> Int? {
            let pattern = #"\b\#(name)\s*=\s*(?:"(\d+)"|'(\d+)'|(\d+))"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return nil
            }
            let range = NSRange(html.startIndex ..< html.endIndex, in: html)
            guard let match = regex.firstMatch(in: html, range: range) else { return nil }
            for index in 1 ..< match.numberOfRanges {
                guard let valueRange = Range(match.range(at: index), in: html) else { continue }
                return Int(html[valueRange])
            }
            return nil
        }

        private static func urlLooksTracker(_ urlText: String) -> Bool {
            let lower = urlText.lowercased()
            return [
                "/track", "tracking", "tracker", "beacon", "open.gif", "open.png",
                "pixel.gif", "pixel.png", "utm_",
            ].contains { lower.contains($0) }
        }
    }

    // `attrScan` consumes tag attributes while treating quoted strings as
    // atomic, so a `>` inside a quoted attribute value (e.g.
    // `<img alt="a>b" src="https://tracker/x.gif">`) does NOT end the element
    // scan early. A plain `[^>]*` stopped at that `>`, never reached `src`,
    // and let a tracking pixel through the remote-content gate.
    private static let elementAssetRegexes: [NSRegularExpression] = {
        let attrScan = #"(?:[^>"']|"[^"]*"|'[^']*')"#
        return [
            #"<([a-z][a-z0-9:-]*)\b\#(attrScan)*?\b(?:src|srcset|poster|background)\s*=\s*(?:"([^"]+)"|'([^']+)'|([^'">\s]+))\#(attrScan)*>"#,
            #"<(link)\b\#(attrScan)*?\bhref\s*=\s*(?:"([^"]+)"|'([^']+)'|([^'">\s]+))\#(attrScan)*>"#,
        ].compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()

    private static func remoteAssets(in html: String) -> [RemoteAsset] {
        var assets: [RemoteAsset] = []
        for regex in elementAssetRegexes {
            collectElementAssets(regex, html: html, into: &assets)
        }
        collectCSSAssets(html: html, into: &assets)
        return assets
    }

    private static func collectElementAssets(
        _ regex: NSRegularExpression,
        html: String,
        into assets: inout [RemoteAsset]
    ) {
        let range = NSRange(html.startIndex ..< html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard match.numberOfRanges > 4,
                  let elementRange = Range(match.range(at: 0), in: html),
                  let tagRange = Range(match.range(at: 1), in: html),
                  let value = firstCapturedString(in: match, source: html, ranges: [2, 3, 4]) else {
                continue
            }
            collectAssets(
                fromAttributeValue: value,
                tagName: String(html[tagRange]),
                elementHTML: String(html[elementRange]),
                into: &assets
            )
        }
    }

    // Two remote-CSS forms: `url(...)` (covers `@import url(...)`), and the
    // string form `@import "https://…"` / `@import 'https://…'` which has no
    // `url()` wrapper and was previously missed, letting a remote stylesheet
    // (a tracker) load on the attributed-string render path.
    private static let cssAssetRegexes: [NSRegularExpression] = [
        #"url\(\s*["']?((?:https?:)?//[^"')\s]+)"#,
        #"@import\s+["']((?:https?:)?//[^"')\s]+)"#,
    ].compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    private static func collectCSSAssets(html: String, into assets: inout [RemoteAsset]) {
        let range = NSRange(html.startIndex ..< html.endIndex, in: html)
        for regex in cssAssetRegexes {
            for match in regex.matches(in: html, range: range) {
                guard let value = firstCapturedString(in: match, source: html, ranges: [1]) else { continue }
                collectAssets(
                    fromAttributeValue: value,
                    tagName: nil,
                    elementHTML: nil,
                    into: &assets
                )
            }
        }
    }

    private static func collectAssets(
        fromAttributeValue value: String,
        tagName: String?,
        elementHTML: String?,
        into assets: inout [RemoteAsset]
    ) {
        for candidate in value.components(separatedBy: ",") {
            guard let token = candidate
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: \.isWhitespace)
                .first
            else {
                continue
            }
            let urlText = String(token)
            if let host = remoteHost(from: urlText) {
                assets.append(RemoteAsset(
                    host: host,
                    urlText: normalizedRemoteURLString(urlText),
                    tagName: tagName,
                    elementHTML: elementHTML
                ))
            }
        }
    }

    private static func firstCapturedString(
        in match: NSTextCheckingResult,
        source: String,
        ranges: [Int]
    ) -> String? {
        for index in ranges {
            guard index < match.numberOfRanges,
                  let range = Range(match.range(at: index), in: source)
            else { continue }
            return String(source[range])
        }
        return nil
    }

    private static func remoteHost(from value: String) -> String? {
        URLComponents(string: normalizedRemoteURLString(value))?.host?.lowercased()
    }

    private static func normalizedRemoteURLString(_ value: String) -> String {
        let urlString: String
        if value.hasPrefix("//") {
            urlString = "https:\(value)"
        } else if value.lowercased().hasPrefix("http://") || value.lowercased().hasPrefix("https://") {
            urlString = value
        } else {
            return value
        }
        return urlString
    }
}
