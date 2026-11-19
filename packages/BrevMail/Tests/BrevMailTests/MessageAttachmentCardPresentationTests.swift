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

/// The second line of a macOS attachment card (#306 slice 4, part 2).
@Suite("Message attachment card presentation")
struct MessageAttachmentCardPresentationTests {
    @Test("a file extension becomes an upper-case kind before the size")
    func kindAndSize() {
        #expect(MessageAttachmentCardPresentation.subtitle(filename: "Q4 plan.pdf", sizeText: "240 KB")
            == "PDF · 240 KB")
        #expect(MessageAttachmentCardPresentation.subtitle(filename: "photo.jpeg", sizeText: "2 MB")
            == "JPEG · 2 MB")
    }

    @Test("no extension, or an implausibly long one, shows the size only")
    func sizeOnly() {
        #expect(MessageAttachmentCardPresentation.subtitle(filename: "README", sizeText: "1 KB") == "1 KB")
        #expect(MessageAttachmentCardPresentation.subtitle(filename: "notes.backup-2026", sizeText: "1 KB")
            == "1 KB")
        #expect(MessageAttachmentCardPresentation.subtitle(filename: ".hidden", sizeText: "1 KB") == "1 KB")
        #expect(MessageAttachmentCardPresentation.subtitle(filename: "Q3 report v1.2", sizeText: "40 KB")
            == "40 KB")
        #expect(MessageAttachmentCardPresentation.subtitle(filename: "notes.a-b", sizeText: "1 KB") == "1 KB")
    }
}
