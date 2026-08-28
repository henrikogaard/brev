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
import BrevDesign
import Foundation

struct MessageListStatus: Equatable, Sendable {
    let title: String
    let icon: String
    let subtitle: String
    let actionTitle: String?
}

struct MessageListFooterStatus: Equatable, Sendable {
    let message: String
    let actionTitle: String
}

struct MessageListSectionHeaderPresentation: Equatable, Sendable {
    enum Style: Equatable, Sendable {
        case date
        case pinned
    }

    let title: String
    let icon: String?
    let style: Style
}

struct MessageListChromePresentation: Equatable, Sendable {
    let clearsSystemRowBackgrounds: Bool
    let rendersDateHeadersAsRows: Bool
}

struct MessageListFolderStats: Equatable, Sendable {
    let folderName: String
    let totalCount: Int
    let unreadCount: Int
    let loadedCount: Int
    let visibleCount: Int
    let pinnedCount: Int
    let isThreaded: Bool
    let isConstrained: Bool
}

struct MessageListFolderStatsFooterPresentation: Equatable, Sendable {
    let text: String
    let accessibilityLabel: String
}

enum MessageListPresentation {
    private static let maximumPreviewLength = 240

    static let listChrome = MessageListChromePresentation(
        clearsSystemRowBackgrounds: true,
        rendersDateHeadersAsRows: true
    )

    static func sectionHeader(title: String) -> MessageListSectionHeaderPresentation {
        if title == "Pinned" {
            return MessageListSectionHeaderPresentation(
                title: "PINNED",
                icon: "pin.fill",
                style: .pinned
            )
        }
        return MessageListSectionHeaderPresentation(
            title: title,
            icon: nil,
            style: .date
        )
    }

    /// Produces a short, human-readable line from potentially raw listing text.
    ///
    /// Snippets fetched by older builds were cached with MIME plumbing still
    /// in them (part headers, boundary params, CSS rules, template merge
    /// tags), and the cache never re-fetches a message's snippet — so those
    /// artifacts also have to be scrubbed here, at display time, where every
    /// row passes through regardless of when it was fetched.
    /// The scrub below is ~15 regex passes, and rows re-render on every
    /// list invalidation (selection, hover, new mail), so results are
    /// memoized on the raw inputs. Snippets are immutable once fetched;
    /// identical inputs always share an entry.
    private static let previewTextCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 4096
        return cache
    }()

    // Snippet cleanup runs for each visible row. Compile the patterns once so
    // row re-renders only pay for matching and replacement, not ICU regex
    // construction as well.
    private static let mimeFragmentRegex = makeRegex(
        #"(?i)[\w.=-]*(content-(type|transfer-encoding|disposition|id)|mime-version)\s*:\s*\S+(\s*;\s*\S+)*"#
    )
    private static let boundaryParameterRegex = makeRegex(#"(?i)\b(boundary|charset)=("[^"]*"|\S+)"#)
    private static let contentDescriptionRegex = makeRegex(#"(?i)content-description\s*:"#)
    private static let multipartDescriptionRegex = makeRegex(
        #"(?i)this is a multi-?part message in mime format\.?"#
    )
    private static let mergeTagRegex = makeRegex(#"\*\|[A-Za-z0-9_:]+\|\*"#)
    private static let cssRuleRegex = makeRegex(#"(?:[#.@\w!:,%-]+\s+){0,4}[#.@\w!:,%-]*\{[^{}]*\}"#)
    private static let styleBlockRegex = makeRegex(#"(?is)<style[^>]*>.*?</style>"#)
    private static let scriptBlockRegex = makeRegex(#"(?is)<script[^>]*>.*?</script>"#)
    private static let tagRegex = makeRegex(#"</?[A-Za-z][^>]*>"#)
    private static let declarationRegex = makeRegex(#"(?s)<![^>]*>"#)
    private static let truncatedTagRegex = makeRegex(#"(?s)<[^>]*\z"#)
    private static let whitespaceRegex = makeRegex(#"\s+"#)
    private static let brandLinkRegex = makeRegex(#"^[\w.&'’-]{1,30}\s*\(\s*https?://[^)\s]*\s*\)\s*"#)
    private static let quotedPrintableRegex = makeRegex(#"(?:=[89A-F][0-9A-F])+"#)

    private static func makeRegex(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            preconditionFailure("Invalid snippet cleanup regex: \(pattern)")
        }
    }

    private static func replacing(
        _ text: String,
        using regex: NSRegularExpression,
        with template: String
    ) -> String {
        regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: template
        )
    }

    static func previewText(from snippet: String, subject: String = "") -> String {
        let key = "\(subject)\u{1F}\(snippet)" as NSString
        if let cached = previewTextCache.object(forKey: key) {
            return cached as String
        }
        let computed = computePreviewText(from: snippet, subject: subject)
        previewTextCache.setObject(computed as NSString, forKey: key)
        return computed
    }

    private static func computePreviewText(from snippet: String, subject: String) -> String {
        // Older builds cached snippets before quoted-printable decoding, so
        // escapes like "p=E5" ("på") survive in the cache.
        let decodedEscapes = decodingQuotedPrintableEscapes(in: snippet)
        // Base64 body runs (encoded parts captured by the peek, or cached by
        // older builds) decode into markup the steps below strip.
        let decodedRuns = SnippetBase64RunDecoder.decodingBase64Runs(in: decodedEscapes)
        let withoutMIMEFragments = replacing(
            replacing(
                replacing(
                    replacing(
                        replacing(
                            replacing(decodedRuns, using: mimeFragmentRegex, with: " "),
                            using: boundaryParameterRegex,
                            with: " "
                        ),
                        using: contentDescriptionRegex,
                        with: " "
                    ),
                    using: multipartDescriptionRegex,
                    with: " "
                ),
                using: mergeTagRegex,
                with: " "
            ),
            using: cssRuleRegex,
            with: " "
        )
        let withoutStyleBlocks = replacing(withoutMIMEFragments, using: styleBlockRegex, with: " ")
        let withoutNonContentMarkup = replacing(withoutStyleBlocks, using: scriptBlockRegex, with: " ")
        // Doctype declarations and comments start with punctuation, not a
        // letter, so the tag pattern above leaves them behind. A snippet cut
        // mid-tag has no closing bracket left to match.
        let withoutTags = replacing(
            replacing(
                replacing(withoutNonContentMarkup, using: tagRegex, with: " "),
                using: declarationRegex,
                with: " "
            ),
            using: truncatedTagRegex,
            with: " "
        )
        let decodedEntities = withoutTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
        let collapsed = replacing(decodedEntities, using: whitespaceRegex, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Newsletters open with a brand link row and often repeat the
        // subject before any prose; the row already shows the subject.
        let withoutBrandLink = replacing(collapsed, using: brandLinkRegex, with: "")
        let withoutSubjectEcho = droppingSubjectEcho(from: withoutBrandLink, subject: subject)
        return String(withoutSubjectEcho.prefix(maximumPreviewLength))
    }

    /// Decodes runs of high-bit quoted-printable escape pairs (`=E5`,
    /// `=C3=A5`), keeping a run only when it decodes to letters — so
    /// hex-looking prose ("id=AB123") decodes to punctuation and stays
    /// untouched. UTF-8 is tried first, then Windows-1252 for legacy
    /// single-byte encodings.
    private static func decodingQuotedPrintableEscapes(in text: String) -> String {
        guard text.contains("=") else {
            return text
        }
        let nsText = text as NSString
        var result = ""
        var cursor = 0
        for match in quotedPrintableRegex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            result += nsText.substring(
                with: NSRange(location: cursor, length: match.range.location - cursor)
            )
            let run = nsText.substring(with: match.range)
            result += decodedEscapeRun(run) ?? run
            cursor = match.range.location + match.range.length
        }
        result += nsText.substring(from: cursor)
        return result
    }

    private static func decodedEscapeRun(_ run: String) -> String? {
        let bytes = run.split(separator: "=").compactMap { UInt8($0, radix: 16) }
        guard !bytes.isEmpty else { return nil }
        guard let decoded = String(bytes: bytes, encoding: .utf8)
            ?? String(bytes: bytes, encoding: .windowsCP1252),
            !decoded.isEmpty,
            decoded.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) })
        else {
            return nil
        }
        return decoded
    }

    private static func droppingSubjectEcho(from text: String, subject: String) -> String {
        let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSubject.isEmpty,
              let range = text.range(of: trimmedSubject, options: [.caseInsensitive, .anchored])
        else {
            return text
        }
        let remainder = String(text[range.upperBound...])
            .trimmingCharacters(in: CharacterSet(charactersIn: " \u{2013}\u{2014}-:|\u{2022}"))
        return remainder.isEmpty ? text : remainder
    }

    static func loadErrorMessage(for error: any Error) -> String {
        localizedMessage(for: error, fallback: "Couldn't load messages.")
    }

    static func searchErrorMessage(for error: any Error) -> String {
        localizedMessage(for: error, fallback: "Couldn't run search.")
    }

    static func loadMoreErrorStatus(for error: any Error) -> MessageListFooterStatus {
        MessageListFooterStatus(
            message: localizedMessage(for: error, fallback: "Couldn't load more messages."),
            actionTitle: "Try Again"
        )
    }

    static func partialLoadErrorStatus(for error: any Error) -> MessageListFooterStatus {
        MessageListFooterStatus(
            message: "Some mailboxes couldn't load. \(loadErrorMessage(for: error))",
            actionTitle: "Try Again"
        )
    }

    static func mutationErrorStatus(for error: any Error) -> MessageListFooterStatus {
        MessageListFooterStatus(
            message: localizedMessage(for: error, fallback: "Couldn't update message."),
            actionTitle: "Refresh"
        )
    }

    static func noFolderStatus() -> MessageListStatus {
        MessageListStatus(
            title: "No folder selected",
            icon: "folder",
            subtitle: "Choose a folder from the sidebar.",
            actionTitle: nil
        )
    }

    static func errorStatus(_ message: String) -> MessageListStatus {
        MessageListStatus(
            title: "Something went wrong",
            icon: "exclamationmark.triangle",
            subtitle: message,
            actionTitle: "Try Again"
        )
    }

    static func emptyStatus(searchText: String) -> MessageListStatus {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return MessageListStatus(
                title: "No messages",
                icon: "tray",
                subtitle: "Messages you receive will appear here.",
                actionTitle: nil
            )
        }
        return MessageListStatus(
            title: "No messages",
            icon: "magnifyingglass",
            subtitle: "No results for \"\(query)\".",
            actionTitle: "Clear search"
        )
    }

    static func folderStatsFooter(
        _ stats: MessageListFolderStats,
        detail: MailboxFolderStatsDetail
    ) -> MessageListFolderStatsFooterPresentation {
        let parts: [String]
        switch detail {
        case .compact:
            parts = compactFolderStatsParts(stats)
        case .detailed:
            parts = detailedFolderStatsParts(stats)
        }
        let accessibilityParts = parts.first == stats.folderName
            ? parts
            : [stats.folderName] + parts
        return MessageListFolderStatsFooterPresentation(
            text: parts.joined(separator: " · "),
            accessibilityLabel: accessibilityParts.joined(separator: ", ")
        )
    }

    private static func localizedMessage(for error: any Error, fallback: String) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? fallback : message
    }

    private static func compactFolderStatsParts(_ stats: MessageListFolderStats) -> [String] {
        if stats.isConstrained {
            return [
                "\(stats.visibleCount) shown",
                "\(stats.totalCount) total",
                countPhrase(stats.unreadCount, singular: "unread", plural: "unread")
            ]
        }
        return [
            countPhrase(stats.totalCount, singular: "message", plural: "messages"),
            countPhrase(stats.unreadCount, singular: "unread", plural: "unread")
        ]
    }

    private static func detailedFolderStatsParts(_ stats: MessageListFolderStats) -> [String] {
        [
            stats.folderName,
            shownPhrase(stats),
            "\(stats.totalCount) total",
            countPhrase(stats.unreadCount, singular: "unread", plural: "unread"),
            countPhrase(stats.pinnedCount, singular: "pinned", plural: "pinned"),
            "\(stats.loadedCount) loaded"
        ]
    }

    private static func shownPhrase(_ stats: MessageListFolderStats) -> String {
        let noun = stats.isThreaded ? "thread" : "message"
        let plural = stats.isThreaded ? "threads" : "messages"
        return "\(stats.visibleCount) \(stats.visibleCount == 1 ? noun : plural) shown"
    }

    private static func countPhrase(
        _ count: Int,
        singular: String,
        plural: String
    ) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }
}
