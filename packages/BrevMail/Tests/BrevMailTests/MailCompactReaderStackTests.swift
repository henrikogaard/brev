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

#if canImport(AppKit)
import AppKit
@testable import BrevMail
import Observation
import SwiftUI
import Testing

@Suite("Compact reader stack")
@MainActor
struct MailCompactReaderStackTests {
    @Test("presenting and dismissing the reader keeps the mailbox mounted")
    func readerPresentationKeepsMailboxMounted() async {
        let model = CompactReaderRetentionModel()
        let host = NSHostingController(
            rootView: CompactReaderRetentionHarness(model: model)
                .frame(width: 390, height: 780)
        )
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 780)

        await settle(host)
        #expect(model.mailboxAppearances == 1)
        #expect(model.mailboxDisappearances == 0)

        model.isReaderPresented = true
        await settle(host)
        #expect(model.mailboxAppearances == 1)
        #expect(model.mailboxDisappearances == 0)

        model.isReaderPresented = false
        await settle(host)
        #expect(model.mailboxAppearances == 1)
        #expect(model.mailboxDisappearances == 0)
    }

    private func settle(_ host: NSHostingController<some View>) async {
        host.view.needsLayout = true
        host.view.layoutSubtreeIfNeeded()
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(20))
        host.view.layoutSubtreeIfNeeded()
    }
}

@Observable
@MainActor
private final class CompactReaderRetentionModel {
    var isReaderPresented = false
    var mailboxAppearances = 0
    var mailboxDisappearances = 0
}

private struct CompactReaderRetentionHarness: View {
    @Bindable var model: CompactReaderRetentionModel

    var body: some View {
        MailCompactReaderStack(
            isReaderPresented: model.isReaderPresented,
            background: {
                Text("Mailbox")
                    .onAppear { model.mailboxAppearances += 1 }
                    .onDisappear { model.mailboxDisappearances += 1 }
            },
            reader: model.isReaderPresented ? AnyView(Text("Reader")) : nil
        )
    }
}
#endif
