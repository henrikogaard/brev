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

#if os(iOS)
import BrevDesign
import BrevThemes
import SwiftUI
import UIKit

struct MessageListSearchField: View {
    @Environment(\.brevTheme) private var theme

    @Binding var text: String
    let prompt: String
    /// Changes to this value pull focus into the field. Supplied by
    /// `MailNavigationState.searchFocusRequestID`, so Focus Search (⌘/) works
    /// with the in-pane field the same way it does with the macOS toolbar one.
    var focusRequestID = 0
    private let configuration = MessageListSearchFieldPolicy.configuration(platform: .iOS)
    @AppStorage(MailboxViewPreferenceKey.listDensity)
    private var listDensityRaw = MailboxListDensity.comfortable.rawValue

    /// Compact density trims the band's height so a tighter list also gets a
    /// tighter search row; the field stays comfortably tappable either way.
    private var chromeHeight: CGFloat {
        let density = MailboxListDensity(rawValue: listDensityRaw) ?? .comfortable
        return max(44, density == .compact ? 32 : configuration.chromeHeight ?? 40)
    }

    var body: some View {
        HStack(spacing: BrevSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(theme.textTertiary.color)
                .accessibilityHidden(true)

            KeyboardSafeSearchTextField(
                text: $text,
                prompt: prompt,
                focusRequestID: focusRequestID,
                theme: theme
            )
            .frame(minHeight: 44)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(theme.textTertiary.color)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Clear search", bundle: .module))
            }
        }
        .padding(.leading, BrevSpacing.md)
        .padding(.trailing, text.isEmpty ? BrevSpacing.md : BrevSpacing.xs)
        .frame(minHeight: chromeHeight)
        .background(BrevWindowSurfaceBackground(role: .card))
        .overlay {
            RoundedRectangle(cornerRadius: BrevRadius.md)
                .stroke(theme.border.color, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: BrevRadius.md))
        .dynamicTypeSize(MailDenseChromeDynamicType.compactRange)
    }
}

/// Full-width search band above the message list.
///
/// The navigation bar has room for the back button and the mailbox
/// actions but not a search capsule — the old principal-slot field
/// clipped its placeholder against the action cluster. Apple Mail gives
/// search its own row above the list, so the field gets the full column
/// width and the bar stays calm. Lives inside the list's content stack,
/// directly under the navigation bar: a `safeAreaInset(edge: .top)`
/// version collided with the bar's row instead of landing below it.
struct MessageListSearchBand: View {
    @Bindable var navigation: MailNavigationState

    var body: some View {
        MessageListSearchField(
            text: $navigation.searchText,
            prompt: "Search messages",
            focusRequestID: navigation.searchFocusRequestID
        )
        .padding(.horizontal, BrevSpacing.md)
        .padding(.top, BrevSpacing.xxs)
        .background(Color.clear)
    }
}

private struct KeyboardSafeSearchTextField: UIViewRepresentable {
    @Binding var text: String
    let prompt: String
    let focusRequestID: Int
    let theme: BrevTheme

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        textField.borderStyle = .none
        textField.clearButtonMode = .never
        textField.returnKeyType = .search
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.smartDashesType = .no
        textField.smartQuotesType = .no
        textField.smartInsertDeleteType = .no
        textField.textContentType = nil
        textField.accessibilityLabel = prompt
        textField.inputAssistantItem.leadingBarButtonGroups = []
        textField.inputAssistantItem.trailingBarButtonGroups = []
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textDidChange(_:)),
            for: .editingChanged
        )
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        if textField.text != text {
            textField.text = text
        }
        textField.placeholder = prompt
        textField.textColor = UIColor(theme.textPrimary.color)
        textField.tintColor = UIColor(theme.accent.color)
        textField.attributedPlaceholder = NSAttributedString(
            string: prompt,
            attributes: [.foregroundColor: UIColor(theme.textTertiary.color)]
        )
        textField.inputAssistantItem.leadingBarButtonGroups = []
        textField.inputAssistantItem.trailingBarButtonGroups = []
        guard focusRequestID != context.coordinator.lastHandledFocusRequestID else { return }
        context.coordinator.lastHandledFocusRequestID = focusRequestID
        guard focusRequestID > 0 else { return }
        // Deferred: the field may still be joining the window when the
        // shortcut fires.
        DispatchQueue.main.async {
            textField.becomeFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding private var text: String
        var lastHandledFocusRequestID = 0

        init(text: Binding<String>) {
            _text = text
        }

        @objc
        func textDidChange(_ textField: UITextField) {
            text = textField.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}
#endif

#if os(macOS)
import AppKit
import BrevDesign
import SwiftUI

/// The message list search field on macOS.
///
/// Wraps `NSSearchField` rather than drawing a SwiftUI approximation so the
/// field gets the platform's search idiom for free: the recessed bezel, the
/// magnifying glass, the cancel button, Escape-to-clear, and the standard
/// focus ring. It is placed as a plain toolbar item in the message list
/// column's own section rather than via `.searchable`, whose window-level
/// `NSSearchToolbarItem` shifts and collapses to an icon when the AI Sidebar
/// column appears.
struct MessageListSearchField: View {
    @Binding var text: String
    let prompt: String
    /// Changes to this value pull focus into the field. Supplied by
    /// `MailNavigationState.searchFocusRequestID`.
    var focusRequestID = 0
    /// Called when the field stops editing, so the toolbar can collapse it back
    /// to a magnifying-glass button when it holds no query.
    var onEndEditing: (() -> Void)?
    private let configuration = MessageListSearchFieldPolicy.configuration(platform: .macOS)

    var body: some View {
        NativeSearchField(
            text: $text,
            prompt: prompt,
            focusRequestID: focusRequestID,
            onEndEditing: onEndEditing
        )
        .frame(height: configuration.chromeHeight ?? 24)
        .dynamicTypeSize(MailDenseChromeDynamicType.compactRange)
    }
}

private struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String
    let focusRequestID: Int
    let onEndEditing: (() -> Void)?

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.delegate = context.coordinator
        context.coordinator.startMonitoringOutsideClicks(of: searchField)
        searchField.placeholderString = prompt
        searchField.controlSize = .small
        searchField.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        searchField.sendsSearchStringImmediately = true
        // Debouncing already happens downstream in the search task; AppKit's
        // own throttle would only add a second, invisible delay.
        searchField.sendsWholeSearchString = false
        searchField.focusRingType = .default
        return searchField
    }

    func updateNSView(_ searchField: NSSearchField, context: Context) {
        if searchField.stringValue != text {
            searchField.stringValue = text
        }
        searchField.placeholderString = prompt
        context.coordinator.onEndEditing = onEndEditing
        guard focusRequestID != context.coordinator.lastHandledFocusRequestID else { return }
        context.coordinator.lastHandledFocusRequestID = focusRequestID
        guard focusRequestID > 0 else { return }
        // Deferred: the window may still be laying out the column that owns
        // this field when the menu command fires.
        DispatchQueue.main.async {
            searchField.window?.makeFirstResponder(searchField)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onEndEditing: onEndEditing)
    }

    static func dismantleNSView(_: NSSearchField, coordinator: Coordinator) {
        coordinator.stopMonitoringOutsideClicks()
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        @Binding private var text: String
        var lastHandledFocusRequestID = 0
        var onEndEditing: (() -> Void)?
        private var outsideClickMonitor: Any?

        init(text: Binding<String>, onEndEditing: (() -> Void)?) {
            _text = text
            self.onEndEditing = onEndEditing
        }

        func controlTextDidEndEditing(_: Notification) {
            onEndEditing?()
        }

        /// Clicking a message row does not resign first responder from the
        /// field — SwiftUI's list rows do not take it — so ending the edit on a
        /// click elsewhere needs an explicit monitor rather than the delegate
        /// callback alone.
        ///
        /// The hit test runs in screen coordinates because a macOS 26 toolbar
        /// hosts its item views in a window of its own, so the click and the
        /// field routinely belong to different windows.
        func startMonitoringOutsideClicks(of searchField: NSSearchField) {
            stopMonitoringOutsideClicks()
            outsideClickMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self, weak searchField] event in
                guard let self, let searchField, let window = searchField.window else { return event }
                let screenPoint = event.window?.convertPoint(toScreen: event.locationInWindow)
                    ?? NSEvent.mouseLocation
                let fieldFrame = window.convertToScreen(searchField.convert(searchField.bounds, to: nil))
                guard !fieldFrame.contains(screenPoint) else { return event }
                window.makeFirstResponder(nil)
                // Collapse here rather than relying on `controlTextDidEndEditing`
                // alone: the field is not always the first responder when the
                // click lands, and the control still has to close.
                onEndEditing?()
                return event
            }
        }

        func stopMonitoringOutsideClicks() {
            guard let outsideClickMonitor else { return }
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }

        deinit {
            guard let outsideClickMonitor else { return }
            NSEvent.removeMonitor(outsideClickMonitor)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let searchField = notification.object as? NSSearchField else { return }
            text = searchField.stringValue
        }
    }
}
#endif
