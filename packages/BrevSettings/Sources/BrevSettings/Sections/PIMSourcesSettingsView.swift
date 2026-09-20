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
                if !isPresented { removalCandidate = nil }
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
            sourceMenu(row)
        }
        .padding(.vertical, BrevSpacing.xxs)
    }

    private func sourceMenu(_ row: PIMSourceRowPresentation) -> some View {
        Menu {
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BrevSpacing.lg) {
                    if showsEndpointFields {
                        kindPicker
                        endpointFields
                    }
                    credentialFields
                    if showsEndpointFields {
                        displayNameField
                    }
                    issueCallouts
                }
                .padding(BrevSpacing.lg)
            }
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
        .frame(minWidth: 420, idealWidth: 460, minHeight: showsEndpointFields ? 520 : 320)
    }

    private var canSubmit: Bool {
        guard !isSubmitting else { return false }
        return showsEndpointFields ? form.isValid : form.resolvedCredential() != nil
    }

    // MARK: - Sections

    private var kindPicker: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
            Text(String(localized: "Source type", bundle: .module))
                .brevFont(.subheadline)
                .foregroundStyle(theme.textPrimary.color)
            Picker(String(localized: "Source type", bundle: .module), selection: $form.kind) {
                Text(String(localized: "Calendar (CalDAV)", bundle: .module))
                    .tag(PIMDAVConnectForm.SourceKind.calendar)
                Text(String(localized: "Contacts (CardDAV)", bundle: .module))
                    .tag(PIMDAVConnectForm.SourceKind.contacts)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var endpointFields: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            Picker(
                String(localized: "Find the server", bundle: .module),
                selection: $form.endpointMode
            ) {
                Text(String(localized: "Discover by email", bundle: .module))
                    .tag(PIMDAVConnectForm.EndpointMode.discover)
                Text(String(localized: "Manual server URL", bundle: .module))
                    .tag(PIMDAVConnectForm.EndpointMode.manual)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            TextField(
                form.endpointMode == .discover
                    ? String(localized: "Email address", bundle: .module)
                    : String(localized: "Server URL", bundle: .module),
                text: $form.address
            )
            .textFieldStyle(.roundedBorder)
            #if os(iOS)
                .keyboardType(form.endpointMode == .discover ? .emailAddress : .URL)
                .textInputAutocapitalization(.never)
            #endif
                .autocorrectionDisabled()

            Text(
                form.endpointMode == .discover
                    ? String(localized: "Brev discovers the DAV server from the address domain.", bundle: .module)
                    : String(localized: "HTTPS is required. HTTP is allowed only for local development servers.", bundle: .module)
            )
            .brevFont(.caption)
            .foregroundStyle(theme.textSecondary.color)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var credentialFields: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            Picker(
                String(localized: "Sign in with", bundle: .module),
                selection: $form.credentialMode
            ) {
                Text(String(localized: "App password", bundle: .module))
                    .tag(PIMDAVConnectForm.CredentialMode.appPassword)
                Text(String(localized: "Access token", bundle: .module))
                    .tag(PIMDAVConnectForm.CredentialMode.bearerToken)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch form.credentialMode {
            case .appPassword:
                TextField(
                    String(localized: "Username", bundle: .module),
                    text: $form.username
                )
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
                    .autocorrectionDisabled()

                SecureField(
                    String(localized: "App-specific password", bundle: .module),
                    text: $form.password
                )
                .textFieldStyle(.roundedBorder)
            case .bearerToken:
                SecureField(
                    String(localized: "Access token", bundle: .module),
                    text: $form.bearerToken
                )
                .textFieldStyle(.roundedBorder)
            }

            Text(String(
                localized: "Credentials are stored in Keychain and used only for this source.",
                bundle: .module
            ))
            .brevFont(.caption)
            .foregroundStyle(theme.textSecondary.color)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var displayNameField: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
            Text(String(localized: "Display name (optional)", bundle: .module))
                .brevFont(.subheadline)
                .foregroundStyle(theme.textPrimary.color)
            TextField(
                String(localized: "Shown in the source list", bundle: .module),
                text: $form.displayName
            )
            .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private var issueCallouts: some View {
        let issues = showsEndpointFields
            ? form.issues
            : form.issues.filter {
                $0 == .usernameRequired || $0 == .passwordRequired || $0 == .tokenRequired
            }
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: BrevSpacing.xs) {
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
}
