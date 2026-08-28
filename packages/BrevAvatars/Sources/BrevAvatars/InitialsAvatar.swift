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

import CryptoKit
import Foundation

/// Deterministic initials + color index for a sender.
///
/// See ADR-0003 §Resolution cascade step 6. The color index is
/// stable across sessions and devices because it derives from the
/// lowercased email rather than any per-session state.
public enum InitialsAvatar {
    public enum ForegroundStyle: Sendable, Equatable {
        case light
        case dark
    }

    /// Extract one-or-two-letter initials. Tries the display name
    /// first, falls back to the email local-part.
    public static func initials(displayName: String?, email: String) -> String {
        if let displayName, !displayName.trimmingCharacters(in: .whitespaces).isEmpty {
            return initials(from: displayName)
        }
        let local = email.split(separator: "@").first.map(String.init) ?? email
        return initials(from: local)
    }

    /// Color palette index for `email`. Stable across runs.
    public static func colorIndex(email: String, paletteCount: Int) -> Int {
        guard paletteCount > 0 else { return 0 }
        let normalized = email.lowercased()
        let hash = Insecure.MD5.hash(data: Data(normalized.utf8))
        // Take the first byte; cheap and stable enough for a
        // per-sender swatch (we don't need cryptographic strength
        // here, just deterministic spread).
        let firstByte = Array(hash).first ?? 0
        return Int(firstByte) % paletteCount
    }

    public static func foregroundStyle(forBackgroundHex hex: String) -> ForegroundStyle {
        guard let luminance = relativeLuminance(hex: hex) else { return .light }
        return luminance > 0.55 ? .dark : .light
    }

    // MARK: - Internals

    static func initials(from raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "[._\\-+]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = cleaned
            .split(separator: " ")
            .filter { !$0.isEmpty }
        let letters = parts.prefix(2).compactMap { $0.first }.map(String.init)
        if letters.isEmpty {
            return cleaned.first.map { String($0).uppercased() } ?? "?"
        }
        return letters.joined().uppercased()
    }

    private static func relativeLuminance(hex: String) -> Double? {
        var stripped = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.hasPrefix("#") { stripped.removeFirst() }
        guard stripped.count == 6 || stripped.count == 8,
              let raw = UInt64(stripped, radix: 16) else {
            return nil
        }
        let r, g, b: Double
        if stripped.count == 6 {
            r = Double((raw & 0xFF0000) >> 16) / 255.0
            g = Double((raw & 0x00FF00) >> 8) / 255.0
            b = Double(raw & 0x0000FF) / 255.0
        } else {
            r = Double((raw & 0xFF00_0000) >> 24) / 255.0
            g = Double((raw & 0x00FF_0000) >> 16) / 255.0
            b = Double((raw & 0x0000_FF00) >> 8) / 255.0
        }
        return 0.2126 * linearized(r) + 0.7152 * linearized(g) + 0.0722 * linearized(b)
    }

    private static func linearized(_ component: Double) -> Double {
        component <= 0.03928
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }
}
