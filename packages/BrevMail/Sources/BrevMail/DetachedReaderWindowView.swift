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

/// Root view for a detached iPad reader window opened via `WindowGroup(for: DetachedReaderWindowPayload.self)`.
///
/// Resolves the backend and message header from the payload ids, then
/// delegates rendering to `MessageDetailView` — the same view and body-loading
/// path used in the main three-column layout.
public struct DetachedReaderWindowView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.brevTheme) private var theme

    private let payload: DetachedReaderWindowPayload
    // Snapshot of the backend list captured at window-open time. Will not
    // reflect account add/remove while this window is open — acceptable
    // because detached reader windows are short-lived.
    private let backends: [any MailBackend]

    @State private var resolvedHeader: MessageHeader?
    @State private var resolvedBackend: (any MailBackend)?
    @State private var resolvedFolders: [Folder] = []
    @State private var isResolving = true

    public init(payload: DetachedReaderWindowPayload, backends: [any MailBackend]) {
        self.payload = payload
        self.backends = backends
    }

    public var body: some View {
        // The detached scene's root must supply a toolbar host, otherwise the
        // `.toolbar` items inside `MessageDetailView` (Print, Export PDF, and
        // "Open in New Window") have nowhere to attach and are silently dropped.
        // In the main window the reader inherits a host from the three-column
        // navigation container; here we wrap it in a `NavigationStack` to give it
        // the same. This closes the "detached reader is missing `.toolbar`
        // actions" v1 limitation recorded in ADR-0033. The title is shown inline
        // so the bar stays compact above the in-content `windowActionBar` rather
        // than reserving space for a large title.
        NavigationStack {
            Group {
                if let backend = resolvedBackend {
                    MessageDetailView(
                        backend: backend,
                        sourceID: payload.sourceID,
                        header: resolvedHeader,
                        navigation: nil,
                        allFolders: resolvedFolders,
                        closeWindow: { dismissWindow(value: payload) }
                    )
                    .brevMailPaneSurface(.content)
                } else if isResolving {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    messageUnavailablePlaceholder
                }
            }
            .navigationTitle(resolvedHeader?.subject ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: payload) {
                await resolveContent()
            }
        }
    }

    // MARK: Private

    @ViewBuilder
    private var messageUnavailablePlaceholder: some View {
        VStack(spacing: BrevSpacing.sm) {
            Image(systemName: "envelope.badge.exclamationmark")
                .font(.system(size: 36))
                .foregroundStyle(theme.textTertiary.color)
            Text("Message unavailable.", bundle: .module)
                .brevFont(.body)
                .foregroundStyle(theme.textTertiary.color)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Resolves the backend and message header from the payload.
    ///
    /// Backend is matched by `sourceID.accountID` when a source is present,
    /// or falls through to the first available backend. The header is fetched
    /// from the backend's in-memory cache by scanning all folder caches; if
    /// the cache is cold the view still renders (showing a loading skeleton
    /// from `MessageDetailView`) because the body-loading path only needs the
    /// header id, not the full header metadata.
    @MainActor
    private func resolveContent() async {
        isResolving = true
        defer { isResolving = false }

        guard let backend = DetachedWindowResolver.resolveBackend(
            sourceID: payload.sourceID,
            in: backends
        ) else {
            resolvedBackend = nil
            return
        }
        resolvedBackend = backend

        // Fetch folders so we can (a) pass them to the reader for Move/Junk
        // actions, and (b) give the header lookup its search space. Non-fatal
        // on failure: the reader still works without folders.
        let folders = await (try? backend.folders()) ?? []
        resolvedFolders = folders

        // Cold-start path: if the header is not cached the view still renders
        // (MessageDetailView shows a placeholder until mail syncs).
        resolvedHeader = await DetachedWindowResolver.resolveHeader(
            messageID: payload.messageID,
            in: backend,
            folders: folders
        )
    }
}
#endif
