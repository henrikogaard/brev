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

@Suite("IMAP BODYSTRUCTURE plan")
struct IMAPBodyStructurePlanTests {
    @Test("common multipart mail fetches text first and defers attachment bytes")
    func parsesMultipartAlternativeAndAttachment() throws {
        let response = #"* 9 FETCH (UID 43 BODYSTRUCTURE ((("TEXT" "PLAIN" ("CHARSET" "UTF-8") NIL NIL "QUOTED-PRINTABLE" 20 2)("TEXT" "HTML" ("CHARSET" "UTF-8") NIL NIL "BASE64" 32 1) "ALTERNATIVE" ("BOUNDARY" "alt"))("APPLICATION" "PDF" ("NAME" "report.pdf") NIL NIL "BASE64" 2048 NIL ("ATTACHMENT" ("FILENAME" "report.pdf"))) "MIXED" ("BOUNDARY" "mixed")))"#

        let plan = try #require(IMAPBodyStructurePlan.parse(fetchResponses: [response], uid: 43))

        #expect(plan.plainTextPart?.section == "1.1")
        #expect(plan.htmlPart?.section == "1.2")
        #expect(plan.attachments == [
            IMAPBodyStructurePart(
                section: "2",
                mimeType: "application/pdf",
                transferEncoding: "base64",
                sizeBytes: 2048,
                charset: nil,
                name: "report.pdf",
                isInline: false,
                contentID: nil
            ),
        ])
    }

    @Test("signed and encrypted containers use the full-source compatibility path")
    func rejectsSecurityContainers() {
        let response = #"* 9 FETCH (UID 43 BODYSTRUCTURE (("TEXT" "PLAIN" ("CHARSET" "UTF-8") NIL NIL "7BIT" 20 2)("APPLICATION" "PKCS7-SIGNATURE" ("NAME" "smime.p7s") NIL NIL "BASE64" 1000 NIL ("ATTACHMENT" ("FILENAME" "smime.p7s"))) "SIGNED" ("PROTOCOL" "application/pkcs7-signature")))"#

        #expect(IMAPBodyStructurePlan.parse(fetchResponses: [response], uid: 43) == nil)
    }

    @Test("part resources round trip message ids without delimiter ambiguity")
    func partReferenceRoundTrips() throws {
        let reference = IMAPMessagePartReference(
            messageID: "Archive/2026:43",
            section: "2.1",
            transferEncoding: "base64"
        )

        #expect(try IMAPMessagePartReference(resource: reference.resource) == reference)
    }
}
