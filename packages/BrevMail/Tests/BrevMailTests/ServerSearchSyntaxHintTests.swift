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

import BrevBackend
@testable import BrevMail
import Testing

@Suite("Server search syntax hint")
struct ServerSearchSyntaxHintTests {
    @Test("generic or unavailable sources do not show a syntax hint")
    func unavailableSyntaxHidesHint() {
        #expect(!ServerSearchSyntaxHintPolicy.shouldShow(nil))
        #expect(!ServerSearchSyntaxHintPolicy.shouldShow(
            ServerSearchSyntaxDescription(
                identifier: "",
                displayName: "",
                summary: ""
            )
        ))
    }

    @Test("available syntax exposes the provider summary and examples")
    func availableSyntaxShowsHint() {
        let description = ServerSearchSyntaxDescription(
            identifier: "native-search",
            displayName: "Native search",
            summary: "Use provider operators.",
            examples: [
                ServerSearchSyntaxExample(
                    query: "from:alice@example.com",
                    explanation: "Messages from Alice."
                ),
            ]
        )

        #expect(ServerSearchSyntaxHintPolicy.shouldShow(description))
        #expect(ServerSearchSyntaxHintPolicy.examples(description) == description.examples)
    }
}
