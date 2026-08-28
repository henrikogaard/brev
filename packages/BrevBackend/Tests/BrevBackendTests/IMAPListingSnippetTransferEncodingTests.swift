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
import Testing

@Suite("IMAPListingSnippetTransferEncoding")
struct IMAPListingSnippetTransferEncodingTests {
    @Test("literal equals values are not treated as quoted-printable")
    func literalEqualsValuesAreNotTreatedAsQuotedPrintable() {
        let plain = "Set code=10 and retry=20 before shipping."
        #expect(!IMAPListingSnippetTransferEncoding.looksLikeQuotedPrintable(plain))
        #expect(IMAPListingSnippetTransferEncoding.decodeIfNeeded(plain) == plain)
    }

    @Test("encoded newlines and spaces decode for listing peeks")
    func encodedNewlinesAndSpacesDecodeForListingPeeks() {
        let encoded = "=0A=0A=0A*|SUBJECT|* Hello from=20Porkbun"
        #expect(IMAPListingSnippetTransferEncoding.looksLikeQuotedPrintable(encoded))
        #expect(
            IMAPListingSnippetTransferEncoding.decodeIfNeeded(encoded)
                == "\n\n\n*|SUBJECT|* Hello from Porkbun"
        )
    }
}
