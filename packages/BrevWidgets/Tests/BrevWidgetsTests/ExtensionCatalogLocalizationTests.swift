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

/// Guards the Norwegian Bokmål (`nb`) coverage of the string catalogs that ship
/// in the widget and the iOS share extension. A missing translation silently
/// falls back to English, so a Norwegian user would see a mixed-language
/// widget or share sheet.
@Suite("Extension catalog localization")
struct ExtensionCatalogLocalizationTests {
    private static let widgetCatalog = "packages/BrevWidgets/Sources/BrevWidgets/Resources/Localizable.xcstrings"
    private static let shareCatalog = "apps/iOS/BrevShareExtension/Resources/Localizable.xcstrings"

    /// Keys the share extension requests through `String(localized:)`, exactly
    /// as the runtime builds them (interpolations become `%lld`).
    private static let shareExtensionKeys = [
        "Compose in Brev",
        "Loading shared content...",
        "Open Brev",
        "Cancel",
        "Try Again",
        "Brev could not prepare shared storage for attachments.",
        "Shared text is too large to include and was left out.",
        "%lld URL(s)",
        "1 attachment",
        "%lld attachments",
        "%lld unsupported",
        "This content type is not supported yet.",
        "No content to share",
        "Brev could not open this shared draft. Please try again."
    ]

    @Test("every widget catalog entry has a translated nb value")
    func widgetCatalogIsFullyTranslated() throws {
        let strings = try Self.loadStrings(Self.widgetCatalog)
        #expect(!strings.isEmpty)
        for key in strings.keys.sorted() {
            #expect(Self.hasTranslatedNB(strings[key]), "widget catalog is missing nb for: \(key)")
        }
    }

    @Test("widget catalog covers the keys the widget requests")
    func widgetCatalogCoversRuntimeKeys() throws {
        let strings = try Self.loadStrings(Self.widgetCatalog)
        for key in [
            "Mail",
            "Unread count and latest messages from your unified inbox.",
            "%lld unread",
            "Open Brev to see your mail.",
            "You're all caught up."
        ] {
            #expect(strings[key] != nil, "widget catalog is missing key: \(key)")
        }
    }

    @Test("share extension catalog translates every key the extension requests to nb")
    func shareExtensionCatalogIsTranslated() throws {
        let strings = try Self.loadStrings(Self.shareCatalog)
        for key in Self.shareExtensionKeys {
            #expect(strings[key] != nil, "share extension catalog is missing key: \(key)")
            #expect(Self.hasTranslatedNB(strings[key]), "share extension catalog is missing nb for: \(key)")
        }
        for key in strings.keys.sorted() {
            #expect(Self.hasTranslatedNB(strings[key]), "share extension catalog is missing nb for: \(key)")
        }
    }

    private static func hasTranslatedNB(_ entry: Any?) -> Bool {
        guard let entry = entry as? [String: Any],
              let localizations = entry["localizations"] as? [String: Any],
              let nb = localizations["nb"] as? [String: Any] else {
            return false
        }
        if let unit = nb["stringUnit"] as? [String: Any] {
            return isTranslated(unit)
        }
        guard let plural = (nb["variations"] as? [String: Any])?["plural"] as? [String: Any] else {
            return false
        }
        return ["one", "other"].allSatisfy { form in
            isTranslated((plural[form] as? [String: Any])?["stringUnit"] as? [String: Any])
        }
    }

    private static func isTranslated(_ unit: [String: Any]?) -> Bool {
        unit?["state"] as? String == "translated" && (unit?["value"] as? String)?.isEmpty == false
    }

    private static func loadStrings(_ relativePath: String) throws -> [String: Any] {
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
        throw CatalogLookupError.notFound(relativePath)
    }

    private enum CatalogLookupError: Error {
        case notFound(String)
    }
}
