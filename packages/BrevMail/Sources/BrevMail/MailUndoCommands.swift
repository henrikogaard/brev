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
import Combine
import Observation
import SwiftUI

/// Window-scoped mail Undo exposed to the menu without replacing text-editor history.
@MainActor
public struct MailUndoCommandActions {
    let canUndo: () -> Bool
    let onUndo: () -> Void

    /// Captures live availability and the owning mail window's reversal action.
    public init(canUndo: @escaping () -> Bool, onUndo: @escaping () -> Void) {
        self.canUndo = canUndo
        self.onUndo = onUndo
    }
}

private struct MailUndoCommandKey: FocusedValueKey {
    typealias Value = MailUndoCommandActions
}

public extension FocusedValues {
    /// Mail Undo for the focused scene; other scenes retain native Undo behavior.
    var mailUndoActions: MailUndoCommandActions? {
        get { self[MailUndoCommandKey.self] }
        set { self[MailUndoCommandKey.self] = newValue }
    }
}

/// Native Edit-menu shortcuts with live text-editor and mail-context routing.
@MainActor
public struct MailUndoCommands: Commands {
    @FocusedValue(\.mailUndoActions) private var mailActions
    @State private var state = MailUndoMenuState()

    /// Creates the macOS Undo/Redo command group.
    public init() {}

    public var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button(undoTitle) { state.router.undo(mail: mailActions) }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!canUndo)
            Button(redoTitle) { state.router.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!canRedo)
        }
    }

    private var undoTitle: String {
        _ = state.revision
        return state.router.undoTitle(mail: mailActions)
    }

    private var canUndo: Bool {
        _ = state.revision
        return state.router.canUndo(mail: mailActions)
    }

    private var redoTitle: String {
        _ = state.revision
        return state.router.nativeManager()?.redoMenuItemTitle ?? String(localized: "Redo", bundle: .module)
    }

    private var canRedo: Bool {
        _ = state.revision
        return state.router.nativeManager()?.canRedo == true
    }
}

/// A non-nil context identifies text editing even when its native manager has no Undo.
@MainActor
struct MailTextUndoContext {
    let manager: UndoManager?
}

@MainActor
final class MailNativeUndoRouter {
    var textContext: () -> MailTextUndoContext? = {
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { return nil }
        return MailTextUndoContext(manager: editor.undoManager)
    }

    var windowManager: () -> UndoManager? = { NSApp.keyWindow?.undoManager }

    func canUndo(mail: MailUndoCommandActions?) -> Bool {
        if let editing = textContext() { return editing.manager?.canUndo == true }
        if let mail { return mail.canUndo() }
        return windowManager()?.canUndo == true
    }

    func undoTitle(mail: MailUndoCommandActions?) -> String {
        if let editing = textContext() { return editing.manager?.undoMenuItemTitle ?? String(localized: "Undo", bundle: .module) }
        if let mail {
            return mail.canUndo() ? String(localized: "Undo Mail Action", bundle: .module) : String(
                localized: "Undo",
                bundle: .module
            )
        }
        return windowManager()?.undoMenuItemTitle ?? String(localized: "Undo", bundle: .module)
    }

    func undo(mail: MailUndoCommandActions?) {
        if let editing = textContext() {
            if editing.manager?.canUndo == true { editing.manager?.undo() }
        } else if let mail {
            if mail.canUndo() { mail.onUndo() }
        } else if let manager = windowManager(), manager.canUndo {
            manager.undo()
        }
    }

    func nativeManager() -> UndoManager? {
        if let editing = textContext() { return editing.manager }
        return windowManager()
    }

    func redo() { if let manager = nativeManager(), manager.canRedo { manager.redo() } }
}

@Observable
@MainActor
final class MailUndoMenuState {
    let router = MailNativeUndoRouter()
    private(set) var revision = 0
    @ObservationIgnored private var observations: Set<AnyCancellable> = []

    init(center: NotificationCenter = .default) {
        let names: [Notification.Name] = [
            NSMenu.didBeginTrackingNotification,
            NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
            NSText.didBeginEditingNotification, NSText.didEndEditingNotification, NSText.didChangeNotification,
            .NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange,
            .NSUndoManagerDidCloseUndoGroup
        ]
        for name in names {
            center.publisher(for: name).sink { [weak self] _ in
                if Thread.isMainThread {
                    MainActor.assumeIsolated { self?.revision &+= 1 }
                } else {
                    Task { @MainActor [weak self] in self?.revision &+= 1 }
                }
            }.store(in: &observations)
        }
    }
}
#endif
