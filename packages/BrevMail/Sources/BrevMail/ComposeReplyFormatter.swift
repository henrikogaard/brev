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

enum ComposeReplyQuotePlacement: String, Sendable {
    case belowReply
    case aboveReply

    static let storageKey = "compose.quotePlacement"

    static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let value = defaults.string(forKey: storageKey),
              let placement = Self(rawValue: value) else {
            return .belowReply
        }
        return placement
    }
}

/// Removes a leading run of reply/forward prefixes so threading doesn't
/// stack them ("Re: Re: X" replies as "Re: X"). The comparison is
/// case-insensitive and tolerant of a missing trailing space ("Re:X").
enum ComposeSubjectPrefixCollapser {
    static func stripping(_ subject: String, prefixes: [String]) -> String {
        var rest = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        while let match = prefixes.first(where: { rest.lowercased().hasPrefix($0) }) {
            rest = String(rest.dropFirst(match.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return rest
    }
}

enum ComposeReplyFormatter {
    /// Test seams: snapshot tests pin the attribution line's locale and time
    /// zone so the rendered text does not depend on the machine running them.
    static var localeOverride: Locale?
    static var timeZoneOverride: TimeZone?

    static var defaultLocale: Locale { localeOverride ?? .current }
    static var defaultTimeZone: TimeZone { timeZoneOverride ?? .current }

    static func subject(for original: String) -> String {
        let rest = ComposeSubjectPrefixCollapser.stripping(original, prefixes: ["re:"])
        return "Re: \(displaySubject(rest))"
    }

    /// First line of the quoted original block — also the marker the
    /// compose quote-edit guard uses to locate the read-only region.
    ///
    /// The line is localized and shows the reader's local time ("Den 9. okt.
    /// 2026 kl. 10:13 skrev …:"). The guard receives this exact string at
    /// open time, so it never has to parse the visible wording.
    static func quoteMarker(
        for header: MessageHeader,
        locale: Locale = ComposeReplyFormatter.defaultLocale,
        timeZone: TimeZone = ComposeReplyFormatter.defaultTimeZone
    ) -> String {
        let day = format(header.date, locale: locale, timeZone: timeZone, includesTime: false)
        let time = format(header.date, locale: locale, timeZone: timeZone, includesTime: true)
        let sender = format(header.from)
        return String(
            localized: "On \(day) at \(time), \(sender) wrote:",
            bundle: localizedBundle(for: locale)
        )
    }

    /// Whether `line` is a reply attribution line in English or in `locale`'s
    /// wording. Signature placement uses this to find where a quote starts
    /// without hard-coding "wrote:".
    static func isAttributionLine<S: StringProtocol>(
        _ line: S,
        locale: Locale = ComposeReplyFormatter.defaultLocale
    ) -> Bool {
        let text = String(line)
        if text.hasPrefix("On "), text.hasSuffix(" wrote:") { return true }
        let affixes = attributionAffixes(locale: locale)
        return text.count > affixes.prefix.count + affixes.suffix.count
            && text.hasPrefix(affixes.prefix)
            && text.hasSuffix(affixes.suffix)
    }

    /// The fixed words before the first and after the last placeholder of the
    /// localized attribution template.
    private static func attributionAffixes(locale: Locale) -> (prefix: String, suffix: String) {
        let first = "\u{1}"
        let last = "\u{2}"
        let template = String(
            localized: "On \(first) at \(first), \(last) wrote:",
            bundle: localizedBundle(for: locale)
        )
        let prefix = template.components(separatedBy: first).first ?? ""
        let suffix = template.components(separatedBy: last).last ?? ""
        return (prefix, suffix)
    }

    /// The `.lproj` bundle for `locale`'s best-matching catalog language, so
    /// the attribution wording follows the requested locale rather than only
    /// the process language.
    private static func localizedBundle(for locale: Locale) -> Bundle {
        let language = Bundle.preferredLocalizations(
            from: Bundle.module.localizations,
            forPreferences: [locale.identifier]
        ).first
        guard let language,
              let path = Bundle.module.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else {
            return .module
        }
        return bundle
    }

    static func body(
        for header: MessageHeader,
        quoteText: String? = nil,
        placement: ComposeReplyQuotePlacement = .belowReply,
        locale: Locale = ComposeReplyFormatter.defaultLocale,
        timeZone: TimeZone = ComposeReplyFormatter.defaultTimeZone
    ) -> String {
        let quoteHeader = quoteMarker(for: header, locale: locale, timeZone: timeZone)
        let quotedSnippet = quoteLines(from: quoteText ?? header.snippet)

        switch placement {
        case .belowReply:
            var lines = ["", "", quoteHeader]
            lines.append(contentsOf: quotedSnippet)
            return lines.joined(separator: "\n")
        case .aboveReply:
            var lines = [quoteHeader]
            lines.append(contentsOf: quotedSnippet)
            lines.append(contentsOf: ["", ""])
            return lines.joined(separator: "\n")
        }
    }

    private static func quoteLines(from snippet: String) -> [String] {
        let trimmed = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return trimmed
            .components(separatedBy: .newlines)
            .map { "> \($0)" }
    }

    private static func format(_ correspondent: Correspondent) -> String {
        let email = correspondent.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = correspondent.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != email else { return email }
        return "\(name) <\(email)>"
    }

    private static func format(
        _ date: Date,
        locale: Locale,
        timeZone: TimeZone,
        includesTime: Bool
    ) -> String {
        var style = includesTime
            ? Date.FormatStyle(date: .omitted, time: .shortened)
            : Date.FormatStyle(date: .abbreviated, time: .omitted)
        style.locale = locale
        style.timeZone = timeZone
        return date.formatted(style)
    }

    private static func displaySubject(_ subject: String) -> String {
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(no subject)" : trimmed
    }
}

enum ComposeReplyPrefillPolicy {
    static func bodyText(
        prefillBodyText: String?,
        replyBody: String,
        placement: ComposeReplyQuotePlacement
    ) -> String {
        guard let prefillBodyText, !prefillBodyText.isEmpty else { return replyBody }
        switch placement {
        case .belowReply:
            return prefillBodyText + replyBody
        case .aboveReply:
            return replyBody + prefillBodyText
        }
    }
}
