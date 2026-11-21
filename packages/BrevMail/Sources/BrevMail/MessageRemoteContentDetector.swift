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

/// Message HTML after tracking images were removed (#299).
struct MessageTrackerStripResult: Equatable, Sendable {
    let html: String
    let removedCount: Int
}

/// Hosts that serve only open-tracking images, shipped with the app so no
/// list is fetched (ADR-0006). Matches the host or any subdomain of it.
enum MessageKnownTrackerHosts {
    static let hosts: Set<String> = [
        "mailtrack.io",
        "t.yesware.com",
        "getnotify.com",
        "bananatag.com",
    ]

    static func contains(_ host: String) -> Bool {
        let host = host.lowercased()
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
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

    private final class CachedStrip {
        let result: MessageTrackerStripResult
        init(_ result: MessageTrackerStripResult) { self.result = result }
    }

    private static let stripCache: NSCache<NSString, CachedStrip> = {
        let cache = NSCache<NSString, CachedStrip>()
        cache.countLimit = 64
        return cache
    }()

    /// The message HTML with likely tracking images removed, and how many
    /// were removed (#299). Used when remote content is allowed, so a sender
    /// still can't tell when the message was opened. Uses the same tracker
    /// test as the blocked-content banner; normal images stay untouched.
    static func strippingLikelyTrackers(_ html: String) -> MessageTrackerStripResult {
        let key = html as NSString
        if let cached = stripCache.object(forKey: key) {
            return cached.result
        }
        let result = uncachedStrippingLikelyTrackers(html)
        stripCache.setObject(CachedStrip(result), forKey: key)
        return result
    }

    private static func uncachedStrippingLikelyTrackers(_ html: String) -> MessageTrackerStripResult {
        guard let elementRegex = elementAssetRegexes.first else {
            return MessageTrackerStripResult(html: html, removedCount: 0)
        }
        let fullRange = NSRange(html.startIndex ..< html.endIndex, in: html)
        var trackerRanges: [NSRange] = []
        for match in elementRegex.matches(in: html, range: fullRange) {
            guard match.numberOfRanges > 4,
                  let elementRange = Range(match.range(at: 0), in: html),
                  let tagRange = Range(match.range(at: 1), in: html),
                  html[tagRange].lowercased() == "img" else {
                continue
            }
            // Every src-like attribute counts: a pixel can sit on `src`
            // behind a harmless `data-src`.
            let elementHTML = String(html[elementRange])
            var assets: [RemoteAsset] = []
            for value in imageSourceValues(in: elementHTML) {
                collectAssets(fromAttributeValue: value, tagName: "img", elementHTML: elementHTML, into: &assets)
            }
            if assets.contains(where: \.isLikelyTracker) {
                trackerRanges.append(match.range(at: 0))
            }
        }
        guard !trackerRanges.isEmpty else {
            return MessageTrackerStripResult(html: html, removedCount: 0)
        }
        let stripped = NSMutableString(string: html)
        for range in trackerRanges.reversed() {
            stripped.replaceCharacters(in: range, with: "")
        }
        return MessageTrackerStripResult(html: stripped as String, removedCount: trackerRanges.count)
    }

    private static let imageSourceAttributeRegex = try? NSRegularExpression(
        pattern: #"\b(?:src|srcset)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^'">\s]+))"#,
        options: [.caseInsensitive]
    )

    private static func imageSourceValues(in elementHTML: String) -> [String] {
        guard let regex = imageSourceAttributeRegex else { return [] }
        let range = NSRange(elementHTML.startIndex ..< elementHTML.endIndex, in: elementHTML)
        return regex.matches(in: elementHTML, range: range).compactMap {
            firstCapturedString(in: $0, source: elementHTML, ranges: [1, 2, 3])
        }
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
               Self.urlLooksTracker(urlText) || MessageKnownTrackerHosts.contains(host) {
                return true
            }
            return false
        }

        private static func imageLooksHiddenOrTiny(_ html: String) -> Bool {
            let lower = html.lowercased()
            let width = numericAttribute("width", in: lower)
            let height = numericAttribute("height", in: lower)
            if width.map({ $0 <= 1 }) == true, height.map({ $0 <= 1 }) == true {
                return true
            }
            if let cssWidth = cssPixelSize("width", in: lower), let cssHeight = cssPixelSize("height", in: lower),
               cssWidth <= 1, cssHeight <= 1 {
                return true
            }
            // Fully transparent images are never shown, whatever their size.
            if isFullyTransparent(lower) {
                return true
            }
            // A hidden image given a real size is usually a responsive
            // variant a media query shows on narrow screens, not a pixel.
            let hasRealSize = (width ?? 0) > 1 || (height ?? 0) > 1
            return !hasRealSize && (
                lower.contains("display:none")
                    || lower.contains("display: none")
                    || lower.contains("visibility:hidden")
                    || lower.contains("visibility: hidden")
            )
        }

        /// An inline-CSS `width`/`height` in px (or unitless 0), ignoring
        /// `max-`/`min-` variants.
        private static func cssPixelSize(_ property: String, in html: String) -> Double? {
            let pattern = #"(?<![-a-z])\#(property)\s*:\s*(\d+(?:\.\d+)?)(px|%)?(?![\w.%])\s*(!\s*important)?"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            // CSS comments are not declarations, and may sit inside `!important`.
            let html = html.replacingOccurrences(of: #"/\*.*?\*/"#, with: "", options: .regularExpression)
            let range = NSRange(html.startIndex ..< html.endIndex, in: html)
            // As in the browser: the last `!important` declaration wins,
            // otherwise the last declaration.
            let matches = regex.matches(in: html, range: range)
            let important = matches.last { $0.range(at: 3).location != NSNotFound }
            guard let match = important ?? matches.last,
                  let valueRange = Range(match.range(at: 1), in: html),
                  let value = Double(html[valueRange]) else { return nil }
            // px counts as-is; `0`, `0px` and `0%` are all zero; any other
            // unit or percentage is not a known pixel size.
            let unit = Range(match.range(at: 2), in: html).map { String(html[$0]) }
            return unit == "px" || value == 0 ? value : nil
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

        // `opacity:0` or `opacity: 0.0`, but not `opacity:0.8`: these images
        // are now removed, so a faded content image must not match (#299).
        private static let transparentOpacityRegex = try? NSRegularExpression(
            pattern: #"(?<![-a-z])opacity\s*:\s*0+(?:\.0*)?(?![0-9.])"#
        )

        private static func isFullyTransparent(_ html: String) -> Bool {
            guard let regex = transparentOpacityRegex else { return false }
            return regex.firstMatch(in: html, range: NSRange(html.startIndex ..< html.endIndex, in: html)) != nil
        }

        /// Open-tracking paths and file names only. Query strings and loose
        /// words are not checked: a `utm_` campaign tag or a `/tracks/` path
        /// sits on ordinary content images, which are now removed when
        /// matched (#299).
        private static func urlLooksTracker(_ urlText: String) -> Bool {
            let path = (URLComponents(string: urlText)?.path ?? urlText).lowercased()
            // Whole path segments and file names only, so `beacon-hill.jpg`
            // or `/track/opening-night.jpg` stay.
            let segments = path.split(separator: "/").map(String.init)
            if let fileName = segments.last,
               ["open.gif", "open.png", "pixel.gif", "pixel.png", "beacon.gif", "beacon.png"].contains(fileName) {
                return true
            }
            if segments.contains("beacon") {
                return true
            }
            // `/track/open`, `/track/open.php`, `/wf/open.aspx`: the open
            // endpoint itself, with no extension or a server-script one.
            let openEndpoints: Set<String> = [
                "open", "open.php", "open.aspx", "open.ashx", "open.asp", "open.jsp", "open.cgi",
            ]
            return zip(segments, segments.dropFirst()).contains { pair in
                (pair.0 == "track" || pair.0 == "wf") && openEndpoints.contains(pair.1)
            }
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
        // WebKit decodes entities before loading, so `&#104;ttps://` is a
        // remote URL too.
        for candidate in decodingHTMLEntities(value).components(separatedBy: ",") {
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

    private static let numericEntityRegex = try? NSRegularExpression(
        pattern: #"&#(x[0-9a-f]+|[0-9]+);?"#,
        options: [.caseInsensitive]
    )

    /// Decodes the entities that can disguise a URL scheme or host:
    /// numeric ones and `&amp;`, `&colon;`, `&sol;`, `&period;`.
    private static func decodingHTMLEntities(_ value: String) -> String {
        guard value.contains("&") else { return value }
        var decoded = value
        if let regex = numericEntityRegex {
            let ns = decoded as NSString
            let matches = regex.matches(in: decoded, range: NSRange(location: 0, length: ns.length))
            let mutable = NSMutableString(string: decoded)
            for match in matches.reversed() {
                let code = ns.substring(with: match.range(at: 1)).lowercased()
                let scalarValue = code.hasPrefix("x") ? UInt32(code.dropFirst(), radix: 16) : UInt32(code)
                guard let scalarValue, let scalar = Unicode.Scalar(scalarValue) else { continue }
                mutable.replaceCharacters(in: match.range, with: String(Character(scalar)))
            }
            decoded = mutable as String
        }
        for (entity, character) in [("&colon;", ":"), ("&sol;", "/"), ("&period;", "."), ("&amp;", "&")] {
            decoded = decoded.replacingOccurrences(of: entity, with: character, options: .caseInsensitive)
        }
        return decoded
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
