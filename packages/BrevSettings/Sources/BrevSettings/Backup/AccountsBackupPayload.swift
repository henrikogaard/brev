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
import Foundation

/// One account entry in `accounts.json` (ADR-0076 decision 3).
///
/// Carries the account identity plus enough server configuration to offer
/// a prefilled sign-in. `IMAPAccountConfiguration` and `MailServerSettings`
/// hold only host/port/TLS/auth-kind metadata; the only secret-bearing
/// field is `credentialID` — a Keychain pointer — which export replaces
/// with an empty string.
public struct AccountBackupEntry: Codable, Equatable, Sendable, Identifiable {
    public var account: BrevAccount
    public var imapConfiguration: IMAPAccountConfiguration?

    public var id: String { account.id }

    public init(account: BrevAccount, imapConfiguration: IMAPAccountConfiguration?) {
        self.account = account
        self.imapConfiguration = imapConfiguration
    }

    /// Export-safe copy: the Keychain `credentialID` is blanked so no
    /// credential reference ever reaches the backup file.
    public static func sanitized(
        account: BrevAccount,
        configuration: IMAPAccountConfiguration?
    ) -> AccountBackupEntry {
        guard let configuration else {
            return AccountBackupEntry(account: account, imapConfiguration: nil)
        }
        let stripped = IMAPAccountConfiguration(
            accountID: configuration.accountID,
            emailAddress: configuration.emailAddress,
            displayName: configuration.displayName,
            incoming: configuration.incoming,
            outgoing: configuration.outgoing,
            manageSieve: configuration.manageSieve,
            credentialID: ""
        )
        return AccountBackupEntry(account: account, imapConfiguration: stripped)
    }
}

/// `accounts.json` payload: the list of backed-up accounts, encoded as a
/// top-level JSON array.
public typealias AccountsBackupPayload = [AccountBackupEntry]

/// Builds the accounts payload from signed-in accounts and their stored
/// IMAP configurations, stripping credential pointers.
public enum AccountsBackupCodec {
    /// - Parameters:
    ///   - accounts: Signed-in accounts, typically `AccountStore.accounts`.
    ///   - configurationProvider: Per-account IMAP configuration lookup,
    ///     typically `UserDefaultsIMAPAccountConfigurationStore.configuration(for:)`.
    public static func export(
        accounts: [BrevAccount],
        configurationProvider: (String) async -> IMAPAccountConfiguration?
    ) async -> AccountsBackupPayload {
        var entries: [AccountBackupEntry] = []
        for account in accounts {
            let configuration = await configurationProvider(account.id)
            entries.append(.sanitized(account: account, configuration: configuration))
        }
        return entries
    }
}

/// Restored-but-unsigned-in accounts waiting for the user to finish
/// sign-in (ADR-0076 decision 5). Stored as a Codable list under
/// `backup.pendingRestoredAccounts`; surfaced in Settings › Accounts as
/// "Restored accounts — sign in to finish".
public final class PendingRestoredAccountsStore: @unchecked Sendable {
    public static let key = "backup.pendingRestoredAccounts"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// All entries still waiting for sign-in.
    public func entries() -> [AccountBackupEntry] {
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([AccountBackupEntry].self, from: data)
        else { return [] }
        return decoded
    }

    /// Replaces the pending list.
    public func setEntries(_ entries: [AccountBackupEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.key)
    }

    /// Removes one entry — after sign-in or an explicit Remove.
    public func remove(accountID: String) {
        setEntries(entries().filter { $0.account.id != accountID })
    }
}
