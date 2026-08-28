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
import BrevAI
import BrevBackend
import BrevDesign
import BrevThemes
import Foundation
import SwiftUI

/// Root view for a detached iPad compose window opened via
/// `WindowGroup(for: ComposeWindowPayload.self)`.
///
/// Resolves the backend and, for reply/forward payloads, the referenced
/// `MessageHeader` from the cache, then hands off to `ComposeView` — the
/// same view used by the sheet path. The backend passed in already owns
/// the shared `FileIMAPDraftStagingStore`, so draft persistence is
/// identical to the sheet flow (ADR-0033).
///
/// Reaches feature parity with the sheet path: it restores a saved
/// new-message recovery snapshot on open, wires AI Writer, applies
/// end-to-end-encryption send defaults, and offers multi-identity
/// ("From:" alias) sender selection. The providers backing those features
/// are injected from the app layer, mirroring `BrevMailRootView`.
public struct DetachedComposeWindowView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.brevTheme) private var theme

    private let payload: ComposeWindowPayload
    // Snapshot of the backend list captured at window-open time.
    private let backends: [any MailBackend]
    private let aiBackends: [BrevAccount.ID: any AIBackend]
    private let signatureContextProvider: ((BrevAccount) -> ComposeSignatureContext)?
    private let composeSecurityDefaultsProvider: ((BrevAccount) -> ComposeSecurityDefaultState)?
    private let trustedSigningIdentityCountProvider: ((BrevAccount) -> Int)?
    private let trustedEncryptionIdentityCountProvider: ((BrevAccount) -> Int)?

    @AppStorage(MailboxSourcePreferencesStorage.storageKey) private var mailboxSourcePreferencesData = Data()

    @State private var resolvedBackend: (any MailBackend)?
    @State private var resolvedHeader: MessageHeader?
    @State private var senderSections: [MailSourceSection] = []
    @State private var isResolving = true

    public init(
        payload: ComposeWindowPayload,
        backends: [any MailBackend],
        aiBackends: [BrevAccount.ID: any AIBackend] = [:],
        signatureContextProvider: ((BrevAccount) -> ComposeSignatureContext)? = nil,
        composeSecurityDefaultsProvider: ((BrevAccount) -> ComposeSecurityDefaultState)? = nil,
        trustedSigningIdentityCountProvider: ((BrevAccount) -> Int)? = nil,
        trustedEncryptionIdentityCountProvider: ((BrevAccount) -> Int)? = nil
    ) {
        self.payload = payload
        self.backends = backends
        self.aiBackends = aiBackends
        self.signatureContextProvider = signatureContextProvider
        self.composeSecurityDefaultsProvider = composeSecurityDefaultsProvider
        self.trustedSigningIdentityCountProvider = trustedSigningIdentityCountProvider
        self.trustedEncryptionIdentityCountProvider = trustedEncryptionIdentityCountProvider
    }

    public var body: some View {
        Group {
            // Gate on `isResolving` first so the compose view is built exactly
            // once, after the backend, quote header, and sender identities are
            // all resolved. Building it earlier would let `ComposeView` capture
            // an empty sender list or a missing reply header at init.
            if isResolving {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let backend = resolvedBackend {
                composeView(backend: backend)
            } else {
                composeUnavailablePlaceholder
            }
        }
        .task(id: payload) {
            await resolveContent()
        }
    }

    // MARK: Private

    @ViewBuilder
    private func composeView(backend: any MailBackend) -> some View {
        let account = backend.account
        let onClose: (() -> Void) = { dismissWindow(value: payload) }

        // Resolve the multi-identity "From:" selection the same way the sheet
        // path does, from the account's mailbox source sections.
        let senderResolution = ComposeSenderIdentity.resolution(
            from: senderSections,
            fallbackAccount: account,
            selectedSourceID: DetachedComposeInputs.sourceID(for: payload.kind),
            defaultSourceID: preferredDefaultSourceID(in: senderSections)
        )
        let sourceID = senderResolution.sourceID

        // Restore a previously-saved new-message draft (sheet-path parity).
        // Reply/forward payloads never carry a recovery snapshot.
        let recoveredDraft = DetachedComposeInputs.restoresRecoverySnapshot(for: payload.kind)
            ? ComposeDraftRecoveryStore.load(accountID: account.id, sourceID: sourceID)
            : nil

        let quote = DetachedComposeInputs.quoteContext(for: payload.kind, header: resolvedHeader)

        let onCompletion: (ComposeCompletion) async -> Void = { completion in
            updateComposeDraftRecovery(
                for: completion,
                accountID: account.id,
                sourceID: sourceID
            )
            // Mirror the sheet path: a sent message closes the compose surface.
            if case .sentMessage = completion {
                dismissWindow(value: payload)
            }
        }

        ComposeView(
            backend: backend,
            sourceID: sourceID,
            from: senderResolution.initialSender?.correspondent
                ?? Correspondent(name: account.displayName, email: account.emailAddress),
            senderOptions: senderResolution.options,
            initialSenderOption: senderResolution.initialSender,
            backendForSenderSource: { [backends] source in
                DetachedWindowResolver.resolveBackend(sourceID: source, in: backends) ?? backend
            },
            replyingTo: quote.replyingTo,
            replyMode: quote.replyMode,
            forwardingFrom: quote.forwardingFrom,
            recoveredDraft: recoveredDraft,
            aiBackend: aiBackend(for: account),
            signatureContext: signatureContextProvider?(account),
            composeSecurityDefaults: composeSecurityDefaultsProvider?(account) ?? .disabled,
            hasTrustedSigningIdentity: (trustedSigningIdentityCountProvider?(account) ?? 0) > 0,
            hasTrustedEncryptionIdentity: (trustedEncryptionIdentityCountProvider?(account) ?? 0) > 0,
            onClose: onClose,
            onCompletion: onCompletion
        )
    }

    @ViewBuilder
    private var composeUnavailablePlaceholder: some View {
        VStack(spacing: BrevSpacing.sm) {
            Image(systemName: "envelope.badge.exclamationmark")
                .font(.system(size: 36))
                .foregroundStyle(theme.textTertiary.color)
            Text("Compose unavailable.", bundle: .module)
                .brevFont(.body)
                .foregroundStyle(theme.textTertiary.color)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The AI backend for `account`, looked up from the injected map.
    private func aiBackend(for account: BrevAccount) -> (any AIBackend)? {
        AIBackendAccountRouter(backendsByAccountID: aiBackends).backend(for: account)
    }

    /// The account's default "From:" source, honoring the saved mailbox-source
    /// preference and falling back to the primary mailbox — mirrors
    /// `BrevMailRootView.preferredDefaultSection(in:)`.
    private func preferredDefaultSourceID(in sections: [MailSourceSection]) -> MailSourceID? {
        let preferences = MailboxSourcePreferencesStorage.decode(mailboxSourcePreferencesData) ?? .defaults
        let preferredProviderDefault = sections.first { $0.mailbox.isPrimary }?.id
        return MailboxSourcePreferencesPolicy.defaultSourceID(
            availableSourceIDs: sections.map(\.id),
            preferences: preferences,
            preferredDefaultSourceID: preferredProviderDefault
        )
    }

    /// Resolves the backend, the multi-identity sender sections, and — for
    /// reply/forward payloads — the referenced `MessageHeader` from the cache.
    ///
    /// All resolution completes before `isResolving` flips to `false`, so the
    /// compose view is constructed once with the full context. The backend is
    /// matched by `sourceID.accountID` when present, with `backends.first` as
    /// the fallback. The header is resolved from the per-folder in-memory cache
    /// by scanning all folders. If the header is not in the cache the compose
    /// window still opens, but without quote context — the reply/forward fields
    /// will be empty rather than pre-populated. This is acceptable for an
    /// early-launch cold-start; the common case is that the cache is warm when
    /// the user taps reply.
    @MainActor
    private func resolveContent() async {
        isResolving = true
        // Clear any prior resolution so a re-resolve (e.g. a `.new` payload after
        // a reply/forward) can't inherit a stale quoted header.
        resolvedHeader = nil
        defer { isResolving = false }

        let payloadSourceID = DetachedComposeInputs.sourceID(for: payload.kind)

        // Resolve the backend.
        guard let backend = DetachedWindowResolver.resolveBackend(
            sourceID: payloadSourceID,
            in: backends
        ) else {
            resolvedBackend = nil
            return
        }

        // Build the "From:" identity options before the compose view is shown.
        senderSections = await DetachedWindowResolver.resolveSenderSections(in: backend)

        // For reply/forward, resolve the referenced header for quote context.
        if let messageID = DetachedComposeInputs.messageID(for: payload.kind) {
            let folders = await (try? backend.folders()) ?? []
            resolvedHeader = await DetachedWindowResolver.resolveHeader(
                messageID: messageID,
                in: backend,
                folders: folders
            )
        }

        resolvedBackend = backend
    }
}
#endif
