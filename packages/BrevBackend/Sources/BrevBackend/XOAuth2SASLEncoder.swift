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

/// Encodes an XOAUTH2 SASL token for IMAP `AUTHENTICATE XOAUTH2` and
/// SMTP `AUTH XOAUTH2` commands.
///
/// The wire format is defined in RFC 7628 §3.1:
/// ```
/// base64("user=" + email + "\x01auth=Bearer " + accessToken + "\x01\x01")
/// ```
public enum XOAuth2SASLEncoder {
    /// Returns the base64-encoded SASL string for the given credentials.
    ///
    /// - Parameters:
    ///   - email: The authenticated user's email address.
    ///   - accessToken: A valid OAuth2 Bearer access token.
    /// - Returns: A base64-encoded string suitable for use as the initial
    ///   response in an XOAUTH2 SASL exchange.
    public static func encode(email: String, accessToken: String) -> String {
        // Format: "user=<email>\x01auth=Bearer <token>\x01\x01"
        let raw = "user=\(email)\u{01}auth=Bearer \(accessToken)\u{01}\u{01}"
        return Data(raw.utf8).base64EncodedString()
    }
}
