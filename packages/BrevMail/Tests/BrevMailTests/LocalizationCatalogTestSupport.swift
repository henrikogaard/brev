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

@testable import BrevMail
import Foundation
import Testing

/// Shared lookups for plural string tests.
///
/// `swift test` with the CI toolchain (Xcode 16 on macOS 15) copies the
/// `.xcstrings` catalog without compiling `<language>.lproj` tables, so a
/// runtime lookup there has nothing to read. Tests check the catalog source
/// everywhere and resolve through compiled tables only where they exist.
enum LocalizationCatalogTestSupport {
    /// Compiled tables for `language`, or nil when the toolchain left the catalog uncompiled.
    static func compiledLanguageBundle(_ language: String) -> Bundle? {
        Bundle.module.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
    }

    static var hasCompiledCatalogs: Bool {
        compiledLanguageBundle("en") != nil && compiledLanguageBundle("nb") != nil
    }

    /// Plural `one`/`other` values for `key` in `language`, read from the catalog source.
    static func pluralForms(key: String, language: String) throws -> [String: String] {
        let strings = try loadCatalogStrings()
        let entry = strings[key] as? [String: Any]
        let localization = (entry?["localizations"] as? [String: Any])?[language] as? [String: Any]
        let plural = (localization?["variations"] as? [String: Any])?["plural"] as? [String: Any]
        var forms: [String: String] = [:]
        for (form, value) in plural ?? [:] {
            let unit = (value as? [String: Any])?["stringUnit"] as? [String: Any]
            forms[form] = unit?["value"] as? String
        }
        return forms
    }

    private static func loadCatalogStrings() throws -> [String: Any] {
        let relativePath = "packages/BrevMail/Sources/BrevMail/Resources/Localizable.xcstrings"
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0 ..< 7 {
            let candidate = directory.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                let root = try JSONSerialization.jsonObject(with: Data(contentsOf: candidate)) as? [String: Any]
                return try #require(root?["strings"] as? [String: Any])
            }
            directory.deleteLastPathComponent()
        }
        throw CatalogNotFound()
    }

    private struct CatalogNotFound: Error {}
}
