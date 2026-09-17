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

#if os(macOS)
import AppKit
@testable import BrevMail
import Testing

@Suite("Native Undo command routing")
@MainActor
struct MailUndoCommandsTests {
    @Test("mail-pane Undo invokes the focused mail action")
    func mailAction() {
        let router = MailNativeUndoRouter()
        router.textContext = { nil }
        router.windowManager = { nil }
        var calls = 0
        let mail = MailUndoCommandActions(canUndo: { true }, onUndo: { calls += 1 })
        #expect(router.canUndo(mail: mail))
        router.undo(mail: mail)
        #expect(calls == 1)
    }

    @Test("native text history takes priority and an empty editor does not fall through to mail Undo")
    func textPriority() {
        let native = UndoManager()
        native.groupsByEvent = false
        let probe = NativeUndoProbe()
        native.beginUndoGrouping()
        native.registerUndo(withTarget: probe) { $0.calls += 1 }
        native.endUndoGrouping()
        let router = MailNativeUndoRouter()
        router.textContext = { MailTextUndoContext(manager: native) }
        var mailCalls = 0
        let mail = MailUndoCommandActions(canUndo: { true }, onUndo: { mailCalls += 1 })
        router.undo(mail: mail)
        #expect(probe.calls == 1)
        #expect(mailCalls == 0)
        #expect(!router.canUndo(mail: mail))
        router.undo(mail: mail)
        #expect(mailCalls == 0)
    }

    @Test("other windows keep their native Undo")
    func otherWindows() {
        let native = UndoManager()
        native.groupsByEvent = false
        let probe = NativeUndoProbe()
        native.beginUndoGrouping()
        native.registerUndo(withTarget: probe) { $0.calls += 1 }
        native.endUndoGrouping()
        let router = MailNativeUndoRouter()
        router.textContext = { nil }
        router.windowManager = { native }
        router.undo(mail: nil)
        #expect(probe.calls == 1)
    }

    @Test("an editor without a manager cannot invoke another window's Undo")
    func absentTextManagerDoesNotFallThrough() {
        let router = MailNativeUndoRouter()
        router.textContext = { MailTextUndoContext(manager: nil) }
        let native = UndoManager()
        native.groupsByEvent = false
        let probe = NativeUndoProbe()
        native.beginUndoGrouping()
        native.registerUndo(withTarget: probe) { $0.calls += 1 }
        native.endUndoGrouping()
        router.windowManager = { native }
        router.undo(mail: nil)
        #expect(!router.canUndo(mail: nil))
        #expect(router.nativeManager() == nil)
        #expect(probe.calls == 0)
    }

    @Test("menu and editing notifications refresh command availability")
    func notificationUpdates() {
        let center = NotificationCenter()
        let state = MailUndoMenuState(center: center)
        center.post(name: NSMenu.didBeginTrackingNotification, object: nil)
        #expect(state.revision == 1)
        center.post(name: NSText.didChangeNotification, object: nil)
        #expect(state.revision == 2)
    }
}

private final class NativeUndoProbe: NSObject {
    var calls = 0
}
#endif
