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

@Suite("IMAP message body parser")
struct IMAPMessageBodyParserTests {
    // MARK: - Plain text

    @Test("parses plain text 7bit message")
    func plainText7Bit() {
        let raw = """
        From: alice@example.com
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: 7bit

        Hello, world!
        This is a test.
        """
        let body = IMAPMessageBodyParser().parse(messageID: "1", rawMessage: raw)
        #expect(body.plainText == "Hello, world!\nThis is a test.")
        #expect(body.html == nil)
        #expect(body.attachments.isEmpty)
    }

    @Test("parses plain text 8bit message")
    func plainText8Bit() {
        let raw = """
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: 8bit

        Café au lait: 5 €
        """
        let body = IMAPMessageBodyParser().parse(messageID: "2", rawMessage: raw)
        #expect(body.plainText == "Café au lait: 5 €")
    }

    @Test("decodes a body in a non-Latin charset (windows-1251) via the IANA registry")
    func plainTextWindows1251Body() {
        // windows-1251 bytes for "Привет" (CF F0 E8 E2 E5 F2), quoted-printable.
        // Before the registry-backed charset lookup this fell back to Latin-1
        // and rendered as mojibake.
        let raw = """
        Content-Type: text/plain; charset=windows-1251
        Content-Transfer-Encoding: quoted-printable

        =CF=F0=E8=E2=E5=F2
        """
        let body = IMAPMessageBodyParser().parse(messageID: "w1251", rawMessage: raw)
        #expect(body.plainText == "Привет")
    }

    @Test("parses HTML message")
    func htmlMessage() {
        let raw = """
        Content-Type: text/html; charset=utf-8
        Content-Transfer-Encoding: 7bit

        <html><body><p>Hello</p></body></html>
        """
        let body = IMAPMessageBodyParser().parse(messageID: "3", rawMessage: raw)
        #expect(body.html == "<html><body><p>Hello</p></body></html>")
        #expect(body.plainText == nil)
    }

    // MARK: - Base64

    @Test("decodes base64 encoded body")
    func base64Body() {
        let raw = """
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: base64

        SGVsbG8sIHdvcmxkIQ==
        """
        let body = IMAPMessageBodyParser().parse(messageID: "4", rawMessage: raw)
        #expect(body.plainText == "Hello, world!")
    }

    @Test("decodes base64 with whitespace wrapping")
    func base64Wrapped() {
        let raw = """
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: base64

        SGVsbG8sIHdv
        cmxkIQ==
        """
        let body = IMAPMessageBodyParser().parse(messageID: "5", rawMessage: raw)
        #expect(body.plainText == "Hello, world!")
    }

    @Test("decodes base64 attachment body")
    func base64Attachment() {
        let raw = """
        Content-Type: image/png; name="photo.png"
        Content-Transfer-Encoding: base64
        Content-Disposition: attachment; filename="photo.png"

        iVBORw0KGgoAAAANSUhEUgAAAAEAAAA=
        """
        let body = IMAPMessageBodyParser().parse(messageID: "6", rawMessage: raw)
        #expect(body.attachments.count == 1)
        #expect(body.attachments[0].name == "photo.png")
        #expect(body.attachments[0].mimeType == "image/png")
    }

    // MARK: - Quoted-printable

    @Test("decodes quoted-printable UTF-8 body")
    func quotedPrintableUtf8() {
        let raw = """
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: quoted-printable

        =C3=A9l=C3=A8ve =E2=82=AC10
        """
        let body = IMAPMessageBodyParser().parse(messageID: "7", rawMessage: raw)
        #expect(body.plainText == "élève €10")
    }

    @Test("decodes quoted-printable with soft line break")
    func quotedPrintableSoftBreak() {
        let raw = """
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: quoted-printable

        This is a long line that should be =
        joined back together.
        """
        let body = IMAPMessageBodyParser().parse(messageID: "8", rawMessage: raw)
        #expect(body.plainText == "This is a long line that should be joined back together.")
    }

    @Test("decodes quoted-printable with CRLF soft line break")
    func quotedPrintableCRLFSoftBreak() {
        let raw = "Content-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\nHello=\r\nWorld"
        let body = IMAPMessageBodyParser().parse(messageID: "9", rawMessage: raw)
        #expect(body.plainText == "HelloWorld")
    }

    // MARK: - Multipart

    @Test("parses multipart alternative: plain text preferred")
    func multipartAlternativePlainPreferred() {
        let raw = """
        Content-Type: multipart/alternative; boundary="=_boundary_123"

        --=_boundary_123
        Content-Type: text/plain; charset=utf-8

        Hello in plain text.

        --=_boundary_123
        Content-Type: text/html; charset=utf-8

        <html><body><p>Hello in HTML.</p></body></html>

        --=_boundary_123--
        """
        let body = IMAPMessageBodyParser().parse(messageID: "10", rawMessage: raw)
        #expect(body.plainText == "Hello in plain text.")
        #expect(body.html == "<html><body><p>Hello in HTML.</p></body></html>")
    }

    @Test("parses multipart mixed with attachment")
    func multipartMixedWithAttachment() {
        let raw = """
        Content-Type: multipart/mixed; boundary="==boundary=="

        --==boundary==
        Content-Type: text/plain; charset=utf-8

        Here is the document.

        --==boundary==
        Content-Type: application/pdf; name="report.pdf"
        Content-Disposition: attachment; filename="report.pdf"
        Content-Transfer-Encoding: base64

        UERGIFN0dWZm

        --==boundary==--
        """
        let body = IMAPMessageBodyParser().parse(messageID: "11", rawMessage: raw)
        #expect(body.plainText == "Here is the document.")
        #expect(body.attachments.count == 1)
        #expect(body.attachments[0].name == "report.pdf")
        #expect(body.attachments[0].mimeType == "application/pdf")
        #expect(body.attachments[0].isInline == false)
    }

    @Test("parses received read receipt multipart reports")
    func receivedReadReceiptReport() {
        let raw = """
        Content-Type: multipart/report; report-type=disposition-notification; boundary="receipt-boundary"

        --receipt-boundary
        Content-Type: text/plain; charset=utf-8

        Your message was displayed.

        --receipt-boundary
        Content-Type: message/disposition-notification
        Content-Transfer-Encoding: 7bit

        Final-Recipient: rfc822;reader@example.com
        Original-Message-ID: <original@example.org>
        Disposition: manual-action/MDN-sent-manually; displayed

        --receipt-boundary--
        """

        let body = IMAPMessageBodyParser().parse(messageID: "receipt", rawMessage: raw)

        #expect(body.readReceiptNotification == ReadReceiptNotification(
            finalRecipient: "reader@example.com",
            originalMessageID: "<original@example.org>",
            disposition: "manual-action/MDN-sent-manually; displayed"
        ))
        #expect(body.plainText == "Your message was displayed.")
    }

    @Test("parses multipart with inline image")
    func multipartInlineImage() {
        let raw = """
        Content-Type: multipart/related; boundary="relbound"

        --relbound
        Content-Type: text/html; charset=utf-8

        <img src="cid:img1@example.com">

        --relbound
        Content-Type: image/png; name="logo.png"
        Content-ID: <img1@example.com>
        Content-Transfer-Encoding: base64

        iVBORw0KGgo=

        --relbound--
        """
        let body = IMAPMessageBodyParser().parse(messageID: "12", rawMessage: raw)
        #expect(body.html?.contains("cid:img1@example.com") == true)
        #expect(body.attachments.count == 1)
        #expect(body.attachments[0].contentID == "img1@example.com")
        #expect(body.attachments[0].isInline == true)
    }

    @Test("parses multipart with deeply nested structure")
    func multipartDeepNesting() {
        let raw = """
        Content-Type: multipart/mixed; boundary="outer"

        --outer
        Content-Type: multipart/alternative; boundary="alt"

        --alt
        Content-Type: text/plain; charset=utf-8

        Deep text

        --alt
        Content-Type: text/html; charset=utf-8

        <b>Deep HTML</b>

        --alt--

        --outer
        Content-Type: application/octet-stream
        Content-Disposition: attachment; filename="data.bin"
        Content-Transfer-Encoding: base64

        ZGF0YQo=

        --outer--
        """
        let body = IMAPMessageBodyParser().parse(messageID: "13", rawMessage: raw)
        #expect(body.plainText == "Deep text")
        #expect(body.html == "<b>Deep HTML</b>")
        #expect(body.attachments.count == 1)
        #expect(body.attachments[0].name == "data.bin")
    }

    @Test("parses multipart with no closing boundary")
    func multipartNoClosingBoundary() {
        let raw = """
        Content-Type: multipart/mixed; boundary="bound"

        --bound
        Content-Type: text/plain

        Part one

        --bound
        Content-Type: text/plain

        Part two
        """
        let body = IMAPMessageBodyParser().parse(messageID: "14", rawMessage: raw)
        #expect(body.plainText == "Part one")
    }

    // MARK: - Attachment detection

    @Test("detects inline text part as non-attachment")
    func inlineTextNotAttachment() {
        let raw = """
        Content-Type: text/plain
        Content-Disposition: inline

        Just inline.
        """
        let body = IMAPMessageBodyParser().parse(messageID: "15", rawMessage: raw)
        #expect(body.attachments.isEmpty)
    }

    @Test("detects non-text inline disposition as attachment")
    func nonTextInlineIsAttachment() {
        let raw = """
        Content-Type: image/png
        Content-Disposition: inline; filename="icon.png"
        Content-Transfer-Encoding: base64

        iVBORw0KGgo=
        """
        let body = IMAPMessageBodyParser().parse(messageID: "16", rawMessage: raw)
        #expect(body.attachments.count == 1)
        #expect(body.attachments[0].name == "icon.png")
        #expect(body.attachments[0].isInline == true)
    }

    @Test("falls back to filename from Content-Type name parameter")
    func filenameFromContentTypeName() {
        let raw = """
        Content-Type: application/pdf; name="guide.pdf"
        Content-Disposition: attachment

        %PDF-something
        """
        let body = IMAPMessageBodyParser().parse(messageID: "17", rawMessage: raw)
        #expect(body.attachments.count == 1)
        #expect(body.attachments[0].name == "guide.pdf")
    }

    @Test("falls back to generic attachment name when filename missing")
    func attachmentMissingFilename() {
        let raw = """
        Content-Type: application/octet-stream
        Content-Transfer-Encoding: base64

        dW5rbm93bg==
        """
        let body = IMAPMessageBodyParser().parse(messageID: "18", rawMessage: raw)
        #expect(body.attachments.count == 1)
        #expect(body.attachments[0].name == "Attachment 1")
    }

    @Test("detects attachment by content ID without disposition")
    func attachmentByContentID() {
        let raw = """
        Content-Type: image/png
        Content-ID: <cid:123>

        PNG data here
        """
        let body = IMAPMessageBodyParser().parse(messageID: "19", rawMessage: raw)
        #expect(body.attachments.count == 1)
        #expect(body.attachments[0].contentID == "cid:123")
    }

    // MARK: - MIMEHeader parsing

    @Test("parses simple headers")
    func simpleHeaders() {
        let raw = """
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: 7bit

        Body
        """
        let body = IMAPMessageBodyParser().parse(messageID: "20", rawMessage: raw)
        #expect(body.plainText == "Body")
    }

    @Test("parses folded/continuation headers")
    func foldedHeaders() {
        let raw = """
        Subject: A very long
         subject that
         was folded
        Content-Type: text/plain

        Body
        """
        let body = IMAPMessageBodyParser().parse(messageID: "21", rawMessage: raw)
        #expect(body.plainText == "Body")
    }

    @Test("parses headers with no body as fallback text")
    func headersNoBody() {
        let raw = "Subject: just headers"
        let body = IMAPMessageBodyParser().parse(messageID: "22", rawMessage: raw)
        #expect(body.plainText == "Subject: just headers")
    }

    // MARK: - Authentication-Results header

    @Test("passes through Authentication-Results header")
    func authenticationResults() {
        let raw = """
        Authentication-Results: spf=pass smtp.mailfrom=example.com
        Content-Type: text/plain

        Body
        """
        let body = IMAPMessageBodyParser().parse(messageID: "23", rawMessage: raw)
        #expect(body.authenticationResults == "spf=pass smtp.mailfrom=example.com")
    }

    @Test("passes through read receipt request header")
    func readReceiptRequest() {
        let raw = """
        Disposition-Notification-To: sender@example.org
        Content-Type: text/plain

        Body
        """
        let body = IMAPMessageBodyParser().parse(messageID: "receipt-request", rawMessage: raw)
        #expect(body.readReceiptRequest?.notificationTo == "sender@example.org")
    }

    @Test("handles missing Authentication-Results header")
    func noAuthenticationResults() {
        let raw = """
        Content-Type: text/plain

        Body
        """
        let body = IMAPMessageBodyParser().parse(messageID: "24", rawMessage: raw)
        #expect(body.authenticationResults == nil)
    }

    // MARK: - Content-Type parsing

    @Test("defaults media type to text/plain when missing")
    func defaultContentType() {
        let raw = """
        From: test@example.com

        Body text
        """
        let body = IMAPMessageBodyParser().parse(messageID: "25", rawMessage: raw)
        #expect(body.plainText == "Body text")
    }

    @Test("parses Content-Type with quoted charset parameter")
    func quotedCharsetParameter() {
        let raw = """
        Content-Type: text/plain; charset="utf-8"

        Hello
        """
        let body = IMAPMessageBodyParser().parse(messageID: "26", rawMessage: raw)
        #expect(body.plainText == "Hello")
    }

    // MARK: - CRLF normalization

    @Test("normalizes CRLF to LF before parsing")
    func crlfNormalization() {
        let raw = "Content-Type: text/plain\r\n\r\nLine1\r\nLine2"
        let body = IMAPMessageBodyParser().parse(messageID: "27", rawMessage: raw)
        #expect(body.plainText == "Line1\nLine2")
    }

    @Test("normalizes bare CR to LF before parsing")
    func bareCRNormalization() {
        let raw = "Content-Type: text/plain\r\rLine1\rLine2"
        let body = IMAPMessageBodyParser().parse(messageID: "28", rawMessage: raw)
        #expect(body.plainText == "Line1\nLine2")
    }

    // MARK: - UTF-8 BOM handling

    @Test("handles UTF-8 BOM in body")
    func utf8BOM() {
        let raw = """
        Content-Type: text/plain; charset=utf-8

        \u{FEFF}Hello with BOM
        """
        let body = IMAPMessageBodyParser().parse(messageID: "29", rawMessage: raw)
        #expect(body.plainText == "\u{FEFF}Hello with BOM")
    }

    // MARK: - Windows-1252 charset

    @Test("decodes Windows-1252 body")
    func windows1252() {
        let raw = """
        Content-Type: text/plain; charset=windows-1252

        \u{2013}\u{2014}\u{2122}
        """
        let body = IMAPMessageBodyParser().parse(messageID: "30", rawMessage: raw)
        #expect(body.plainText == "\u{2013}\u{2014}\u{2122}")
    }

    // MARK: - attachmentData

    @Test("returns nil for attachmentIndex 0")
    func attachmentDataZeroIndex() {
        let result = IMAPMessageBodyParser().attachmentData(
            attachmentIndex: 0,
            rawMessage: ""
        )
        #expect(result == nil)
    }

    @Test("returns attachment data for valid index")
    func attachmentDataValidIndex() {
        let raw = """
        Content-Type: multipart/mixed; boundary="b"

        --b
        Content-Type: text/plain

        Body

        --b
        Content-Type: application/octet-stream
        Content-Transfer-Encoding: base64

        aGVsbG8=

        --b--
        """
        let data = IMAPMessageBodyParser().attachmentData(
            attachmentIndex: 1,
            rawMessage: raw
        )
        #expect(data != nil)
        #expect(String(data: data!, encoding: .utf8) == "hello")
    }

    @Test("returns nil for out-of-range attachment index")
    func attachmentDataOutOfRange() {
        let raw = """
        Content-Type: text/plain

        No attachments.
        """
        let result = IMAPMessageBodyParser().attachmentData(
            attachmentIndex: 99,
            rawMessage: raw
        )
        #expect(result == nil)
    }

    // MARK: - MIME filename decoding

    @Test("uses RFC 5987 extended filename when present")
    func extendedFilenameRFC5987() {
        let raw = """
        Content-Type: text/plain
        Content-Disposition: attachment; filename*=UTF-8''caf%C3%A9.txt

        Data
        """
        let body = IMAPMessageBodyParser().parse(messageID: "31", rawMessage: raw)
        #expect(body.attachments.count == 1)
        #expect(body.attachments[0].name == "café.txt")
    }

    @Test("uses continued RFC 2231 filename segments")
    func continuedFilenameSegments() {
        let raw = """
        Content-Type: text/plain
        Content-Disposition: attachment; filename*0=long; filename*1=name.txt

        Data
        """
        let body = IMAPMessageBodyParser().parse(messageID: "32", rawMessage: raw)
        #expect(body.attachments.count == 1)
        #expect(body.attachments[0].name == "longname.txt")
    }

    // MARK: - Resource safety

    @Test("pathologically nested multipart is bounded and does not overflow the stack")
    func deeplyNestedMultipartIsBounded() {
        // A crafted message with thousands of nested multipart boundaries must
        // not recurse without bound. Before the depth cap this overflowed the
        // stack and crashed the process; now descent stops and deeper parts are
        // treated as opaque content. Reaching the #expect at all proves no crash.
        var nested = "Content-Type: text/plain\n\ninnermost"
        for level in 0 ..< 3000 {
            let boundary = "b\(level)"
            nested = """
            Content-Type: multipart/mixed; boundary="\(boundary)"

            --\(boundary)
            \(nested)
            --\(boundary)--
            """
        }
        let body = IMAPMessageBodyParser().parse(messageID: "deep", rawMessage: nested)
        // The cap stops descent well before the innermost leaf, so the unique
        // marker is never extracted as a clean text part.
        #expect(body.plainText != "innermost")
    }
}
