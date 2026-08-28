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

/// Resolves an IANA/MIME charset name to a `String.Encoding`. A short fast path
/// covers the most common names; anything else is looked up in Core
/// Foundation's charset registry (so iso-8859-15, windows-1251, koi8-r, gb2312,
/// big5, shift_jis, euc-kr, … decode correctly instead of falling back to
/// Latin-1 mojibake). Used for both header (RFC 2047) and body/parameter
/// decoding so charset support stays consistent across the parser.
enum MIMECharset {
    /// Resolves a charset name, defaulting to UTF-8 when the name is unknown.
    /// Use for body/parameter decoding where some encoding must be chosen.
    static func encoding(for charset: String) -> String.Encoding {
        recognizedEncoding(for: charset) ?? .utf8
    }

    /// Like `encoding(for:)` but returns `nil` for an unrecognized charset
    /// instead of defaulting to UTF-8, so callers can fall through to byte-level
    /// decoding heuristics (Latin-1/CP1252) when the declared charset is unknown.
    static func recognizedEncoding(for charset: String) -> String.Encoding? {
        // Strip an RFC 2231 *language suffix (e.g. "utf-8*en") before matching.
        let name = charset.split(separator: "*", maxSplits: 1).first.map(String.init) ?? charset
        switch name.lowercased() {
        case "utf-8", "utf8":
            return .utf8
        case "us-ascii", "ascii":
            return .ascii
        case "iso-8859-1", "latin1", "latin-1":
            return .isoLatin1
        case "windows-1252", "cp1252":
            return .windowsCP1252
        default:
            return registryEncoding(named: name)
        }
    }

    /// Maps an IANA charset name to a `String.Encoding` via Core Foundation's
    /// registry, or `nil` if the name isn't recognized.
    private static func registryEncoding(named name: String) -> String.Encoding? {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
    }
}
