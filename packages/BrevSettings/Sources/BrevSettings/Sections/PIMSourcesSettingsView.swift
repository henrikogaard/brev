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

import BrevBackend
import BrevCalendar
import BrevDesign
import BrevThemes
import SwiftUI

// MARK: - Row presentation

/// Everything a source row displays, derived from the record and the
/// shared status presenter (ADR-0072). Action availability is decided
/// here so the view never interprets lifecycle state itself.
struct PIMSourceRowPresentation: Sendable, Hashable, Identifiable {
    let id: PIMSource.ID
    let displayName: String
    /// "Provider · Kind" — e.g. "CalDAV · Calendar".
    let subtitle: String
    let statusTitle: String
    let statusSymbolName: String
    let statusDetail: String?
    let syncEnabled: Bool
    let canToggleSync: Bool
    let canDisconnect: Bool
    let canReconnect: Bool
    let canRemove: Bool
    /// Whether the source can refresh its collection list — connected or
    /// retryable after a failure.
    let canRefreshCollections: Bool
    /// Whether the source can run an item sync now — sources that
    /// finished connecting, plus retryable failures.
    let canSyncNow: Bool

    init(source: PIMSource) {
        let status = PIMSourceStatusPresenter.presentation(for: source.status)
        id = source.id
        displayName = source.displayName
        subtitle = Self.subtitle(provider: source.provider, kind: source.kind)
        statusTitle = status.title
        statusSymbolName = status.symbolName
        statusDetail = source.statusDetail
        syncEnabled = source.syncEnabled

        let connected: Set<PIMSourceStatus> = [.ready, .syncing, .permissionLimited]
        canToggleSync = connected.contains(source.status)
        canDisconnect = connected.contains(source.status)
        canReconnect = [.disconnected, .authenticationRequired, .failed].contains(source.status)
        canRemove = source.status != .connecting
        canRefreshCollections = connected.contains(source.status)
            || source.status == .failed
        canSyncNow = connected.contains(source.status)
            || source.status == .failed
    }

    private static func subtitle(provider: PIMSourceProvider, kind: PIMSourceKind) -> String {
        let providerTitle = switch provider {
        case .google: String(localized: "Google", bundle: .module)
        case .calDAV: "CalDAV"
        case .cardDAV: "CardDAV"
        }
        let kindTitle = switch kind {
        case .calendar: String(localized: "Calendar", bundle: .module)
        case .contacts: String(localized: "Contacts", bundle: .module)
        case .tasks: String(localized: "Tasks", bundle: .module)
        }
        return providerTitle + " · " + kindTitle
    }
}

// MARK: - Sources group

/// The connected-source list inside Calendar & Contacts settings.
///
/// Rows report state through the shared presenter and offer the lifecycle
/// actions valid for that state: sync opt-in, disconnect, reconnect, and
/// removal with the ADR-0072 two-step cache choice. Google enablement is
/// listed as "Not available yet" until feature-triggered reauthorization
/// ships — never labeled ready.
struct PIMSourcesSettingsView: View {
    @Environment(\.brevTheme) private var theme

    let model: PIMSourceSettingsModel
    /// Google mail accounts eligible for feature enablement. Empty in
    /// previews and sessions without a Google account.
    let googleAccounts: [BrevAccount]

    @State private var isShowingConnectSheet = false
    @State private var reconnectSource: PIMSource?
    @State private var removalCandidate: PIMSource?

    var body: some View {
        SettingsGroup(
            title: String(localized: "Sources", bundle: .module),
            subtitle: String(
                localized: "Optional Google and DAV connections that power calendar and contacts features.",
                bundle: .module
            ),
            symbolName: "person.crop.rectangle.stack"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                if let lastError = model.lastError {
                    SettingsInfoCallout(
                        symbolName: "exclamationmark.triangle",
                        message: lastError,
                        tone: .warning
                    )
                }

                if model.sources.isEmpty, !model.isLoading {
                    Text(String(localized: "No sources connected yet.", bundle: .module))
                        .brevFont(.footnote)
                        .foregroundStyle(theme.textSecondary.color)
                }

                ForEach(Array(model.sources.enumerated()), id: \.element.id) { index, source in
                    sourceRow(PIMSourceRowPresentation(source: source))
                    if index < model.sources.count - 1 {
                        Divider()
                    }
                }

                HStack(spacing: BrevSpacing.sm) {
                    Button {
                        isShowingConnectSheet = true
                    } label: {
                        Label(
                            String(localized: "Add DAV Source…", bundle: .module),
                            systemImage: "plus"
                        )
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint(String(
                        localized: "Connect a CalDAV or CardDAV source",
                        bundle: .module
                    ))
                }
                .padding(.top, BrevSpacing.xxs)

                googleRows
            }
        }
        .sheet(isPresented: $isShowingConnectSheet) {
            PIMSourceConnectSheet(
                title: String(localized: "Add DAV Source", bundle: .module),
                submitTitle: String(localized: "Connect", bundle: .module),
                showsEndpointFields: true,
                isSubmitting: model.isConnecting
            ) { form in
                await model.connectDAV(form)
            }
        }
        .sheet(item: $reconnectSource) { source in
            PIMSourceConnectSheet(
                title: String(localized: "Reconnect Source", bundle: .module),
                submitTitle: String(localized: "Reconnect", bundle: .module),
                showsEndpointFields: false,
                isSubmitting: model.pendingSourceID == source.id
            ) { form in
                await model.reconnect(sourceID: source.id, form: form)
            }
        }
        .confirmationDialog(
            String(localized: "Remove source?", bundle: .module),
            isPresented: removalBinding,
            presenting: removalCandidate
        ) { source in
            Button(String(localized: "Remove, keep cached copy", bundle: .module)) {
                Task { await model.remove(sourceID: source.id, deleteCachedContent: false) }
            }
            Button(String(localized: "Remove and delete cached data", bundle: .module), role: .destructive) {
                Task { await model.remove(sourceID: source.id, deleteCachedContent: true) }
            }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) {}
        } message: { source in
            Text(String(
                localized: "Brev stops all work for \(source.displayName) and deletes its unsent drafts. Provider data is never deleted. A kept cache stays readable but disconnected.",
                bundle: .module
            ))
        }
    }

    private var removalBinding: Binding<Bool> {
        Binding(
            get: { removalCandidate != nil },
            set: { isPresented in
                if !isPresented {
                    removalCandidate = nil
                }
            }
        )
    }

    // MARK: - Rows

    private func sourceRow(_ row: PIMSourceRowPresentation) -> some View {
        HStack(alignment: .top, spacing: BrevSpacing.sm) {
            Image(systemName: row.statusSymbolName)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(statusColor(for: row))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                Text(row.displayName)
                    .brevFont(.subheadline)
                    .foregroundStyle(theme.textPrimary.color)
                Text(row.subtitle + " · " + row.statusTitle)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                if let detail = row.statusDetail {
                    Text(detail)
                        .brevFont(.caption)
                        .foregroundStyle(theme.warning.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                collectionList(for: row)
            }
            Spacer(minLength: BrevSpacing.sm)
            if model.pendingSourceID == row.id {
                ProgressView()
                    .controlSize(.small)
            }
            if row.canToggleSync {
                Toggle(
                    String(localized: "Sync", bundle: .module),
                    isOn: syncBinding(for: row.id, enabled: row.syncEnabled)
                )
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel(String(
                    localized: "Background sync for \(row.displayName)",
                    bundle: .module
                ))
                .disabled(model.pendingSourceID == row.id)
            }
            if model.canToggleWrite(sourceID: row.id) {
                Toggle(
                    String(localized: "Editing", bundle: .module),
                    isOn: writeBinding(for: row.id)
                )
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel(String(
                    localized: "Editing for \(row.displayName)",
                    bundle: .module
                ))
                .disabled(model.pendingSourceID == row.id)
            }
            sourceMenu(row)
        }
        .padding(.vertical, BrevSpacing.xxs)
    }

    /// The discovered collections under a source row. Each toggles
    /// whether it participates in sync and browsing; provider colors show
    /// as the leading dot via the theme hex parser.
    @ViewBuilder
    private func collectionList(
        for row: PIMSourceRowPresentation
    ) -> some View {
        let collections = model.collectionsBySource[row.id] ?? []
        if !collections.isEmpty {
            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                ForEach(collections) { collection in
                    collectionRow(collection, sourceID: row.id)
                }
                if let count = model.eventCountsBySource[row.id] {
                    Text(String(
                        localized: "\(count) events cached",
                        bundle: .module
                    ))
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                }
                if let count = model.contactCountsBySource[row.id] {
                    Text(String(
                        localized: "\(count) contacts cached",
                        bundle: .module
                    ))
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                }
            }
            .padding(.top, BrevSpacing.xxs)
        } else if row.canRefreshCollections, model.canManageCollections {
            Text(String(
                localized: "No collections discovered yet.",
                bundle: .module
            ))
            .brevFont(.caption)
            .foregroundStyle(theme.textSecondary.color)
            .padding(.top, BrevSpacing.xxs)
        }
    }

    private func collectionRow(
        _ collection: PIMCollection,
        sourceID: PIMSource.ID
    ) -> some View {
        HStack(spacing: BrevSpacing.xs) {
            Circle()
                .fill(collectionColor(for: collection))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(collection.displayName)
                .brevFont(.caption)
                .foregroundStyle(theme.textPrimary.color)
            if collection.isPrimary {
                Text(String(localized: "Primary", bundle: .module))
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
            }
            if collection.isReadOnly {
                Image(systemName: "lock")
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                    .accessibilityLabel(String(
                        localized: "Read-only",
                        bundle: .module
                    ))
            }
            Spacer(minLength: BrevSpacing.xs)
            Toggle(
                String(localized: "Visible", bundle: .module),
                isOn: collectionVisibilityBinding(
                    for: collection,
                    sourceID: sourceID
                )
            )
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.mini)
            .accessibilityLabel(String(
                localized: "Show \\(collection.displayName)",
                bundle: .module
            ))
            .disabled(model.pendingSourceID == sourceID)
        }
    }

    private func collectionColor(for collection: PIMCollection) -> Color {
        guard let hex = collection.colorHex else {
            return theme.textSecondary.color
        }
        return BrevColor(hex).color
    }

    private func collectionVisibilityBinding(
        for collection: PIMCollection,
        sourceID: PIMSource.ID
    ) -> Binding<Bool> {
        Binding(
            get: { collection.isVisible },
            set: { isVisible in
                Task {
                    await model.setCollectionVisible(
                        isVisible,
                        collectionID: collection.id,
                        sourceID: sourceID
                    )
                }
            }
        )
    }

    private func sourceMenu(_ row: PIMSourceRowPresentation) -> some View {
        Menu {
            if row.canSyncNow, model.canSyncNow(sourceID: row.id) {
                Button {
                    Task { await model.syncNow(sourceID: row.id) }
                } label: {
                    Label(
                        String(localized: "Sync Now", bundle: .module),
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                }
            }
            if row.canRefreshCollections, model.canManageCollections {
                Button {
                    Task { await model.refreshCollections(sourceID: row.id) }
                } label: {
                    Label(
                        String(localized: "Refresh Collections", bundle: .module),
                        systemImage: "arrow.clockwise"
                    )
                }
            }
            if row.canReconnect {
                Button {
                    if let source = model.sources.first(where: { $0.id == row.id }) {
                        reconnectSource = source
                    }
                } label: {
                    Label(String(localized: "Reconnect…", bundle: .module), systemImage: "arrow.triangle.2.circlepath")
                }
            }
            if row.canDisconnect {
                Button {
                    Task { await model.disconnect(sourceID: row.id) }
                } label: {
                    Label(String(localized: "Disconnect", bundle: .module), systemImage: "cable.connector")
                }
            }
            if row.canRemove {
                Divider()
                Button(role: .destructive) {
                    if let source = model.sources.first(where: { $0.id == row.id }) {
                        removalCandidate = source
                    }
                } label: {
                    Label(String(localized: "Remove Source…", bundle: .module), systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(theme.textSecondary.color)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(model.pendingSourceID == row.id)
    }

    /// Google enablement rows. When the session wires reauthorization,
    /// each Google account offers a button per PIM kind not yet enabled;
    /// otherwise the feature is listed as not available yet — never
    /// labeled ready (ADR-0072).
    @ViewBuilder
    private var googleRows: some View {
        if model.canEnableGoogleFeatures, !googleAccounts.isEmpty {
            ForEach(googleAccounts) { account in
                googleAccountRow(account)
            }
        } else {
            googlePlaceholderRow
        }
    }

    private func googleAccountRow(_ account: BrevAccount) -> some View {
        let enabledKinds = Set(
            model.sources
                .filter { $0.provider == .google && $0.linkedAccountID == account.id }
                .map(\.kind)
        )
        let missingKinds = PIMSourceKind.allCases.filter { !enabledKinds.contains($0) }
        return Group {
            if missingKinds.isEmpty {
                EmptyView()
            } else {
                HStack(alignment: .top, spacing: BrevSpacing.sm) {
                    Image(systemName: "g.circle")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(theme.textSecondary.color)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                        Text(account.emailAddress)
                            .brevFont(.subheadline)
                            .foregroundStyle(theme.textPrimary.color)
                        Text(String(localized: "Google", bundle: .module))
                            .brevFont(.caption)
                            .foregroundStyle(theme.textSecondary.color)
                        HStack(spacing: BrevSpacing.xs) {
                            ForEach(missingKinds, id: \.self) { kind in
                                Button {
                                    Task {
                                        await model.enableGoogleFeature(
                                            accountID: account.id,
                                            kind: kind
                                        )
                                    }
                                } label: {
                                    Text(googleKindButtonTitle(kind))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(model.pendingGoogleAccountID == account.id)
                            }
                            if model.pendingGoogleAccountID == account.id {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                        .padding(.top, BrevSpacing.xxs)
                    }
                }
                .padding(.vertical, BrevSpacing.xxs)
            }
        }
    }

    private func googleKindButtonTitle(_ kind: PIMSourceKind) -> String {
        switch kind {
        case .calendar:
            return String(localized: "Enable Calendar", bundle: .module)
        case .contacts:
            return String(localized: "Enable Contacts", bundle: .module)
        case .tasks:
            return String(localized: "Enable Tasks", bundle: .module)
        }
    }

    /// Shown when no Google reauthorization path exists in this session —
    /// the feature is listed as unavailable rather than hidden so the
    /// surface never implies the option does not exist.
    private var googlePlaceholderRow: some View {
        HStack(alignment: .top, spacing: BrevSpacing.sm) {
            Image(systemName: "g.circle")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.textTertiary.color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                HStack(spacing: BrevSpacing.xs) {
                    Text(String(localized: "Google Calendar & Contacts", bundle: .module))
                        .brevFont(.subheadline)
                        .foregroundStyle(theme.textTertiary.color)
                    Text(String(localized: "Not available yet", bundle: .module))
                        .brevFont(.caption)
                        .foregroundStyle(theme.textTertiary.color)
                        .padding(.horizontal, BrevSpacing.xxs)
                        .padding(.vertical, 1)
                        .brevQuietSurface(cornerRadius: BrevRadius.sm)
                }
                Text(String(
                    localized: "Enable PIM features on a connected Google account with feature-triggered authorization.",
                    bundle: .module
                ))
                .brevFont(.caption)
                .foregroundStyle(theme.textTertiary.color)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, BrevSpacing.xxs)
    }

    private func syncBinding(for sourceID: PIMSource.ID, enabled: Bool) -> Binding<Bool> {
        Binding(
            get: { enabled },
            set: { newValue in
                Task { await model.setSyncEnabled(newValue, for: sourceID) }
            }
        )
    }

    private func writeBinding(for sourceID: PIMSource.ID) -> Binding<Bool> {
        Binding(
            get: { model.isWriteEnabled(sourceID: sourceID) },
            set: { newValue in
                Task { await model.setWriteEnabled(newValue, for: sourceID) }
            }
        )
    }

    private func statusColor(for row: PIMSourceRowPresentation) -> Color {
        guard let source = model.sources.first(where: { $0.id == row.id }) else {
            return theme.textTertiary.color
        }
        return switch source.status {
        case .ready: theme.success.color
        case .syncing, .connecting: theme.info.color
        case .disconnected: theme.textTertiary.color
        case .permissionLimited, .authenticationRequired: theme.warning.color
        case .failed: theme.danger.color
        }
    }
}

// MARK: - Connect sheet

/// Form sheet for connecting a DAV source or re-entering credentials on
/// reconnect. Endpoint fields are hidden in reconnect mode — the endpoint
/// is already stored and only the credential changes.
struct PIMSourceConnectSheet: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    let title: String
    let submitTitle: String
    let showsEndpointFields: Bool
    let isSubmitting: Bool
    /// Returns true when the action succeeded and the sheet should close.
    let onSubmit: (PIMDAVConnectForm) async -> Bool

    @State private var form = PIMDAVConnectForm()
    @State private var didAttemptSubmit = false

    var body: some View {
        NavigationStack {
            SwiftUI.Form(content: {
                if showsEndpointFields {
                    Section(String(localized: "Source", bundle: .module)) {
                        kindPicker
                    }
                    Section(
                        header: Text(String(localized: "Server", bundle: .module)),
                        footer: Text(endpointFooter)
                    ) {
                        endpointFields
                    }
                }
                Section(
                    header: Text(String(localized: "Sign in", bundle: .module)),
                    footer: Text(
                        String(
                            localized: "Credentials are stored in Keychain and used only for this source.",
                            bundle: .module
                        )
                    )
                ) {
                    credentialFields
                }
                if showsEndpointFields {
                    Section(String(localized: "Display name", bundle: .module)) {
                        displayNameField
                    }
                }
                issueCallouts
            })
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .navigationTitle(title)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Cancel", bundle: .module)) {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(submitTitle) {
                            didAttemptSubmit = true
                            Task {
                                if await onSubmit(form) {
                                    dismiss()
                                }
                            }
                        }
                        .disabled(!canSubmit)
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 480, minHeight: showsEndpointFields ? 480 : 300)
        #endif
    }

    private var canSubmit: Bool {
        guard !isSubmitting else { return false }
        return showsEndpointFields ? form.isValid : form.resolvedCredential() != nil
    }

    // MARK: - Sections

    private var kindPicker: some View {
        Picker(String(localized: "Type", bundle: .module), selection: $form.kind) {
            Text(String(localized: "Calendar (CalDAV)", bundle: .module))
                .tag(PIMDAVConnectForm.SourceKind.calendar)
            Text(String(localized: "Contacts (CardDAV)", bundle: .module))
                .tag(PIMDAVConnectForm.SourceKind.contacts)
            Text(String(localized: "Tasks (CalDAV)", bundle: .module))
                .tag(PIMDAVConnectForm.SourceKind.tasks)
        }
        #if os(macOS)
        .pickerStyle(.segmented)
        #endif
    }

    private var endpointFooter: String {
        form.endpointMode == .discover
            ? String(localized: "Brev discovers the DAV server from the address domain.", bundle: .module)
            : String(localized: "HTTPS is required. HTTP is allowed only for local development servers.", bundle: .module)
    }

    @ViewBuilder
    private var endpointFields: some View {
        Group {
            Picker(
                String(localized: "Find the server", bundle: .module),
                selection: $form.endpointMode
            ) {
                Text(String(localized: "Discover by email", bundle: .module))
                    .tag(PIMDAVConnectForm.EndpointMode.discover)
                Text(String(localized: "Manual server URL", bundle: .module))
                    .tag(PIMDAVConnectForm.EndpointMode.manual)
            }

            TextField(
                form.endpointMode == .discover
                    ? String(localized: "Email address", bundle: .module)
                    : String(localized: "Server URL", bundle: .module),
                text: $form.address
            )
            #if os(iOS)
            .keyboardType(form.endpointMode == .discover ? .emailAddress : .URL)
            .textInputAutocapitalization(.never)
            #endif
            .autocorrectionDisabled()
        }
    }

    @ViewBuilder
    private var credentialFields: some View {
        Group {
            Picker(
                String(localized: "Sign in with", bundle: .module),
                selection: $form.credentialMode
            ) {
                Text(String(localized: "App password", bundle: .module))
                    .tag(PIMDAVConnectForm.CredentialMode.appPassword)
                Text(String(localized: "Access token", bundle: .module))
                    .tag(PIMDAVConnectForm.CredentialMode.bearerToken)
            }

            switch form.credentialMode {
            case .appPassword:
                TextField(
                    String(localized: "Username", bundle: .module),
                    text: $form.username
                )
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()

                SecureField(
                    String(localized: "App-specific password", bundle: .module),
                    text: $form.password
                )
            case .bearerToken:
                SecureField(
                    String(localized: "Access token", bundle: .module),
                    text: $form.bearerToken
                )
            }
        }
    }

    private var displayNameField: some View {
        TextField(
            String(localized: "Shown in the source list", bundle: .module),
            text: $form.displayName
        )
    }

    @ViewBuilder
    private var issueCallouts: some View {
        let issues = visibleIssues
        if !issues.isEmpty {
            Section {
                ForEach(issues, id: \.self) { issue in
                    SettingsInfoCallout(
                        symbolName: "exclamationmark.triangle",
                        message: issue.message,
                        tone: .warning
                    )
                }
            }
        }
    }

    private var visibleIssues: [PIMDAVConnectForm.Issue] {
        guard didAttemptSubmit || hasAnyInput else { return [] }
        return showsEndpointFields
            ? form.issues
            : form.issues.filter {
                $0 == .usernameRequired || $0 == .passwordRequired || $0 == .tokenRequired
            }
    }

    private var hasAnyInput: Bool {
        [
            form.address,
            form.username,
            form.password,
            form.bearerToken,
            form.displayName
        ]
        .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
