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
import Testing

/// Count strings must carry `one`/`other` plural variants so a single item
/// reads "1 message" / "1 melding" rather than "1 messages" / "1 meldinger"
/// (audit finding N3).
@Suite("CountPluralLocalization")
struct CountPluralLocalizationTests {
    /// Catalog keys that render a count next to a noun and therefore need
    /// plural variations in both English and Norwegian Bokmål.
    private static let pluralKeys = [
        "%@, %lld messages, collapsed",
        "%@, %lld messages, expanded",
        "%lld messages",
        "%lld messages shown",
        "%lld threads shown",
        "%lld Filters",
        "Sort and filter, %lld filters active, %@",
        "%lld days before",
        "%lld hours before",
        "%lld minutes before",
        "%lld months ago",
        "%lld years ago",
        "%lld times",
        "%lld template(s)",
        "Couldn't load mailboxes for %lld accounts.",
        "%lld scheduled messages remain in Outbox. Waiting mail is checked when Brev is next opened; messages needing review will not retry automatically.",
        "%lld unavailable mailboxes are still part of this profile. Reconnect them in Accounts, or remove their membership here."
    ]

    @Test("count strings define one and other for en and nb", arguments: pluralKeys)
    func countStringsDefinePluralForms(key: String) throws {
        let strings = try Self.loadCatalogStrings()
        let localizations = ((strings[key] as? [String: Any])?["localizations"]) as? [String: Any]

        for language in ["en", "nb"] {
            let plural = Self.pluralForms(localizations?[language])
            for form in ["one", "other"] {
                let value = plural?[form]
                #expect(value?.isEmpty == false, "missing \(language) plural \(form) for \(key)")
            }
            #expect(plural?["one"]?.contains("%lld") == true, "\(language) one-form lost the count for \(key)")
        }
    }

    @Test("the English singular differs from the plural so '1 messages' cannot return")
    func englishSingularDiffersFromPlural() throws {
        let strings = try Self.loadCatalogStrings()
        let localizations = ((strings["%lld messages"] as? [String: Any])?["localizations"]) as? [String: Any]
        let english = Self.pluralForms(localizations?["en"])
        let norwegian = Self.pluralForms(localizations?["nb"])

        #expect(english?["one"] == "%lld message")
        #expect(english?["other"] == "%lld messages")
        #expect(norwegian?["one"] == "%lld melding")
        #expect(norwegian?["other"] == "%lld meldinger")
    }

    @Test("date section header accessibility label reads '1 melding' in nb")
    func dateHeaderLabelUsesNorwegianSingular() throws {
        let strings = try Self.loadCatalogStrings()
        let localizations = ((strings["%@, %lld messages, collapsed"] as? [String: Any])?["localizations"]) as? [String: Any]
        let norwegian = Self.pluralForms(localizations?["nb"])

        #expect(norwegian?["one"] == "%@, %lld melding, sammenfoldet")
    }

    /// Presentation-layer strings that used to be plain `String` literals and
    /// therefore never reached the catalog (audit finding N4).
    private static let presentationKeys = [
        "Unsubscribe available",
        "Open the unsubscribe page?",
        "Draft an unsubscribe email?",
        "Open Page",
        "Draft Email",
        "Download images",
        "Tracking pixels blocked",
        "Remote content blocked",
        "Brev blocked %@ and %@.",
        "Brev blocked %@.",
        "the remote hosts",
        "%@ and %@",
        "%@, %@, and %@",
        "Read receipt requested",
        "Send Receipt",
        "Read receipt received",
        "Read receipts received",
        "The recipient %@ the message.",
        "Preview",
        "Save",
        "Open",
        "Recent",
        "Ready to send",
        "Retry on Send",
        "Upload failed: %@",
        "Couldn't choose attachment: %@",
        "Couldn't attach \"%@\": %@",
        "Couldn't attach dropped image: %@"
    ]

    @Test("presentation strings are translated to nb", arguments: presentationKeys)
    func presentationStringsHaveNorwegian(key: String) throws {
        let strings = try Self.loadCatalogStrings()
        let localizations = ((strings[key] as? [String: Any])?["localizations"]) as? [String: Any]
        let unit = (localizations?["nb"] as? [String: Any])?["stringUnit"] as? [String: Any]

        #expect(unit?["state"] as? String == "translated", "missing nb for \(key)")
        #expect((unit?["value"] as? String)?.isEmpty == false, "empty nb for \(key)")
    }

    private static func pluralForms(_ localization: Any?) -> [String: String]? {
        guard let plural = ((localization as? [String: Any])?["variations"] as? [String: Any])?["plural"]
            as? [String: Any] else {
            return nil
        }
        var forms: [String: String] = [:]
        for (form, entry) in plural {
            if let value = ((entry as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String {
                forms[form] = value
            }
        }
        return forms
    }

    private static func loadCatalogStrings() throws -> [String: Any] {
        let relativePath = "packages/BrevMail/Sources/BrevMail/Resources/Localizable.xcstrings"
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0 ..< 8 {
            let candidate = directory.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                let data = try Data(contentsOf: candidate)
                let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                return try #require(root?["strings"] as? [String: Any])
            }
            directory.deleteLastPathComponent()
        }
        throw CatalogLookupError.notFound
    }

    private enum CatalogLookupError: Error {
        case notFound
    }
}
