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

import BrevAI
import Foundation
import Testing

/// AI Writer copy that devbox QA on #302 found in English inside the
/// Norwegian UI: preview buttons, action titles and availability reasons.
@Suite("AI Writer copy localization")
struct AIWriterCopyLocalizationTests {
    private static let availabilityKeys = [
        "AI Writer is unavailable for this compose window.",
        "AI Writer is turned off.",
        "AI Writer needs consent before sending text.",
        "This account does not support AI Writer.",
        "Finish the current compose action first.",
        "AI Writer is already working.",
        "Write draft text before using this action.",
        "Select text before using this action.",
        "Enter a prompt before using this action.",
        "Open this from a reply compose window.",
        "Open a compose window with an editable subject.",
    ]

    private static let keys = [
        "Replace Draft", "Replace Subject", "Replace Selection",
        "Draft from Prompt", "Draft Reply", "Suggest Subject",
    ] + AIShortcutAction.allCases.map(\.displayLabel) + availabilityKeys

    @Test("AI Writer copy has a Norwegian translation", arguments: keys)
    func norwegian(key: String) throws {
        let strings = try LocalizationCatalogTestSupport.loadCatalogStrings()
        let entry = try #require(strings[key] as? [String: Any], "missing catalog key: \(key)")
        let nb = (entry["localizations"] as? [String: Any])?["nb"] as? [String: Any]
        let value = (nb?["stringUnit"] as? [String: Any])?["value"] as? String
        #expect(value?.isEmpty == false)
        #expect(value != key)
    }
}
