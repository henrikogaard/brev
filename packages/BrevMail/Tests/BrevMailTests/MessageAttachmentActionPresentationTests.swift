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

@Suite("MessageAttachmentActionPresentation")
struct MessageAttachmentActionPresentationTests {
    @Test("attachment rows expose Preview Save and Open actions")
    func attachmentRowsExposePreviewSaveAndOpenActions() {
        let actions = MessageAttachmentActionPresentation.actions(
            resourceAvailable: true,
            isDownloading: false,
            isWorkBlocked: false
        )

        #expect(actions.map(\.kind) == [.preview, .save, .open])
        #expect(actions.map(\.title) == ["Preview", "Save", "Open"])
        #expect(actions.map(\.systemImage) == ["eye", "arrow.down.circle", "arrow.up.forward"])
        #expect(actions.allSatisfy { !$0.isDisabled })
    }

    @Test("attachment rows keep preview primary and place file actions in overflow")
    func attachmentRowsKeepPreviewPrimaryAndPlaceFileActionsInOverflow() {
        let actions = MessageAttachmentActionPresentation.actions(
            resourceAvailable: true,
            isDownloading: false,
            isWorkBlocked: false
        )

        #expect(MessageAttachmentActionPresentation.primaryAction(in: actions)?.kind == .preview)
        #expect(MessageAttachmentActionPresentation.overflowActions(in: actions).map(\.kind) == [.save, .open])
    }

    @Test("attachment actions disable without a resource or while busy")
    func attachmentActionsDisableWithoutResourceOrWhileBusy() {
        #expect(MessageAttachmentActionPresentation.actions(
            resourceAvailable: false,
            isDownloading: false,
            isWorkBlocked: false
        ).allSatisfy { $0.isDisabled })

        #expect(MessageAttachmentActionPresentation.actions(
            resourceAvailable: true,
            isDownloading: true,
            isWorkBlocked: false
        ).allSatisfy { $0.isDisabled })

        #expect(MessageAttachmentActionPresentation.actions(
            resourceAvailable: true,
            isDownloading: false,
            isWorkBlocked: true
        ).allSatisfy { $0.isDisabled })
    }
}
