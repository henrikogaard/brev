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

@Suite("MessageBulkSelectionPresentation")
struct MessageBulkSelectionPresentationTests {
    /// The compiled `<language>.lproj` of the module bundle, so each
    /// translation resolves regardless of the test process's own language.
    private static func languageBundle(_ language: String) throws -> Bundle {
        let path = try #require(Bundle.module.path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    @Test("the pane replaces the reader from two checked messages")
    func paneThreshold() {
        #expect(!MessageBulkSelectionPresentation.showsPane(forSelectionCount: 0))
        #expect(!MessageBulkSelectionPresentation.showsPane(forSelectionCount: 1))
        #expect(MessageBulkSelectionPresentation.showsPane(forSelectionCount: 2))
        #expect(MessageBulkSelectionPresentation.showsPane(forSelectionCount: 40))
    }

    @Test("English heading follows plural rules")
    func englishHeading() throws {
        let bundle = try Self.languageBundle("en")
        #expect(MessageBulkSelectionPresentation.title(count: 1, bundle: bundle) == "1 message selected")
        #expect(MessageBulkSelectionPresentation.title(count: 3, bundle: bundle) == "3 messages selected")
    }

    @Test("Norwegian heading follows plural rules")
    func norwegianHeading() throws {
        let bundle = try Self.languageBundle("nb")
        #expect(MessageBulkSelectionPresentation.title(count: 1, bundle: bundle) == "1 melding valgt")
        #expect(MessageBulkSelectionPresentation.title(count: 3, bundle: bundle) == "3 meldinger valgt")
    }
}
