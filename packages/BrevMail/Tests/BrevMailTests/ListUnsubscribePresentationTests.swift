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
import Foundation
import Testing

@Suite("ListUnsubscribePresentation")
struct ListUnsubscribePresentationTests {
    @Test("presentation separates HTTPS and mailto actions and requires confirmation")
    func presentationSeparatesMethodsAndRequiresConfirmation() {
        let presentation = MessageListUnsubscribePresentation.resolve(
            options: ListUnsubscribeOptions(methods: [
                .https(URL(string: "https://lists.example.org/unsubscribe")!, supportsOneClick: true),
                .mailto(URL(string: "mailto:leave@example.org")!)
            ])
        )

        #expect(presentation?.title == "Unsubscribe available")
        #expect(presentation?.actions.map(\.title) == ["Open unsubscribe page", "Draft unsubscribe email"])
        #expect(presentation?.requiresExplicitConfirmation == true)
        #expect(presentation?.warning?.contains("No unsubscribe request is sent") == true)
        #expect(presentation?.actions.first?.confirmationTitle == "Open unsubscribe page?")
        #expect(presentation?.actions.first?.confirmationMessage.contains("one-click unsubscribe") == true)
        #expect(presentation?.actions.last?.confirmationTitle == "Draft unsubscribe email?")
        #expect(presentation?.actions.last?.confirmationMessage.contains("Review the message before sending") == true)
    }

    @Test("empty options do not render controls")
    func emptyOptionsDoNotRenderControls() {
        #expect(MessageListUnsubscribePresentation.resolve(
            options: ListUnsubscribeOptions(methods: [])
        ) == nil)
    }
}
