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

/// Conservative local comparisons against domains the user knows and a few brand names.
enum SenderDomainComparison {
    private static let brands = ["paypal": "paypal.com", "microsoft": "microsoft.com", "google": "google.com"]
    private static let alternateDomains = [
        "paypal": ["paypal.co.uk", "paypal.de", "paypal.fr", "paypal.com.au", "paypal.ca"],
        "microsoft": ["microsoftonline.com", "office.com"],
        "google": ["youtube.com"]
    ]

    static func claimedDomain(name: String?, domain: String, knownDomains: Set<String>) -> String? {
        guard let host = decodedHost(domain) else { return nil }
        let labels = host.split(separator: ".")
        // Honor an exact known domain or subdomain before comparing other spellings.
        let suffixes = labels.indices.map { labels[$0...].joined(separator: ".") }
        let familiar = knownDomains.union(brands.values)
        let claim = name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if let expected = brands[claim] {
            guard !suffixes.contains(expected),
                  !suffixes.contains(where: { alternateDomains[claim, default: []].contains($0) }) else { return nil }
            return expected
        }
        guard suffixes.allSatisfy({ !familiar.contains($0) }) else { return nil }

        // Align on the entire domain suffix; a brand-like subdomain on some
        // unrelated host is not evidence that the owning domain is a typo.
        return familiar.lazy.filter { target in
            let expected = target.split(separator: ".")
            guard expected.count >= 2, labels.count >= expected.count,
                  labels.suffix(expected.count - 1).elementsEqual(expected.dropFirst()),
                  let wanted = expected.first, wanted.count >= 5 else { return false }
            let actual = labels[labels.count - expected.count]
            guard abs(actual.count - wanted.count) <= 1 else { return false }
            let lhs = skeleton(actual), rhs = skeleton(wanted)
            return lhs == rhs || differsByOneEdit(lhs, rhs)
        }.min()
    }

    /// Decode IDNA locally. Accept only a host: no URL components or percent escapes.
    static func decodedHost(_ domain: String) -> String? {
        let lower = domain.lowercased()
        guard lower.utf8.count <= 253, !lower.isEmpty,
              lower.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "-" }),
              let host = URLComponents(string: "https://" + lower)?.host?.lowercased() else { return nil }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty && $0.count <= 63 }) else { return nil }
        return host
    }

    private static func skeleton(_ label: Substring) -> [Character] {
        let folded = String(label).folding(
            options: [.diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        return folded.map { character in
            switch character {
            case "а", "α": "a"
            case "е", "ε": "e"
            case "і", "ι": "i"
            case "1", "ӏ": "l"
            case "о", "ο", "0": "o"
            case "р", "ρ": "p"
            case "с": "c"
            case "х", "χ": "x"
            case "у": "y"
            default: character
            }
        }
    }

    private static func differsByOneEdit(_ lhs: [Character], _ rhs: [Character]) -> Bool {
        guard abs(lhs.count - rhs.count) <= 1 else { return false }
        var i = 0, j = 0, edits = 0
        while i < lhs.count, j < rhs.count {
            if lhs[i] == rhs[j] { i += 1; j += 1; continue }
            edits += 1
            guard edits <= 1 else { return false }
            if lhs.count >= rhs.count { i += 1 }
            if rhs.count >= lhs.count { j += 1 }
        }
        return edits + lhs.count - i + rhs.count - j == 1
    }
}
