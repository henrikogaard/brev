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

    private struct InitialsCacheKey: Hashable {
        let displayName: String?
        let email: String
    }

    private struct ColorIndexCacheKey: Hashable {
        let email: String
        let paletteCount: Int
    }

    private static let cacheLock = NSLock()
    private nonisolated(unsafe) static var initialsCache: [InitialsCacheKey: String] = [:]
    private nonisolated(unsafe) static var colorIndexCache: [ColorIndexCacheKey: Int] = [:]
    private nonisolated(unsafe) static var foregroundStyleCache: [String: ForegroundStyle] = [:]
    private static let maxSenderCacheEntries = 512
    private static let maxForegroundCacheEntries = 128

    /// Extract one-or-two-letter initials. Tries the display name
    /// first, falls back to the email local-part.
    public static func initials(displayName: String?, email: String) -> String {
        let key = InitialsCacheKey(displayName: displayName, email: email)
        if let cached = cacheLock.withLock({ initialsCache[key] }) {
            return cached
        }
        let computed: String
        if let displayName, !displayName.trimmingCharacters(in: .whitespaces).isEmpty {
            computed = initials(from: displayName)
        } else {
            let local = email.split(separator: "@").first.map(String.init) ?? email
            computed = initials(from: local)
        }
        cacheLock.withLock {
            if initialsCache.count >= maxSenderCacheEntries {
                initialsCache.removeAll(keepingCapacity: true)
            }
            initialsCache[key] = computed
        }
        return computed
    }

    /// Color palette index for `email`. Stable across runs.
    public static func colorIndex(email: String, paletteCount: Int) -> Int {
        guard paletteCount > 0 else { return 0 }
        let key = ColorIndexCacheKey(email: email, paletteCount: paletteCount)
        if let cached = cacheLock.withLock({ colorIndexCache[key] }) {
            return cached
        }
        let normalized = email.lowercased()
        let hash = Insecure.MD5.hash(data: Data(normalized.utf8))
        // Take the first byte; cheap and stable enough for a
        // per-sender swatch (we don't need cryptographic strength
        // here, just deterministic spread).
        let firstByte = hash.withUnsafeBytes { $0.first ?? 0 }
        let computed = Int(firstByte) % paletteCount
        cacheLock.withLock {
            if colorIndexCache.count >= maxSenderCacheEntries {
                colorIndexCache.removeAll(keepingCapacity: true)
            }
            colorIndexCache[key] = computed
        }
        return computed
    }

    public static func foregroundStyle(forBackgroundHex hex: String) -> ForegroundStyle {
        if let cached = cacheLock.withLock({ foregroundStyleCache[hex] }) {
            return cached
        }
        let computed: ForegroundStyle
        if let luminance = relativeLuminance(hex: hex) {
            computed = luminance > 0.55 ? .dark : .light
        } else {
            computed = .light
        }
        cacheLock.withLock {
            if foregroundStyleCache.count >= maxForegroundCacheEntries {
                foregroundStyleCache.removeAll(keepingCapacity: true)
            }
            foregroundStyleCache[hex] = computed
        }
        return computed
    }

    // MARK: - Internals

    static func initials(from raw: String) -> String {
        var cleaned = String()
        cleaned.reserveCapacity(raw.count)
        var lastWasSeparator = false
        for character in raw {
            if character == "." || character == "_" || character == "-" || character == "+" {
                if !lastWasSeparator {
                    cleaned.append(" ")
                    lastWasSeparator = true
                }
            } else {
                cleaned.append(character)
                lastWasSeparator = false
            }
        }
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        var result = ""
        for part in parts.prefix(2) {
            if let first = part.first {
                result.append(first)
            }
        }
        if result.isEmpty {
            return trimmed.first.map { String($0).uppercased() } ?? "?"
        }
        return result.uppercased()
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
