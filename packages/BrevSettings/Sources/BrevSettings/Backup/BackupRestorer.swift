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

/// Outcome of a restore: which categories applied, which failed and were
/// rolled back, and how many accounts need sign-in (ADR-0076 decisions 4–5).
struct BackupRestoreReport {
    /// Category names that applied cleanly, e.g. `"appearanceTheme"`.
    var succeededCategories: [String] = []
    /// Category names that failed after rollback, with the failure reason.
    var failedCategories: [(category: String, error: String)] = []
    /// Restored accounts parked for sign-in.
    var pendingRestoredAccounts = 0
    /// Backup accounts dropped because the email is already signed in.
    var alreadySignedInAccounts = 0
}

/// Applies a validated `BackupPreview` (ADR-0076 decision 4). Each category
/// — one settings family, accounts, related-mail consent — is applied
/// transactionally: the local value is snapshotted first and restored if
/// the write throws, then the next category continues.
enum BackupRestorer {
    /// Error used by tests to fail a named category after its write.
    struct InjectedCategoryFailure: Error, Equatable {
        let category: String
    }

    /// - Parameters:
    ///   - preview: A `BackupReader.validate` result — already verified.
    ///   - mode: Merge or replace semantics for settings families.
    ///   - store: Settings store to write into.
    ///   - signedInEmails: Lowercased-or-not emails of signed-in accounts;
    ///     matching backup accounts are dropped and counted.
    ///   - consentStore: Related-mail consent store.
    ///   - pendingStore: Where unsigned-in restored accounts are parked.
    ///   - injectedFailures: Test hook — category names that should throw
    ///     after their write, exercising rollback.
    /// - Returns: A report of applied and rolled-back categories.
    @discardableResult
    static func apply(
        preview: BackupPreview,
        mode: BackupRestoreMode,
        store: SettingsPersistenceStore,
        signedInEmails: Set<String>,
        consentStore: RelatedConversationConsentStore = .shared,
        pendingStore: PendingRestoredAccountsStore = .init(),
        injectedFailures: Set<String> = []
    ) -> BackupRestoreReport {
        var report = BackupRestoreReport()

        if let settings = preview.settings {
            for category in SettingsBackupCodec.categoryApplications(
                payload: settings,
                store: store,
                mode: mode,
                consentStore: consentStore
            ) {
                category.snapshotBeforeApply()
                do {
                    try category.run()
                    if injectedFailures.contains(category.name) {
                        throw InjectedCategoryFailure(category: category.name)
                    }
                    report.succeededCategories.append(category.name)
                } catch {
                    category.rollback()
                    report.failedCategories.append((category.name, error.localizedDescription))
                }
            }
        }

        // Accounts never go straight into AccountStore: signed-in matches
        // are dropped, the rest are parked for "sign in to finish".
        if let accounts = preview.accounts {
            let before = pendingStore.entries()
            do {
                let normalized = Set(signedInEmails.map { $0.lowercased() })
                var dropped = 0
                var pending = before
                let pendingEmails = Set(pending.map { $0.account.emailAddress.lowercased() })
                for entry in accounts {
                    let email = entry.account.emailAddress.lowercased()
                    if normalized.contains(email) {
                        dropped += 1
                    } else if !pendingEmails.contains(email) {
                        pending.append(entry)
                    }
                }
                pendingStore.setEntries(pending)
                if injectedFailures.contains("accounts") {
                    throw InjectedCategoryFailure(category: "accounts")
                }
                report.succeededCategories.append("accounts")
                report.alreadySignedInAccounts = dropped
                report.pendingRestoredAccounts = pending.count
            } catch {
                pendingStore.setEntries(before)
                report.failedCategories.append(("accounts", error.localizedDescription))
            }
        }

        return report
    }
}
