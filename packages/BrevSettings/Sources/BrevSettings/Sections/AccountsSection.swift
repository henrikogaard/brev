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
import BrevDesign
import BrevThemes
import SwiftUI

// MARK: - Fetch schedule presentation helpers

enum FetchSchedulePresentation {
    /// Summary shown beneath the interval picker in the fetch group.
    static func intervalSubtitle(_ interval: FetchInterval) -> String {
        switch interval {
        case .manual:
            return String(localized: "Only check when you pull to refresh or press Get Mail.", bundle: .module)
        default:
            return interval.subtitle
        }
    }
}

struct AccountsSectionActionPresentation: Equatable {
    let title: String
    let isDisabled: Bool
}

struct AccountMailboxRowPresentation: Equatable {
    let isEnabled: Bool
    let canToggle: Bool
    let isDefault: Bool
    let defaultActionTitle: String
    let isDefaultActionDisabled: Bool
}

enum AccountRowLayoutKind: Equatable, Sendable {
    case horizontal
    case compact
}

enum AccountRowLayoutPlatform: Equatable, Sendable {
    case iOS
    case macOS
}

enum AccountRowLayoutPolicy {
    static func layout(
        for horizontalSizeClass: SettingsHorizontalSizeClass?,
        platform: AccountRowLayoutPlatform
    ) -> AccountRowLayoutKind {
        switch platform {
        case .iOS:
            .compact
        case .macOS:
            horizontalSizeClass == .compact ? .compact : .horizontal
        }
    }
}

enum AccountsSectionPresentation {
    static func showsAddAccountAction(isAddAccountAvailable: Bool) -> Bool {
        isAddAccountAvailable
    }

    static func addAccountAction(
        isAddingAccount: Bool,
        signingOutAccountIDs: Set<BrevAccount.ID>
    ) -> AccountsSectionActionPresentation {
        AccountsSectionActionPresentation(
            title: isAddingAccount ? String(localized: "Adding…", bundle: .module) : String(
                localized: "Add account",
                bundle: .module
            ),
            isDisabled: isAddingAccount || !signingOutAccountIDs.isEmpty
        )
    }

    static func signOutAction(
        accountID: BrevAccount.ID,
        isAddingAccount: Bool,
        signingOutAccountIDs: Set<BrevAccount.ID>
    ) -> AccountsSectionActionPresentation {
        AccountsSectionActionPresentation(
            title: signingOutAccountIDs.contains(accountID) ? String(localized: "Signing out…", bundle: .module) : String(
                localized: "Sign out",
                bundle: .module
            ),
            isDisabled: isAddingAccount || !signingOutAccountIDs.isEmpty
        )
    }

    static func setDefaultAction(
        accountID: BrevAccount.ID,
        currentAccountID: BrevAccount.ID?,
        isAddingAccount: Bool,
        signingOutAccountIDs: Set<BrevAccount.ID>
    ) -> AccountsSectionActionPresentation {
        let isCurrent = accountID == currentAccountID
        return AccountsSectionActionPresentation(
            title: isCurrent ? String(localized: "Default", bundle: .module) : String(localized: "Set default", bundle: .module),
            isDisabled: isCurrent || isAddingAccount || !signingOutAccountIDs.isEmpty
        )
    }

    static func removeAction(
        isAddingAccount: Bool,
        signingOutAccountIDs: Set<BrevAccount.ID>
    ) -> AccountsSectionActionPresentation {
        AccountsSectionActionPresentation(
            title: String(localized: "Remove", bundle: .module),
            isDisabled: isAddingAccount || !signingOutAccountIDs.isEmpty
        )
    }
}

enum AccountMailboxSelectionPresentation {
    static func row(
        sourceID: MailSourceID,
        availableSourceIDs: [MailSourceID],
        preferences: MailboxSourcePreferences
    ) -> AccountMailboxRowPresentation {
        let enabledSourceIDs = MailboxSourcePreferencesPolicy.enabledSourceIDs(
            availableSourceIDs: availableSourceIDs,
            preferences: preferences
        )
        let isEnabled = enabledSourceIDs.contains(sourceID)
        let defaultSourceID = MailboxSourcePreferencesPolicy.defaultSourceID(
            availableSourceIDs: availableSourceIDs,
            preferences: preferences
        )
        let isDefault = defaultSourceID == sourceID

        return AccountMailboxRowPresentation(
            isEnabled: isEnabled,
            canToggle: !isEnabled || enabledSourceIDs.count > 1,
            isDefault: isDefault,
            defaultActionTitle: isDefault ? String(localized: "Default", bundle: .module) : String(
                localized: "Make default",
                bundle: .module
            ),
            isDefaultActionDisabled: !isEnabled || isDefault
        )
    }
}

struct AccountsSection: View {
    @Environment(\.brevTheme) private var theme
    let accounts: [BrevAccount]
    let currentAccountID: BrevAccount.ID?
    let backendProvider: @MainActor (BrevAccount.ID) -> (any MailBackend)?
    let isAddAccountAvailable: Bool
    let onAddAccount: () async -> Void
    let onSetDefault: (BrevAccount) async -> Void
    let onSignOut: (BrevAccount) async -> Void
    let onRemoveAccount: (BrevAccount) async -> Void

    private let settingsStore: SettingsPersistenceStore
    @State private var fetchSettings: FetchScheduleSettings
    @State private var mailboxPreferences: MailboxSourcePreferences
    @State private var mailboxesByAccountID: [BrevAccount.ID: [Mailbox]] = [:]
    @State private var mailboxLoadErrorsByAccountID: [BrevAccount.ID: String] = [:]
    @State private var loadingMailboxAccountIDs: Set<BrevAccount.ID> = []
    @State private var isAddingAccount = false
    @State private var signingOutAccountIDs: Set<BrevAccount.ID> = []
    @State private var accountPendingRemoval: BrevAccount?
    /// Per-account undismissed replay conflicts. Keyed by `BrevAccount.ID`.
    @State private var conflictsByAccountID: [BrevAccount.ID: [ReplayConflict]] = [:]
    /// The account whose conflict review sheet is currently open.
    @State private var conflictReviewAccountID: BrevAccount.ID?

    init(
        accounts: [BrevAccount],
        currentAccountID: BrevAccount.ID?,
        backendProvider: @MainActor @escaping (BrevAccount.ID) -> (any MailBackend)? = { _ in nil },
        isAddAccountAvailable: Bool = true,
        settingsStore: SettingsPersistenceStore = .standard,
        onAddAccount: @escaping () async -> Void,
        onSetDefault: @escaping (BrevAccount) async -> Void,
        onSignOut: @escaping (BrevAccount) async -> Void,
        onRemoveAccount: @escaping (BrevAccount) async -> Void
    ) {
        self.accounts = accounts
        self.currentAccountID = currentAccountID
        self.backendProvider = backendProvider
        self.isAddAccountAvailable = isAddAccountAvailable
        self.settingsStore = settingsStore
        self.onAddAccount = onAddAccount
        self.onSetDefault = onSetDefault
        self.onSignOut = onSignOut
        self.onRemoveAccount = onRemoveAccount
        _fetchSettings = State(initialValue: settingsStore.fetchScheduleSettings())
        _mailboxPreferences = State(initialValue: settingsStore.mailboxSourcePreferences())
    }

    var body: some View {
        SectionScaffold(title: String(localized: "Accounts", bundle: .module)) {
            VStack(alignment: .leading, spacing: BrevSpacing.xl) {
                accountListGroup
                fetchScheduleGroup
            }
        }
        .confirmationDialog(
            String(localized: "Remove account?", bundle: .module),
            isPresented: removeConfirmationBinding,
            presenting: accountPendingRemoval
        ) { account in
            Button(String(localized: "Remove \(account.emailAddress)", bundle: .module), role: .destructive) {
                startRemove(account)
            }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) {}
        } message: { account in
            Text("Brev removes this account from the local app. Server mail is not deleted.", bundle: .module)
                .accessibilityLabel(String(localized: "Remove account \(account.emailAddress) from Brev", bundle: .module))
        }
        .sheet(item: conflictReviewBinding) { account in
            ConflictReviewSheet(
                conflicts: conflictListBinding(for: account.id),
                onDismissConflict: { conflict in
                    await dismissConflict(conflict, account: account)
                },
                onDismissAll: {
                    await dismissAllConflicts(account: account)
                },
                onRetryConflict: { conflict in
                    await retryConflict(conflict, account: account)
                },
                onRetryAll: {
                    await retrySync(account: account)
                }
            )
        }
        .task(id: mailboxLoadTaskID) {
            await loadMailboxesForAccounts()
        }
    }

    // MARK: - Sub-views

    private var accountListGroup: some View {
        SettingsGroup(
            title: String(localized: "Signed-in accounts", bundle: .module),
            subtitle: String(localized: "Manage the mail accounts connected to Brev.", bundle: .module),
            symbolName: "person.crop.circle"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                if accounts.isEmpty {
                    Text("No accounts signed in.", bundle: .module)
                        .brevFont(.body)
                        .foregroundStyle(theme.textSecondary.color)
                } else {
                    VStack(spacing: BrevSpacing.xs) {
                        ForEach(accounts) { account in
                            AccountRow(
                                account: account,
                                isCurrent: account.id == currentAccountID,
                                mailboxes: mailboxesByAccountID[account.id] ?? [],
                                availableSourceIDs: availableSourceIDs,
                                mailboxPreferences: mailboxPreferences,
                                isLoadingMailboxes: loadingMailboxAccountIDs.contains(account.id),
                                mailboxLoadError: mailboxLoadErrorsByAccountID[account.id],
                                replayConflictCount: conflictsByAccountID[account.id]?.count ?? 0,
                                setDefaultPresentation: setDefaultPresentation(for: account),
                                signOutPresentation: signOutPresentation(for: account),
                                removePresentation: removePresentation,
                                onSetDefault: { startSetDefault(account) },
                                onSignOut: { startSignOut(account) },
                                onRemove: { accountPendingRemoval = account },
                                onReviewConflicts: { conflictReviewAccountID = account.id },
                                onToggleMailbox: { mailbox, isEnabled in
                                    setMailbox(mailbox, for: account, isEnabled: isEnabled)
                                },
                                onSetDefaultMailbox: { mailbox in
                                    setDefaultMailbox(mailbox, for: account)
                                }
                            )
                        }
                    }
                }

                if AccountsSectionPresentation.showsAddAccountAction(
                    isAddAccountAvailable: isAddAccountAvailable
                ) {
                    BrevButton(addAccountPresentation.title, style: .secondary) {
                        startAddAccount()
                    }
                    .disabled(addAccountPresentation.isDisabled)
                }
            }
        }
    }

    private var fetchScheduleGroup: some View {
        SettingsGroup(
            title: String(localized: "Fetch schedule", bundle: .module),
            subtitle: String(localized: "Applies to all accounts. Choose how often Brev checks for new mail.", bundle: .module),
            symbolName: "envelope.arrow.triangle.branch"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                SettingsPickerRow(
                    symbolName: "clock",
                    title: String(localized: "Check for mail", bundle: .module),
                    subtitle: FetchSchedulePresentation.intervalSubtitle(fetchSettings.interval),
                    selection: fetchIntervalBinding
                ) {
                    ForEach(FetchInterval.allCases) { interval in
                        Text(interval.title).tag(interval)
                    }
                }

                SettingsInfoCallout(
                    symbolName: "battery.75percent",
                    message: fetchSettings.interval == .manual
                        ? String(
                            localized: "Manual-only mode. Brev will not wake up to check for mail automatically.",
                            bundle: .module
                        )
                        : String(
                            localized: "More frequent checks use more battery. Manual-only mode is available above.",
                            bundle: .module
                        ),
                    tone: fetchSettings.interval == .fiveMinutes ? .warning : .info
                )
            }
        }
    }

    private var fetchIntervalBinding: Binding<FetchInterval> {
        Binding(
            get: { fetchSettings.interval },
            set: { newValue in
                fetchSettings.interval = newValue
                settingsStore.save(fetchSettings)
            }
        )
    }

    // MARK: - Presentation

    private var addAccountPresentation: AccountsSectionActionPresentation {
        AccountsSectionPresentation.addAccountAction(
            isAddingAccount: isAddingAccount,
            signingOutAccountIDs: signingOutAccountIDs
        )
    }

    private func signOutPresentation(for account: BrevAccount) -> AccountsSectionActionPresentation {
        AccountsSectionPresentation.signOutAction(
            accountID: account.id,
            isAddingAccount: isAddingAccount,
            signingOutAccountIDs: signingOutAccountIDs
        )
    }

    private func setDefaultPresentation(for account: BrevAccount) -> AccountsSectionActionPresentation {
        AccountsSectionPresentation.setDefaultAction(
            accountID: account.id,
            currentAccountID: currentAccountID,
            isAddingAccount: isAddingAccount,
            signingOutAccountIDs: signingOutAccountIDs
        )
    }

    private var removePresentation: AccountsSectionActionPresentation {
        AccountsSectionPresentation.removeAction(
            isAddingAccount: isAddingAccount,
            signingOutAccountIDs: signingOutAccountIDs
        )
    }

    private var removeConfirmationBinding: Binding<Bool> {
        Binding(
            get: { accountPendingRemoval != nil },
            set: { isPresented in
                if !isPresented { accountPendingRemoval = nil }
            }
        )
    }

    private var mailboxLoadTaskID: String {
        accounts.map(\.id).sorted().joined(separator: "|")
    }

    private var availableSourceIDs: [MailSourceID] {
        accounts.flatMap { account in
            (mailboxesByAccountID[account.id] ?? []).map { mailbox in
                sourceID(for: mailbox, account: account)
            }
        }
    }

    private func startAddAccount() {
        guard !addAccountPresentation.isDisabled else { return }
        isAddingAccount = true
        Task { @MainActor in
            defer { isAddingAccount = false }
            await onAddAccount()
        }
    }

    private func startSetDefault(_ account: BrevAccount) {
        let presentation = setDefaultPresentation(for: account)
        guard !presentation.isDisabled else { return }
        Task { @MainActor in
            await onSetDefault(account)
        }
    }

    private func startSignOut(_ account: BrevAccount) {
        let presentation = signOutPresentation(for: account)
        guard !presentation.isDisabled else { return }
        signingOutAccountIDs.insert(account.id)
        Task { @MainActor in
            defer { signingOutAccountIDs.remove(account.id) }
            await onSignOut(account)
        }
    }

    private func startRemove(_ account: BrevAccount) {
        let presentation = removePresentation
        guard !presentation.isDisabled else { return }
        signingOutAccountIDs.insert(account.id)
        Task { @MainActor in
            defer { signingOutAccountIDs.remove(account.id) }
            await onRemoveAccount(account)
        }
    }

    private func loadMailboxesForAccounts() async {
        for account in accounts {
            guard let backend = backendProvider(account.id) else { continue }
            loadingMailboxAccountIDs.insert(account.id)
            do {
                let mailboxes = try await backend.mailboxes()
                mailboxesByAccountID[account.id] = mailboxes
                mailboxLoadErrorsByAccountID[account.id] = nil
            } catch {
                mailboxLoadErrorsByAccountID[account.id] = error.localizedDescription
            }
            loadingMailboxAccountIDs.remove(account.id)

            // Load conflicts from SyncConflictManaging if the backend supports it.
            await loadConflicts(for: account)
        }
    }

    private func loadConflicts(for account: BrevAccount) async {
        guard let backend = backendProvider(account.id),
              let manager = backend.extensionService(SyncConflictManaging.self)
        else { return }
        let mailboxes = mailboxesByAccountID[account.id] ?? []
        let primaryMailbox = mailboxes.first(where: \.isPrimary) ?? mailboxes.first
        guard let primaryMailbox else { return }
        let sid = MailSourceID(accountID: account.id, mailboxID: primaryMailbox.id)
        let conflicts = await manager.replayConflicts(for: sid)
        conflictsByAccountID[account.id] = conflicts
    }

    private func dismissConflict(_ conflict: ReplayConflict, account: BrevAccount) async {
        guard let backend = backendProvider(account.id),
              let manager = backend.extensionService(SyncConflictManaging.self)
        else { return }
        let mailboxes = mailboxesByAccountID[account.id] ?? []
        let primaryMailbox = mailboxes.first(where: \.isPrimary) ?? mailboxes.first
        guard let primaryMailbox else { return }
        let sid = MailSourceID(accountID: account.id, mailboxID: primaryMailbox.id)
        await manager.dismissConflict(id: conflict.id, sourceID: sid)
    }

    private func dismissAllConflicts(account: BrevAccount) async {
        guard let backend = backendProvider(account.id),
              let manager = backend.extensionService(SyncConflictManaging.self)
        else { return }
        let mailboxes = mailboxesByAccountID[account.id] ?? []
        let primaryMailbox = mailboxes.first(where: \.isPrimary) ?? mailboxes.first
        guard let primaryMailbox else { return }
        let sid = MailSourceID(accountID: account.id, mailboxID: primaryMailbox.id)
        await manager.dismissAllConflicts(for: sid)
        conflictsByAccountID[account.id] = []
    }

    private func retryConflict(_ conflict: ReplayConflict, account: BrevAccount) async {
        guard let backend = backendProvider(account.id),
              let repairer = backend.extensionService(SyncHealthRepairing.self)
        else { return }
        let mailboxes = mailboxesByAccountID[account.id] ?? []
        let primaryMailbox = mailboxes.first(where: \.isPrimary) ?? mailboxes.first
        guard let primaryMailbox else { return }
        let sid = MailSourceID(accountID: account.id, mailboxID: primaryMailbox.id)
        try? await repairer.retryConflict(id: conflict.id, sourceID: sid)
    }

    private func retrySync(account: BrevAccount) async {
        guard let backend = backendProvider(account.id),
              let repairer = backend.extensionService(SyncHealthRepairing.self)
        else { return }
        let mailboxes = mailboxesByAccountID[account.id] ?? []
        let primaryMailbox = mailboxes.first(where: \.isPrimary) ?? mailboxes.first
        guard let primaryMailbox else { return }
        let sid = MailSourceID(accountID: account.id, mailboxID: primaryMailbox.id)
        try? await repairer.retrySync(for: sid)
    }

    /// Binding used by the `.sheet(item:)` modifier. Maps `conflictReviewAccountID`
    /// to the matching `BrevAccount` so the sheet receives a full account value.
    private var conflictReviewBinding: Binding<BrevAccount?> {
        Binding(
            get: {
                guard let id = conflictReviewAccountID else { return nil }
                return accounts.first { $0.id == id }
            },
            set: { account in
                conflictReviewAccountID = account?.id
            }
        )
    }

    /// Binding for the live conflict list used inside `ConflictReviewSheet`.
    private func conflictListBinding(for accountID: BrevAccount.ID) -> Binding<[ReplayConflict]> {
        Binding(
            get: { conflictsByAccountID[accountID] ?? [] },
            set: { conflictsByAccountID[accountID] = $0 }
        )
    }

    private func setMailbox(_ mailbox: Mailbox, for account: BrevAccount, isEnabled: Bool) {
        let sourceID = sourceID(for: mailbox, account: account)
        let available = availableSourceIDs
        var enabledSourceIDs = MailboxSourcePreferencesPolicy.enabledSourceIDs(
            availableSourceIDs: available,
            preferences: mailboxPreferences
        )

        if isEnabled {
            if !enabledSourceIDs.contains(sourceID) {
                enabledSourceIDs.append(sourceID)
            }
        } else {
            guard enabledSourceIDs.count > 1 else { return }
            enabledSourceIDs.removeAll { $0 == sourceID }
        }

        let proposedDefault = mailboxPreferences.defaultSourceID == sourceID && !isEnabled
            ? nil
            : mailboxPreferences.defaultSourceID
        mailboxPreferences = MailboxSourcePreferencesPolicy.normalized(
            availableSourceIDs: available,
            enabledSourceIDs: enabledSourceIDs,
            defaultSourceID: proposedDefault,
            preferredDefaultSourceID: preferredDefaultSourceID()
        )
        settingsStore.save(mailboxPreferences)
    }

    private func setDefaultMailbox(_ mailbox: Mailbox, for account: BrevAccount) {
        let sourceID = sourceID(for: mailbox, account: account)
        let available = availableSourceIDs
        var enabledSourceIDs = MailboxSourcePreferencesPolicy.enabledSourceIDs(
            availableSourceIDs: available,
            preferences: mailboxPreferences
        )
        if !enabledSourceIDs.contains(sourceID) {
            enabledSourceIDs.append(sourceID)
        }
        mailboxPreferences = MailboxSourcePreferencesPolicy.normalized(
            availableSourceIDs: available,
            enabledSourceIDs: enabledSourceIDs,
            defaultSourceID: sourceID,
            preferredDefaultSourceID: preferredDefaultSourceID()
        )
        settingsStore.save(mailboxPreferences)

        Task {
            try? await backendProvider(account.id)?.switchMailbox(id: mailbox.id)
        }
    }

    private func preferredDefaultSourceID() -> MailSourceID? {
        for account in accounts {
            guard let mailboxes = mailboxesByAccountID[account.id] else { continue }
            if let primary = mailboxes.first(where: \.isPrimary) {
                return sourceID(for: primary, account: account)
            }
        }
        return availableSourceIDs.first
    }

    private func sourceID(for mailbox: Mailbox, account: BrevAccount) -> MailSourceID {
        MailSourceID(accountID: account.id, mailboxID: mailbox.id)
    }
}

private struct AccountRow: View {
    @Environment(\.brevTheme) private var theme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    let account: BrevAccount
    let isCurrent: Bool
    let mailboxes: [Mailbox]
    let availableSourceIDs: [MailSourceID]
    let mailboxPreferences: MailboxSourcePreferences
    let isLoadingMailboxes: Bool
    let mailboxLoadError: String?
    /// Number of undismissed replay conflicts for this account.
    let replayConflictCount: Int
    let setDefaultPresentation: AccountsSectionActionPresentation
    let signOutPresentation: AccountsSectionActionPresentation
    let removePresentation: AccountsSectionActionPresentation
    let onSetDefault: () -> Void
    let onSignOut: () -> Void
    let onRemove: () -> Void
    /// Called when the user taps "Review N conflicts".
    let onReviewConflicts: () -> Void
    let onToggleMailbox: (Mailbox, Bool) -> Void
    let onSetDefaultMailbox: (Mailbox) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            Group {
                switch layoutKind {
                case .horizontal:
                    horizontalLayout
                case .compact:
                    compactLayout
                }
            }

            if let conflictButtonTitle = ConflictReviewPresentation.reviewButtonTitle(
                conflictCount: replayConflictCount
            ) {
                Rectangle()
                    .fill(BrevSeparator.color(for: theme))
                    .frame(height: 1)

                conflictBanner(title: conflictButtonTitle)
            }

            if shouldShowMailboxControls {
                Rectangle()
                    .fill(BrevSeparator.color(for: theme))
                    .frame(height: 1)

                mailboxControls
            }
        }
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.sm)
        .background(theme.bgSecondary.color.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: BrevRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: BrevRadius.md)
                .stroke(theme.border.color.opacity(0.45), lineWidth: 1)
        }
    }

    private func conflictBanner(title: String) -> some View {
        HStack(spacing: BrevSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.warning.color)
                .frame(width: 18)
            Text(title)
                .brevFont(.caption)
                .foregroundStyle(theme.warning.color)
            Spacer(minLength: BrevSpacing.sm)
            BrevButton(title, style: .tertiary) {
                onReviewConflicts()
            }
            .controlSize(.small)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "\(title). Tap to review.", bundle: .module))
    }

    private var layoutKind: AccountRowLayoutKind {
        #if os(iOS)
        AccountRowLayoutPolicy.layout(
            for: horizontalSizeClass,
            platform: .iOS
        )
        #else
        AccountRowLayoutPolicy.layout(
            for: nil,
            platform: .macOS
        )
        #endif
    }

    private var horizontalLayout: some View {
        HStack(spacing: BrevSpacing.md) {
            avatar
            accountIdentity(emailLineLimit: 1)
                .layoutPriority(1)

            Spacer()

            backendBadge

            compactActionsMenu
        }
    }

    private var compactLayout: some View {
        HStack(alignment: .top, spacing: BrevSpacing.md) {
            avatar
            VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                accountIdentity(emailLineLimit: 2)
                HStack(spacing: BrevSpacing.xs) {
                    backendBadge
                    if isCurrent {
                        defaultBadge
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            compactActionsMenu
        }
    }

    private var avatar: some View {
        Circle()
            .fill(theme.accent.color.opacity(0.15))
            .frame(width: 36, height: 36)
            .overlay {
                Text(String(account.displayName.prefix(1)))
                    .brevFont(.callout)
                    .foregroundStyle(theme.accent.color)
            }
    }

    private func accountIdentity(emailLineLimit: Int) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
            HStack(spacing: BrevSpacing.xs) {
                Text(account.displayName)
                    .brevFont(.subheadline)
                    .foregroundStyle(theme.textPrimary.color)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if isCurrent, layoutKind == .horizontal {
                    defaultBadge
                }
            }
            Text(account.emailAddress)
                .brevFont(.footnote)
                .foregroundStyle(theme.textSecondary.color)
                .lineLimit(emailLineLimit)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var backendBadge: some View {
        Text(account.backendDisplayName)
            .brevFont(.caption)
            .foregroundStyle(theme.textSecondary.color)
            .lineLimit(1)
            .padding(.horizontal, BrevSpacing.sm)
            .padding(.vertical, BrevSpacing.xs)
            .background(theme.bgSecondary.color.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: BrevRadius.sm))
            .accessibilityLabel(String(localized: "Backend: \(account.backendDisplayName)", bundle: .module))
    }

    private var defaultBadge: some View {
        Text("Default account", bundle: .module)
            .brevFont(.footnote)
            .foregroundStyle(theme.accent.color)
            .lineLimit(1)
            .padding(.horizontal, BrevSpacing.sm)
            .padding(.vertical, BrevSpacing.xs)
            .background(theme.accentMuted.color.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: BrevRadius.sm))
    }

    private var compactActionsMenu: some View {
        Menu {
            if !isCurrent {
                Button(setDefaultPresentation.title) { onSetDefault() }
                    .disabled(setDefaultPresentation.isDisabled)
            }

            Button(signOutPresentation.title) {
                onSignOut()
            }
            .disabled(signOutPresentation.isDisabled)

            Button(removePresentation.title, role: .destructive) {
                onRemove()
            }
            .disabled(removePresentation.isDisabled)
        } label: {
            Image(systemName: "ellipsis.circle")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.accent.color)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(String(localized: "Account actions for \(account.emailAddress)", bundle: .module))
    }

    private var shouldShowMailboxControls: Bool {
        isLoadingMailboxes || mailboxLoadError != nil || mailboxes.count > 1
    }

    @ViewBuilder
    private var mailboxControls: some View {
        if isLoadingMailboxes {
            HStack(spacing: BrevSpacing.sm) {
                ProgressView()
                    .controlSize(.small)
                    .tint(theme.accent.color)
                Text("Loading mailboxes…", bundle: .module)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
            }
        } else if let mailboxLoadError {
            HStack(alignment: .top, spacing: BrevSpacing.sm) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(theme.warning.color)
                Text(mailboxLoadError)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                Text("Mailboxes", bundle: .module)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)

                ForEach(mailboxes) { mailbox in
                    mailboxRow(mailbox)
                }
            }
        }
    }

    private func mailboxRow(_ mailbox: Mailbox) -> some View {
        let sourceID = MailSourceID(accountID: account.id, mailboxID: mailbox.id)
        let presentation = AccountMailboxSelectionPresentation.row(
            sourceID: sourceID,
            availableSourceIDs: availableSourceIDs,
            preferences: mailboxPreferences
        )

        // The switch is a separate trailing control rather than the toggle's
        // own label. A macOS switch hugs its label, so with the name inside
        // the `Toggle` it landed mid-row against the text instead of lining
        // up with the other trailing controls.
        return HStack(alignment: .center, spacing: BrevSpacing.sm) {
            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                Text(mailbox.displayName)
                    .brevFont(.body)
                    .foregroundStyle(theme.textPrimary.color)
                    .lineLimit(1)
                Text(mailbox.email)
                    .brevFont(.footnote)
                    .foregroundStyle(theme.textSecondary.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: BrevSpacing.sm)

            Toggle(isOn: Binding(
                get: { presentation.isEnabled },
                set: { onToggleMailbox(mailbox, $0) }
            )) {
                EmptyView()
            }
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(theme.accent.color)
            .disabled(!presentation.canToggle)
            .opacity(presentation.canToggle ? 1 : 0.65)
            .accessibilityLabel(String(localized: "Enable mailbox \(mailbox.email)", bundle: .module))

            Group {
                if presentation.isDefault {
                    Label(String(localized: "Default mailbox", bundle: .module), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(theme.textSecondary.color)
                } else {
                    Button(String(localized: "Make default", bundle: .module)) { onSetDefaultMailbox(mailbox) }
                        .buttonStyle(.borderless)
                        .disabled(presentation.isDefaultActionDisabled)
                        .accessibilityLabel(String(localized: "Make default mailbox \(mailbox.email)", bundle: .module))
                }
            }
            .brevFont(.footnote)
            .frame(width: 122, height: 28, alignment: .leading)
        }
    }
}
