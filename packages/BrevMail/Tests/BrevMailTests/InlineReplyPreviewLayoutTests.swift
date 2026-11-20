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
import Testing

/// Room for the AI preview in the docked reply (#302).
@Suite("Inline reply AI preview layout")
struct InlineReplyPreviewLayoutTests {
    @Test("the dock's fields and starters step aside while a preview is open")
    func dockMakesRoom() {
        #expect(!InlineReplyPreviewLayout.showsFieldsAndStarters(isInline: true, isPreviewing: true))
        #expect(InlineReplyPreviewLayout.showsFieldsAndStarters(isInline: true, isPreviewing: false))
    }

    @Test("the reply window keeps its fields while previewing")
    func windowKeepsFields() {
        #expect(InlineReplyPreviewLayout.showsFieldsAndStarters(isInline: false, isPreviewing: true))
        #expect(InlineReplyPreviewLayout.showsFieldsAndStarters(isInline: false, isPreviewing: false))
    }

    @Test("the docked preview text always gets some height")
    func previewMinimumHeight() {
        #expect((InlineReplyPreviewLayout.previewTextMinHeight(isInline: true) ?? 0) > 0)
        #expect(InlineReplyPreviewLayout.previewTextMinHeight(isInline: false) == nil)
    }
}
