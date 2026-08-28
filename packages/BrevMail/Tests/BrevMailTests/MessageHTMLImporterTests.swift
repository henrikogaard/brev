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

@Suite("MessageHTMLImporter")
struct MessageHTMLImporterTests {
    @Test("Returns nil for nil or empty HTML")
    func returnsNilForNilOrEmptyHTML() async {
        #expect(await MessageHTMLImporter.importAttributedHTML(nil) == nil)
        #expect(await MessageHTMLImporter.importAttributedHTML("") == nil)
        #expect(await MessageHTMLImporter.importAttributedHTML("   ") != nil)
    }

    @Test("Parses simple HTML into AttributedString")
    func parsesSimpleHTML() async {
        let result = await MessageHTMLImporter.importAttributedHTML("<p>Hello <b>world</b></p>")
        #expect(result != nil)
        let plain = String(result?.characters ?? AttributedString().characters)
        #expect(plain.contains("Hello"))
        #expect(plain.contains("world"))
    }

    @Test("Returns nil for HTML exceeding the 1 MiB cap")
    func returnsNilForOversizedHTML() async {
        // 2 MiB of ASCII filler — well over the 1_048_576 byte cap.
        let oversized = String(repeating: "a", count: 2_097_152)
        let result = await MessageHTMLImporter.importAttributedHTML(oversized)
        #expect(result == nil)
    }

    @Test("Strips inline foreground and background colors so theme owns contrast")
    func stripsInlineColors() async {
        let html = """
        <p style="color: red; background-color: yellow;">Themed text</p>
        """
        let result = await MessageHTMLImporter.importAttributedHTML(html)
        #expect(result != nil)
        // After stripping, no run should carry a foregroundColor or backgroundColor
        // attribute — the active Brev theme owns contrast.
        for run in result?.runs ?? AttributedString().runs {
            #expect(run.attributes.foregroundColor == nil)
            #expect(run.attributes.backgroundColor == nil)
        }
    }

    @Test("Does not throw for non-HTML input — NSAttributedString is lenient")
    func doesNotThrowForNonHTMLInput() async {
        // NSAttributedString with .html documentType is lenient: garbage input
        // parses to a plain string rather than throwing. The contract we lock
        // in here is that the importer returns *something* (not a throw) for
        // arbitrary input — callers must not crash on malformed mail bodies.
        let result = await MessageHTMLImporter.importAttributedHTML("not html at all")
        #expect(result != nil)
    }

    @Test("Concurrent imports serialize through the shared actor without deadlock")
    func concurrentImportsDoNotDeadlock() async {
        // Fire several concurrent imports to confirm the shared actor handles
        // reentrancy without deadlock. This guards the perf fix: moving off
        // @MainActor to a dedicated actor must not introduce serialization hangs.
        let htmls = (0 ..< 8).map { idx in "<p>Concurrent chunk \(idx)</p>" }
        await withTaskGroup(of: AttributedString?.self) { group in
            for html in htmls {
                group.addTask { await MessageHTMLImporter.importAttributedHTML(html) }
            }
            var results: [AttributedString?] = []
            for await result in group {
                results.append(result)
            }
            #expect(results.count == htmls.count)
            #expect(results.allSatisfy { $0 != nil })
        }
    }
}
