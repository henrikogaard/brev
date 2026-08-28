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

/// Encodes `application/x-www-form-urlencoded` request bodies for the OAuth
/// token endpoints.
///
/// `URLComponents.percentEncodedQuery` is deliberately NOT used: it applies URL
/// *query* encoding, which leaves `+` and `/` literal. A form-body parser
/// decodes a literal `+` as a space (WHATWG/RFC 1866 form serialization), so a
/// value containing `+` arrives corrupted at the server. Microsoft refresh
/// tokens and authorization codes are opaque standard-base64 blobs that
/// routinely contain `+` and `/`, so the query encoder silently broke every
/// token refresh (`invalid_grant` → forced re-sign-in).
///
/// Here each key and value is percent-encoded leaving only the RFC 3986
/// unreserved set literal, so `+`, `/`, `=`, `&`, and space are all escaped.
/// Keys are sorted for a deterministic, testable body; order is irrelevant to
/// the server.
enum OAuthFormEncoding {
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    static func encode(_ items: [String: String]) -> Data {
        let body = items
            .sorted { $0.key < $1.key }
            .map { "\(escape($0.key))=\(escape($0.value))" }
            .joined(separator: "&")
        return Data(body.utf8)
    }

    private static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }
}
