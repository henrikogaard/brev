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
import Foundation
import Testing

@Suite("MailImportAction")
struct MailImportActionTests {
    @MainActor
    @Test("available action forwards typed import request")
    func forwardsTypedImportRequest() {
        let url = URL(fileURLWithPath: "/tmp/archive.mbox")
        let request = MailImportRequest(url: url, format: .mbox)
        var captured: MailImportRequest?
        let action = MailImportAction { request in
            captured = request
        }

        action(request)

        #expect(captured == request)
    }

    @MainActor
    @Test("blocked action does not forward typed import request")
    func blockedActionDoesNotForwardTypedRequest() {
        let request = MailImportRequest(url: URL(fileURLWithPath: "/tmp/message.eml"), format: .eml)
        var didRun = false
        let action = MailImportAction(isBlocked: true) { _ in
            didRun = true
        }

        action(request)

        #expect(didRun == false)
        #expect(action.isAvailable == false)
    }

    @MainActor
    @Test("URL call remains available as MBOX import compatibility path")
    func urlCallDefaultsToMBOXRequest() {
        let url = URL(fileURLWithPath: "/tmp/legacy.mbox")
        var captured: MailImportRequest?
        let action = MailImportAction { request in
            captured = request
        }

        action(url)

        #expect(captured == MailImportRequest(url: url, format: .mbox))
    }
}
