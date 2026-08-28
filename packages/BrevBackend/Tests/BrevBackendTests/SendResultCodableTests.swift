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

@testable import BrevBackend
import Foundation
import Testing

@Suite("SendResult Codable")
struct SendResultCodableTests {
    @Test("missing warnings decode as empty warnings")
    func missingWarningsDecodeAsEmptyWarnings() throws {
        let json = #"""
        {
          "sentMessageID": "smtp-accepted",
          "scheduledFor": null
        }
        """#
        let data = try #require(json.data(using: .utf8))

        let result = try JSONDecoder().decode(SendResult.self, from: data)

        #expect(result.sentMessageID == "smtp-accepted")
        #expect(result.scheduledFor == nil)
        #expect(result.warnings == [])
    }

    @Test("warnings round trip through Codable")
    func warningsRoundTripThroughCodable() throws {
        let result = SendResult(
            sentMessageID: "smtp-accepted",
            warnings: [.queuedForRetry, .sentCopyAppendFailed, .remoteDraftCleanupFailed]
        )

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(SendResult.self, from: data)

        #expect(decoded == result)
    }
}
