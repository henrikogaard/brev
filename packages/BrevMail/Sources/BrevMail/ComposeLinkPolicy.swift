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

/// Pure URL validation and normalization for compose links.
enum ComposeLinkPolicy {
    /// Normalizes and validates a URL string for use in compose.
    ///
    /// Trims whitespace; allows only http/https/mailto schemes.
    /// Bare domains are prefixed with https://, bare emails with mailto:.
    /// Dangerous or empty inputs return nil.
    static func normalizedURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)

        // Reject empty strings
        if trimmed.isEmpty {
            return nil
        }

        // If it contains :// then it's already a full URL with scheme
        if trimmed.contains("://") {
            guard let url = URL(string: trimmed) else {
                return nil
            }
            // Only allow http and https
            guard let scheme = url.scheme, ["http", "https"].contains(scheme) else {
                return nil
            }
            return url
        }

        // Check if it looks like a bare email (contains @, no spaces, and basic email pattern)
        let emailPattern = "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$"
        if let regex = try? NSRegularExpression(pattern: emailPattern, options: []),
           regex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
            // This is a bare email, prefix with mailto:
            if let url = URL(string: "mailto:\(trimmed)") {
                return url
            }
            return nil
        }

        // Check if it looks like a bare host (contains . and no spaces)
        if trimmed.contains(".") && !trimmed.contains(" ") {
            // This is likely a bare domain, prefix with https://
            if let url = URL(string: "https://\(trimmed)") {
                return url
            }
            return nil
        }

        // Anything else is rejected
        return nil
    }
}
