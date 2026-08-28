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

/// Translates between `FlagColor` and the Apple Mail-compatible IMAP /
/// JMAP keyword encoding (`$MailFlagBit0..2`).
///
/// Apple encodes a flag color as a 3-bit ordinal spread across three
/// keywords — `$MailFlagBit0` is the low bit (value 1), `$MailFlagBit1`
/// the middle (value 2), `$MailFlagBit2` the high bit (value 4) — giving
/// an ordinal 0...7. Brev uses 0...6 for its seven colors. The keyword
/// set is written alongside the IMAP `\Flagged` system flag / JMAP
/// `$flagged` keyword, which a future IMAP/JMAP backend owns.
///
/// > Important: The `appleOrdinal` table below maps each Brev `FlagColor`
/// > to an Apple ordinal. The bit *math* is exact and unit-tested, but
/// > the ordinal→color *correspondence* is reverse-engineered and is
/// > **not yet verified against a live Apple Mail mailbox**. Confirm it
/// > before the IMAP/JMAP keyword encoder ships — a wrong row silently
/// > mis-maps one color to another. This is the single place to fix.
/// > See ADR-0019.
public enum AppleFlagKeyword {
    /// The three Apple flag-bit keywords, low bit first.
    static let bitKeywords = ["$MailFlagBit0", "$MailFlagBit1", "$MailFlagBit2"]

    /// Maps a `FlagColor` to its Apple 3-bit ordinal (0...7).
    ///
    /// UNVERIFIED correspondence — see the type doc. Keep this the only
    /// definition of the mapping so verification touches one place.
    static func appleOrdinal(for color: FlagColor) -> Int {
        switch color {
        case .orange: 1
        case .red: 2
        case .yellow: 3
        case .green: 4
        case .blue: 5
        case .purple: 6
        case .gray: 7
        }
    }

    private static func color(forAppleOrdinal ordinal: Int) -> FlagColor? {
        FlagColor.allCases.first { appleOrdinal(for: $0) == ordinal }
    }

    /// The `$MailFlagBit*` keywords representing a color's ordinal.
    ///
    /// Only the bits set in the ordinal are returned; the caller adds
    /// `\Flagged` / `$flagged` separately. An empty set means "flagged,
    /// no color bits" (ordinal 0), which Brev does not emit.
    public static func keywords(for color: FlagColor) -> Set<String> {
        let ordinal = appleOrdinal(for: color)
        var result: Set<String> = []
        for bit in 0 ..< bitKeywords.count where ordinal & (1 << bit) != 0 {
            result.insert(bitKeywords[bit])
        }
        return result
    }

    /// Decode a color from a message's keyword set, or `nil` if no flag
    /// bits are present. Unknown keywords are ignored.
    public static func flagColor(from keywords: some Sequence<String>) -> FlagColor? {
        let present = Set(keywords)
        var ordinal = 0
        for (bit, keyword) in bitKeywords.enumerated() where present.contains(keyword) {
            ordinal |= (1 << bit)
        }
        guard ordinal != 0 else { return nil }
        return color(forAppleOrdinal: ordinal)
    }
}
