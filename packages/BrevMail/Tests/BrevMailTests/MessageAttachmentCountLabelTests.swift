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

@Suite("MessageAttachmentCountLabel")
struct MessageAttachmentCountLabelTests {
    /// The compiled `<language>.lproj` of the module bundle, so each
    /// translation resolves regardless of the test process's own language.
    private static func languageBundle(_ language: String) throws -> Bundle {
        try #require(LocalizationCatalogTestSupport.compiledLanguageBundle(language))
    }

    @Test("the catalog carries English and Norwegian plural forms")
    func catalogPluralForms() throws {
        let english = try LocalizationCatalogTestSupport.pluralForms(key: "%lld attachments", language: "en")
        #expect(english == ["one": "%lld attachment", "other": "%lld attachments"])
        let norwegian = try LocalizationCatalogTestSupport.pluralForms(key: "%lld attachments", language: "nb")
        #expect(norwegian == ["one": "%lld vedlegg", "other": "%lld vedlegg"])
    }

    @Test(
        "English uses the singular for one attachment and the plural otherwise",
        .enabled(if: LocalizationCatalogTestSupport.hasCompiledCatalogs)
    )
    func englishPlurals() throws {
        let bundle = try Self.languageBundle("en")
        #expect(MessageAttachmentCountLabel.title(count: 1, bundle: bundle) == "1 attachment")
        #expect(MessageAttachmentCountLabel.title(count: 2, bundle: bundle) == "2 attachments")
        #expect(MessageAttachmentCountLabel.title(count: 0, bundle: bundle) == "0 attachments")
    }

    @Test(
        "Norwegian resolves the same count through its own catalog entry",
        .enabled(if: LocalizationCatalogTestSupport.hasCompiledCatalogs)
    )
    func norwegianPlurals() throws {
        let bundle = try Self.languageBundle("nb")
        #expect(MessageAttachmentCountLabel.title(count: 1, bundle: bundle) == "1 vedlegg")
        #expect(MessageAttachmentCountLabel.title(count: 3, bundle: bundle) == "3 vedlegg")
    }
}
