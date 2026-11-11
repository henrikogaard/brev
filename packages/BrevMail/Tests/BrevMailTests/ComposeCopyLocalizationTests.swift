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

/// Compose copy that native QA on #279 found in English inside the Norwegian UI.
/// Keys are the runtime keys: a source `\n` is a real line break.
@Suite("Compose copy localization")
struct ComposeCopyLocalizationTests {
    private static let keys = [
        "Display text",
        "Cc/Bcc",
        "Save the current message as a template\nto reuse it in future conversations.",
        "Your last draft couldn't be reopened here. Any saved copy is still in Drafts."
    ]

    @Test("compose copy has a Norwegian translation", arguments: keys)
    func norwegian(key: String) throws {
        let strings = try LocalizationCatalogTestSupport.loadCatalogStrings()
        let entry = try #require(strings[key] as? [String: Any], "missing catalog key: \(key)")
        let nb = (entry["localizations"] as? [String: Any])?["nb"] as? [String: Any]
        let value = (nb?["stringUnit"] as? [String: Any])?["value"] as? String
        #expect(value?.isEmpty == false)
        #expect(value != key)
    }
}
