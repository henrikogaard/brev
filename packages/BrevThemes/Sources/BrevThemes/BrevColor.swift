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
import SwiftUI

/// A theme color expressed as a hex string. Parsed lazily so themes
/// can be loaded from JSON without committing to a `Color` instance
/// (which is platform / scheme specific).
///
/// The hex format is `#RRGGBB` or `#RRGGBBAA` — case-insensitive, the
/// leading `#` is optional. Invalid hex falls back to fully opaque
/// magenta so missed parses are visually loud.
public struct BrevColor: Codable, Sendable, Hashable {
    public let hex: String

    private final class CachedColor: NSObject {
        let value: Color

        init(_ value: Color) {
            self.value = value
        }
    }

    private static let colorCache: NSCache<NSString, CachedColor> = {
        let cache = NSCache<NSString, CachedColor>()
        cache.countLimit = 256
        return cache
    }()

    public init(_ hex: String) { self.hex = hex }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        hex = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }

    /// SwiftUI `Color` parsed from the stored hex string.
    public var color: Color {
        let key = hex.trimmingCharacters(in: .whitespacesAndNewlines) as NSString
        if let cached = Self.colorCache.object(forKey: key) {
            return cached.value
        }
        let parsed = Color(brevHex: hex)
        Self.colorCache.setObject(CachedColor(parsed), forKey: key)
        return parsed
    }
}

public extension Color {
    /// Internal hex initializer used by `BrevColor`. Tolerates `#` prefix
    /// and 6- or 8-character forms; falls back to magenta on parse
    /// failure to flag bad theme JSON visually.
    init(brevHex hex: String) {
        var stripped = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.hasPrefix("#") { stripped.removeFirst() }

        let scanner = Scanner(string: stripped)
        var raw: UInt64 = 0
        guard scanner.scanHexInt64(&raw) else {
            self = Color(red: 1, green: 0, blue: 1)
            return
        }

        let r, g, b, a: Double
        switch stripped.count {
        case 6:
            r = Double((raw & 0xFF0000) >> 16) / 255.0
            g = Double((raw & 0x00FF00) >> 8) / 255.0
            b = Double(raw & 0x0000FF) / 255.0
            a = 1.0
        case 8:
            r = Double((raw & 0xFF00_0000) >> 24) / 255.0
            g = Double((raw & 0x00FF_0000) >> 16) / 255.0
            b = Double((raw & 0x0000_FF00) >> 8) / 255.0
            a = Double(raw & 0x0000_00FF) / 255.0
        default:
            self = Color(red: 1, green: 0, blue: 1)
            return
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
