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
import BrevBackend
import BrevDesign
import BrevThemes
import SwiftUI
import UIKit

/// What the system search field offers for the visible list (audit Q1, Q2).
struct MailListSearchConfiguration: Equatable {
    /// "Current mailbox" / "All mailboxes" scope bar. Only folder lists have a folder to scope to.
    var showsMailboxScope: Bool
    /// "From" and "Subject" field tokens, which the folder list's field scope implements.
    var offersFieldTokens: Bool
    /// Quick filters, senders and recents. Off for the attachments pane, which has its own query.
    var offersSuggestions: Bool
    /// Search locations the backend supports (local, automatic, server).
    var availableExecutions: [SearchExecution]
}

extension View {
    /// Gives a mail list the system search field: scopes, tokens and local suggestions.
    func mailListSearch(
        navigation: MailNavigationState,
        configuration: MailListSearchConfiguration
    ) -> some View {
        modifier(MailListSearchModifier(navigation: navigation, configuration: configuration))
    }
}

private struct MailListSearchModifier: ViewModifier {
    @Bindable var navigation: MailNavigationState
    let configuration: MailListSearchConfiguration

    @State private var isPresented = false
    @State private var recents = MailRecentSearches.load()

    private var mailboxScope: Binding<MailSearchMailboxScope> {
        Binding(
            get: { MailSearchMailboxScope(searchesAllFolders: navigation.searchAllMailboxes) },
            set: { navigation.searchAllMailboxes = $0.searchesAllFolders }
        )
    }

    /// Before iOS 26 the field would otherwise hide above the list until pulled down.
    private var placement: SearchFieldPlacement {
        if #available(iOS 26.0, *) { .automatic } else { .navigationBarDrawer(displayMode: .always) }
    }

    func body(content: Content) -> some View {
        content
            .searchable(
                text: $navigation.searchFreeText,
                tokens: $navigation.searchTokens,
                isPresented: $isPresented,
                placement: placement,
                prompt: Text("Search messages", bundle: .module)
            ) { token in
                Label(token.title, systemImage: token.symbolName)
            }
            .searchScopes(mailboxScope, activation: .onSearchPresentation) {
                if configuration.showsMailboxScope {
                    Text("Current mailbox", bundle: .module).tag(MailSearchMailboxScope.currentMailbox)
                    Text("All mailboxes", bundle: .module).tag(MailSearchMailboxScope.allMailboxes)
                }
            }
            .searchSuggestions { suggestionRows }
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onSubmit(of: .search) { submit() }
            // Focus Search (the keyboard shortcut) presents the field the way tapping it does.
            .onChange(of: navigation.searchFocusRequestID) { isPresented = true }
            // Cancel dismisses search and takes the query, its tokens and the scope with it.
            .onChange(of: isPresented) { _, presented in
                if !presented { navigation.clearSearch() }
            }
    }

    private func submit() {
        navigation.commitSearch()
        if configuration.offersSuggestions {
            recents = MailRecentSearches.adding(navigation.searchFreeText, to: recents)
            MailRecentSearches.save(recents)
        }
    }

    private var suggestions: MailSearchSuggestionSet {
        guard configuration.offersSuggestions else { return MailSearchSuggestionSet() }
        return MailSearchSuggestions.make(
            typedText: navigation.searchFreeText,
            tokens: navigation.searchTokens,
            headers: navigation.currentFolderHeaders,
            recents: recents,
            offersFieldTokens: configuration.offersFieldTokens
        )
    }

    @ViewBuilder
    private var suggestionRows: some View {
        let set = suggestions
        if !set.recents.isEmpty {
            Section {
                ForEach(set.recents, id: \.self) { recent in
                    Label(recent, systemImage: "clock")
                        .searchCompletion(recent)
                }
            } header: {
                HStack {
                    Text("Recent searches", bundle: .module)
                    Spacer()
                    Button {
                        recents = []
                        MailRecentSearches.save([])
                    } label: {
                        Text("Clear", bundle: .module)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(String(localized: "Clear recent searches", bundle: .module))
                }
            }
        }
        if !set.fieldTokens.isEmpty {
            Section {
                ForEach(set.fieldTokens) { token in
                    Button {
                        MailSearchTokens.add(token, to: &navigation.searchTokens)
                    } label: {
                        Label(fieldTokenTitle(token), systemImage: token.symbolName)
                    }
                }
            }
        }
        if !set.quickFilters.isEmpty {
            Section {
                ForEach(set.quickFilters) { token in
                    Label(token.title, systemImage: token.symbolName)
                        .searchCompletion(token)
                }
            } header: {
                Text("Suggested filters", bundle: .module)
            }
        }
        if !set.senders.isEmpty {
            Section {
                ForEach(set.senders) { sender in
                    Label(sender.displayName, systemImage: "person.crop.circle")
                        .searchCompletion(sender.token)
                }
            } header: {
                Text("Senders", bundle: .module)
            }
        }
        if navigation.searchFreeText.isEmpty, configuration.availableExecutions.count > 1 {
            Section {
                ForEach(configuration.availableExecutions, id: \.self) { execution in
                    Button {
                        navigation.hasUserSelectedSearchExecution = true
                        navigation.searchExecution = execution
                    } label: {
                        HStack {
                            Label(execution.messageListTitle, systemImage: execution.messageListSymbolName)
                            Spacer()
                            if execution == navigation.searchExecution {
                                Image(systemName: "checkmark").accessibilityHidden(true)
                            }
                        }
                    }
                    .accessibilityAddTraits(execution == navigation.searchExecution ? .isSelected : [])
                }
            } header: {
                Text("Search location", bundle: .module)
            }
        }
    }

    /// "Search in From" / "Search in Subject": the typed text becomes that field's value.
    private func fieldTokenTitle(_ token: MailSearchToken) -> String {
        switch token {
        case .field(.from): String(localized: "Search in From", bundle: .module)
        case .field(.subject): String(localized: "Search in Subject", bundle: .module)
        default: token.title
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
