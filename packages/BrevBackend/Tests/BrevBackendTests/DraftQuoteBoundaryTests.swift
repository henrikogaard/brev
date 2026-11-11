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

@testable import BrevBackend
import Foundation
import Testing

/// ADR-0093: the quote boundary is optional, local metadata.
@Suite("Draft quote boundary")
struct DraftQuoteBoundaryTests {
    @Test("a Draft saved before the field existed still decodes without one")
    func legacyDecoding() throws {
        let draft = try JSONDecoder().decode(Draft.self, from: Data(#"{"id":"legacy","htmlBody":"Body"}"#.utf8))
        #expect(draft.quoteBoundary == nil)
    }

    @Test("the boundary survives persistence", arguments: [DraftQuoteBoundary.Edge.top, .bottom])
    func roundTrip(edge: DraftQuoteBoundary.Edge) throws {
        let draft = Draft(id: "reply", quoteBoundary: DraftQuoteBoundary(marker: "On Jan 1, Ada wrote:", edge: edge))
        let decoded = try JSONDecoder().decode(Draft.self, from: JSONEncoder().encode(draft))
        #expect(decoded == draft)
    }

    @Test("the boundary does not change the content fingerprint")
    func fingerprintUnchanged() {
        let plain = Draft(id: "reply", htmlBody: "Body")
        var marked = plain
        marked.quoteBoundary = DraftQuoteBoundary(marker: "On Jan 1, Ada wrote:", edge: .bottom)
        #expect(DraftContentFingerprint.fingerprint(for: plain) == DraftContentFingerprint.fingerprint(for: marked))
    }
}
