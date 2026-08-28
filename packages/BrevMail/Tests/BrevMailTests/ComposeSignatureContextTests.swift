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

@Suite("ComposeSignatureContext")
struct ComposeSignatureContextTests {
    @Test("selected signature resolves when the id exists")
    func selectedSignatureResolvesWhenTheIDExists() {
        let context = ComposeSignatureContext(
            selectedSignatureID: "sig-2",
            options: [
                ComposeSignatureOption(id: "sig-1", title: "Work", body: "Work sig"),
                ComposeSignatureOption(id: "sig-2", title: "Home", body: "Home sig")
            ]
        )

        #expect(context.selectedSignature?.id == "sig-2")
        #expect(context.selectedSignature?.body == "Home sig")
    }

    @Test("selected signature stays nil when no id is selected")
    func selectedSignatureStaysNilWhenNoIDIsSelected() {
        let context = ComposeSignatureContext(
            selectedSignatureID: nil,
            options: [
                ComposeSignatureOption(id: "sig-1", title: "Work", body: "Work sig")
            ]
        )

        #expect(context.selectedSignature == nil)
    }
}
