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

@testable import BrevCalendar
import Foundation
import Testing

@Suite("PIMErrorText")
struct PIMErrorTextTests {
    private enum ServiceError: LocalizedError {
        case missingCredential

        var errorDescription: String? {
            "The source has no stored credential. Reconnect it first."
        }
    }

    private enum BareError: Error {
        case missingCredential
    }

    @Test("LocalizedError descriptions beat the raw enum case name")
    func localizedErrorText() {
        #expect(
            PIMErrorText.text(for: ServiceError.missingCredential)
                == "The source has no stored credential. Reconnect it first."
        )
    }

    @Test("A domain enum without errorDescription still gets readable text")
    func syncServiceErrorText() {
        #expect(
            PIMErrorText.text(
                for: PIMEventSyncServiceError.missingCredential
            )
                == "The source has no stored credential. Reconnect it first."
        )
        #expect(
            PIMErrorText.text(for: PIMEventSyncServiceError.missingCredential)
                != "missingCredential"
        )
    }

    @Test("Plain errors fall back to localizedDescription")
    func plainErrorFallback() {
        let text = PIMErrorText.text(for: BareError.missingCredential)
        #expect(!text.isEmpty)
        // The fallback path must at least differ from LocalizedError
        // handling, not crash — Foundation renders it via NSError.
        #expect(text == BareError.missingCredential.localizedDescription)
    }
}
