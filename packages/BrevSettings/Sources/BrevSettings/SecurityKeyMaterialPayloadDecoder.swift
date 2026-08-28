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

public enum SecurityKeyMaterialPayloadDecoder {
    public static func materialData(
        from payload: String,
        family: SecurityKeyMaterialFamily
    ) throws -> Data {
        switch family {
        case .smime:
            return decodedSMIMEMaterial(from: payload) ?? Data(payload.utf8)
        }
    }

    private static func decodedSMIMEMaterial(from payload: String) -> Data? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let direct = Data(base64Encoded: base64Normalized(trimmed)) {
            return direct
        }

        let body = trimmed
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("-----") }
            .joined()

        return Data(base64Encoded: base64Normalized(body))
    }

    private static func base64Normalized(_ value: String) -> String {
        value.filter { !$0.isWhitespace }
    }
}
