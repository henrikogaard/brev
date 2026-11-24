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

import Foundation

/// Standard ASN.1 Object Identifiers used in RFC 5652 / RFC 8551 CMS structures.
enum CMSObjectIdentifier {
    /// `id-data` (`1.2.840.113549.1.7.1`)
    static let data: [UInt64] = [1, 2, 840, 113_549, 1, 7, 1]
    /// `id-signedData` (`1.2.840.113549.1.7.2`)
    static let signedData: [UInt64] = [1, 2, 840, 113_549, 1, 7, 2]
    /// `id-envelopedData` (`1.2.840.113549.1.7.3`)
    static let envelopedData: [UInt64] = [1, 2, 840, 113_549, 1, 7, 3]
    /// `id-contentType` (`1.2.840.113549.1.9.3`)
    static let contentType: [UInt64] = [1, 2, 840, 113_549, 1, 9, 3]
    /// `id-messageDigest` (`1.2.840.113549.1.9.4`)
    static let messageDigest: [UInt64] = [1, 2, 840, 113_549, 1, 9, 4]
    /// `id-signingTime` (`1.2.840.113549.1.9.5`)
    static let signingTime: [UInt64] = [1, 2, 840, 113_549, 1, 9, 5]
    /// `id-sha256` (`2.16.840.1.101.3.4.2.1`)
    static let sha256: [UInt64] = [2, 16, 840, 1, 101, 3, 4, 2, 1]
    /// `rsaEncryption` (`1.2.840.113549.1.1.1`)
    static let rsaEncryption: [UInt64] = [1, 2, 840, 113_549, 1, 1, 1]
    /// `sha256WithRSAEncryption` (`1.2.840.113549.1.1.11`)
    static let sha256WithRSAEncryption: [UInt64] = [1, 2, 840, 113_549, 1, 1, 11]
    /// `ecdsa-with-SHA256` (`1.2.840.10045.4.3.2`)
    static let ecdsaWithSHA256: [UInt64] = [1, 2, 840, 10045, 4, 3, 2]
    /// `id-aes256-CBC` (`2.16.840.1.101.3.4.1.42`)
    static let aes256CBC: [UInt64] = [2, 16, 840, 1, 101, 3, 4, 1, 42]
}

/// Minimal ASN.1 DER encoder for RFC 5652 / RFC 8551 CMS payloads.
enum ASN1DER {
    static let integerTag: UInt8 = 0x02
    static let octetStringTag: UInt8 = 0x04
    static let nullTag: UInt8 = 0x05
    static let oidTag: UInt8 = 0x06
    static let utcTimeTag: UInt8 = 0x17
    static let generalizedTimeTag: UInt8 = 0x18
    static let sequenceTag: UInt8 = 0x30
    static let setTag: UInt8 = 0x31

    /// Encodes a definite DER length (short form < 128, minimal big-endian long form >= 128).
    static func length(_ count: Int) -> Data {
        precondition(count >= 0, "DER length must be non-negative")
        if count < 0x80 {
            return Data([UInt8(count)])
        }
        var value = UInt64(count)
        var bytes: [UInt8] = []
        while value > 0 {
            bytes.append(UInt8(value & 0xFF))
            value >>= 8
        }
        bytes.reverse()
        var out = Data([0x80 | UInt8(bytes.count)])
        out.append(contentsOf: bytes)
        return out
    }

    /// Wraps `content` in a DER Tag-Length-Value tuple.
    static func tlv(tag: UInt8, content: Data) -> Data {
        var out = Data([tag])
        out.append(length(content.count))
        out.append(content)
        return out
    }

    /// Encodes a DER `SEQUENCE` preserving element order.
    static func sequence(_ elements: [Data]) -> Data {
        tlv(tag: sequenceTag, content: concat(elements))
    }

    /// Encodes a canonical DER `SET` / `SET OF` with elements sorted in
    /// ascending unsigned byte order per X.690 §11.6 and RFC 5652 §5.4.
    static func set(_ elements: [Data]) -> Data {
        tlv(tag: setTag, content: concat(sortedSetElements(elements)))
    }

    /// Returns elements sorted in ascending lexicographical byte order for DER SET encoding.
    static func sortedSetElements(_ elements: [Data]) -> [Data] {
        elements.sorted { lhs, rhs in
            lhs.lexicographicallyPrecedes(rhs)
        }
    }

    /// Encodes a context-specific tag (`[tagNumber]`).
    static func contextSpecific(tagNumber: UInt8, constructed: Bool, content: Data) -> Data {
        precondition(tagNumber < 31, "Only single-octet context tags are supported")
        let tag: UInt8 = 0x80 | (constructed ? 0x20 : 0x00) | tagNumber
        return tlv(tag: tag, content: content)
    }

    /// Encodes a non-negative integer in minimal DER two's-complement form.
    static func integer(_ value: Int) -> Data {
        precondition(value >= 0, "Only non-negative CMS version/tag integers are encoded")
        if value == 0 {
            return Data([integerTag, 0x01, 0x00])
        }
        var remaining = UInt64(value)
        var bytes: [UInt8] = []
        while remaining > 0 {
            bytes.append(UInt8(remaining & 0xFF))
            remaining >>= 8
        }
        bytes.reverse()
        if let first = bytes.first, first & 0x80 != 0 {
            bytes.insert(0x00, at: 0)
        }
        return tlv(tag: integerTag, content: Data(bytes))
    }

    /// Encodes a DER `OCTET STRING`.
    static func octetString(_ bytes: Data) -> Data {
        tlv(tag: octetStringTag, content: bytes)
    }

    /// Encodes a DER `NULL`.
    static func null() -> Data {
        Data([nullTag, 0x00])
    }

    /// Encodes a DER `OBJECT IDENTIFIER` from its arc components.
    static func objectIdentifier(_ arcs: [UInt64]) -> Data {
        precondition(arcs.count >= 2 && arcs[0] <= 2 && (arcs[0] == 2 || arcs[1] < 40))
        var bytes: [UInt8] = []
        appendBase128(arcs[0] * 40 + arcs[1], to: &bytes)
        for arc in arcs.dropFirst(2) {
            appendBase128(arc, to: &bytes)
        }
        return tlv(tag: oidTag, content: Data(bytes))
    }

    /// Encodes CMS `Time` per RFC 5652 §11.3 (`UTCTime` through 2049, `GeneralizedTime` from 2050).
    static func cmsTime(_ date: Date) -> Data {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let second = components.second ?? 0

        if (1950 ... 2049).contains(year) {
            let formatted = String(
                format: "%02d%02d%02d%02d%02d%02dZ",
                year % 100,
                month,
                day,
                hour,
                minute,
                second
            )
            return tlv(tag: utcTimeTag, content: Data(formatted.utf8))
        }
        let formatted = String(
            format: "%04d%02d%02d%02d%02d%02dZ",
            year,
            month,
            day,
            hour,
            minute,
            second
        )
        return tlv(tag: generalizedTimeTag, content: Data(formatted.utf8))
    }

    /// Encodes an X.509 / CMS `AlgorithmIdentifier`.
    static func algorithmIdentifier(oid: [UInt64], parameters: Data? = nil) -> Data {
        var fields = [objectIdentifier(oid)]
        if let parameters {
            fields.append(parameters)
        }
        return sequence(fields)
    }

    /// Concatenates DER fragments into a single `Data` buffer.
    static func concat(_ parts: [Data]) -> Data {
        let total = parts.reduce(0) { $0 + $1.count }
        var out = Data(capacity: total)
        for part in parts {
            out.append(part)
        }
        return out
    }

    private static func appendBase128(_ value: UInt64, to output: inout [UInt8]) {
        if value == 0 {
            output.append(0x00)
            return
        }
        var chunks: [UInt8] = []
        var remaining = value
        while remaining > 0 {
            chunks.append(UInt8(remaining & 0x7F))
            remaining >>= 7
        }
        chunks.reverse()
        for index in 0 ..< chunks.count {
            let isLast = index == chunks.count - 1
            output.append(isLast ? chunks[index] : (chunks[index] | 0x80))
        }
    }
}

/// Parses X.509 DER certificates to extract verbatim `IssuerAndSerialNumber` fields.
enum X509CertificateParser {
    struct IssuerAndSerialNumber: Equatable {
        let issuerDER: Data
        let serialNumberDER: Data

        /// Encodes RFC 5652 `IssuerAndSerialNumber ::= SEQUENCE { issuer, serialNumber }`.
        var derEncoded: Data {
            ASN1DER.sequence([issuerDER, serialNumberDER])
        }
    }

    private struct DERElement {
        let tag: UInt8
        let fullRange: Range<Int>
        let valueRange: Range<Int>
    }

    /// Extracts the verbatim DER-encoded `issuer` and `serialNumber` from an X.509 certificate.
    static func extractIssuerAndSerialNumber(from certDER: Data) throws -> IssuerAndSerialNumber {
        let bytes = [UInt8](certDER)
        var rootCursor = 0
        let certificate = try readElement(in: bytes, cursor: &rootCursor, limit: bytes.count)
        guard certificate.tag == ASN1DER.sequenceTag else {
            throw PureSwiftCMSError.malformedCertificate
        }

        // Certificate ::= SEQUENCE { tbsCertificate, signatureAlgorithm, signatureValue }
        var certCursor = certificate.valueRange.lowerBound
        let tbs = try readElement(in: bytes, cursor: &certCursor, limit: certificate.valueRange.upperBound)
        guard tbs.tag == ASN1DER.sequenceTag else {
            throw PureSwiftCMSError.malformedCertificate
        }

        // TBSCertificate ::= SEQUENCE {
        //   version [0] EXPLICIT Version DEFAULT v1,
        //   serialNumber CertificateSerialNumber,
        //   signature AlgorithmIdentifier,
        //   issuer Name,
        //   ...
        // }
        var tbsCursor = tbs.valueRange.lowerBound
        let tbsLimit = tbs.valueRange.upperBound

        var next = try readElement(in: bytes, cursor: &tbsCursor, limit: tbsLimit)
        if next.tag == 0xA0 {
            // Skip optional [0] EXPLICIT version field present in v2/v3 certificates.
            next = try readElement(in: bytes, cursor: &tbsCursor, limit: tbsLimit)
        }

        guard next.tag == ASN1DER.integerTag else {
            throw PureSwiftCMSError.malformedCertificate
        }
        let serialRange = next.fullRange

        let signatureAlg = try readElement(in: bytes, cursor: &tbsCursor, limit: tbsLimit)
        guard signatureAlg.tag == ASN1DER.sequenceTag else {
            throw PureSwiftCMSError.malformedCertificate
        }

        let issuer = try readElement(in: bytes, cursor: &tbsCursor, limit: tbsLimit)
        guard issuer.tag == ASN1DER.sequenceTag else {
            throw PureSwiftCMSError.malformedCertificate
        }

        return IssuerAndSerialNumber(
            issuerDER: Data(bytes[issuer.fullRange]),
            serialNumberDER: Data(bytes[serialRange])
        )
    }

    private static func readElement(
        in bytes: [UInt8],
        cursor: inout Int,
        limit: Int
    ) throws -> DERElement {
        guard cursor < limit else {
            throw PureSwiftCMSError.malformedCertificate
        }
        let start = cursor
        let tag = bytes[cursor]
        cursor += 1

        guard cursor < limit else {
            throw PureSwiftCMSError.malformedCertificate
        }
        let firstLengthByte = bytes[cursor]
        cursor += 1

        let contentLength: Int
        if firstLengthByte < 0x80 {
            contentLength = Int(firstLengthByte)
        } else {
            let numOctets = Int(firstLengthByte & 0x7F)
            // Reject indefinite length (0) and unreasonably large lengths (> 4 bytes).
            guard numOctets > 0, numOctets <= 4, cursor + numOctets <= limit else {
                throw PureSwiftCMSError.malformedCertificate
            }
            var lengthValue = 0
            for index in 0 ..< numOctets {
                lengthValue = (lengthValue << 8) | Int(bytes[cursor + index])
            }
            cursor += numOctets
            contentLength = lengthValue
        }

        let valueStart = cursor
        guard contentLength >= 0, valueStart <= limit - contentLength else {
            throw PureSwiftCMSError.malformedCertificate
        }
        let valueEnd = valueStart + contentLength
        cursor = valueEnd

        return DERElement(
            tag: tag,
            fullRange: start ..< valueEnd,
            valueRange: valueStart ..< valueEnd
        )
    }
}
