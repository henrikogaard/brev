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

@testable import BrevMail
import Testing

/// Native QA on #279 showed a refused Draft's explanation twice: in the body
/// next to Close and again in the bottom error bar.
@Suite("Compose restoration status")
struct ComposeRestorationStatusTests {
    @Test("the error bar does not repeat the refusal shown in the body")
    func noDuplicateRefusal() {
        let refusal = "This draft cannot be restored safely."
        #expect(!ComposePresentation.showsErrorBanner(errorMessage: refusal, restorationError: refusal))
        #expect(ComposePresentation.showsErrorBanner(errorMessage: "Couldn't save the draft.", restorationError: refusal))
        #expect(ComposePresentation.showsErrorBanner(errorMessage: "Couldn't save the draft.", restorationError: nil))
        #expect(!ComposePresentation.showsErrorBanner(errorMessage: nil, restorationError: nil))
    }
}
