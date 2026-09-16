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
import Foundation

/// Codable payload for `settings.json` inside a `.brevbackup` package
/// (ADR-0076). One optional field per included settings family; a `nil`
/// field means the backup does not carry that family and restore leaves
/// the local value untouched in every mode.
///
/// Excluded on purpose (never serialized here):
/// - `DeveloperSettings` — developer tooling, not user data worth moving.
/// - `AIWriterSettings` / AI provider configurations — may reference API keys.
/// - `SecurityKeyMaterialSettings` — key material must never leave the device.
/// - `NotificationSettings.backgroundMailEnabled` / `launchAtLoginRequested` —
///   device-bound per ADR-0075, stripped via `NotificationBackupSettings`.
/// - `CalDAVSettings.credentialAccount` — Keychain credential pointer,
///   stripped via `CalDAVBackupSettings`.
struct SettingsBackupPayload: Codable, Equatable {
    var appearanceTheme: AppearanceThemeSettings?
    var windowAppearance: WindowAppearancePreferences?
    var appIcon: AppIconVariant?
    var mailboxView: MailboxViewSettings?
    var inboxClassification: InboxClassificationSettings?
    var avatarPrivacy: AvatarPrivacySettings?
    var browser: BrowserSettings?
    var compose: ComposeSettings?
    var signature: SignatureSettings?
    var remoteContentPolicy: RemoteContentPolicy?
    var notification: NotificationBackupSettings?
    var update: UpdateSettings?
    var smartMailbox: SmartMailboxSettings?
    var localRules: LocalRulesSettings?
    var folderPreferences: FolderPreferences?
    var vipSender: VIPSenderSettings?
    var followUp: FollowUpSettings?
    var messageTemplate: MessageTemplateSettings?
    var fetchSchedule: FetchScheduleSettings?
    var calDAV: CalDAVBackupSettings?
    var encryption: EncryptionSettings?
    var accountMailboxSync: AccountMailboxSyncSettings?
    var mailboxSource: MailboxSourcePreferences?
    var folderVisibility: FolderVisibilityPreferences?
    var preferenceSync: PreferenceSyncSettings?
    /// Account IDs with persistent related-mail auto-load consent enabled.
    var relatedMailAutoLoadAccountIDs: [String]?

    /// Top-level keys the codec understands. Keys found in `settings.json`
    /// outside this set are counted as skipped during validation; "preserved"
    /// in merge mode means the local value is not destroyed — the unknown
    /// payload content itself is not retained anywhere.
    static let knownKeys: Set<String> = [
        "appearanceTheme", "windowAppearance", "appIcon", "mailboxView",
        "inboxClassification", "avatarPrivacy", "browser", "compose",
        "signature", "remoteContentPolicy", "notification", "update",
        "smartMailbox", "localRules", "folderPreferences", "vipSender",
        "followUp", "messageTemplate", "fetchSchedule", "calDAV",
        "encryption", "accountMailboxSync", "mailboxSource",
        "folderVisibility", "preferenceSync", "relatedMailAutoLoadAccountIDs"
    ]
}

/// `NotificationSettings` minus the device-bound ADR-0075 fields
/// (`backgroundMailEnabled`, `launchAtLoginRequested`), which must never
/// travel between devices in a backup.
struct NotificationBackupSettings: Codable, Equatable {
    var notificationsEnabled: Bool
    var badgeEnabled: Bool
    var badgePolicy: NotificationBadgePolicy
    var soundEnabled: Bool
    var showPreviews: Bool
    var accountOverrides: [String: NotificationSettings.AccountOverride]
    var quietHoursEnabled: Bool
    var quietHoursStart: Int
    var quietHoursEnd: Int

    init(_ settings: NotificationSettings) {
        notificationsEnabled = settings.notificationsEnabled
        badgeEnabled = settings.badgeEnabled
        badgePolicy = settings.badgePolicy
        soundEnabled = settings.soundEnabled
        showPreviews = settings.showPreviews
        accountOverrides = settings.accountOverrides
        quietHoursEnabled = settings.quietHoursEnabled
        quietHoursStart = settings.quietHoursStart
        quietHoursEnd = settings.quietHoursEnd
    }
}

/// `CalDAVSettings` minus `credentialAccount` — a Keychain credential
/// pointer that is meaningless and unsafe to carry into a backup. Server
/// URL, calendar, and collection path are exported; on restore the local
/// credential pointer is preserved.
struct CalDAVBackupSettings: Codable, Equatable {
    var featureFlagEnabled: Bool
    var isEnabled: Bool
    var serverURL: String
    var calendarName: String
    var collectionPath: String
    var useLocalBasicAuth: Bool

    init(_ settings: CalDAVSettings) {
        featureFlagEnabled = settings.featureFlagEnabled
        isEnabled = settings.isEnabled
        serverURL = settings.serverURL
        calendarName = settings.calendarName
        collectionPath = settings.collectionPath
        useLocalBasicAuth = settings.useLocalBasicAuth
    }
}

/// One restorable unit — a single settings family (or another restore
/// category such as accounts). Snapshots the local value before applying
/// so `rollback()` can restore it when the write fails partway.
final class BackupCategoryApplication {
    let name: String
    private var snapshot: Any?
    private let snapshotBox: () -> Any
    private let restoreBox: (Any) -> Void
    private let applyBox: () throws -> Void

    init<T>(
        name: String,
        read: @escaping () -> T,
        write: @escaping (T) -> Void,
        apply: @escaping () throws -> Void
    ) {
        self.name = name
        snapshotBox = { read() }
        restoreBox = { if let value = $0 as? T { write(value) } }
        applyBox = apply
    }

    /// Captures the local value for a later `rollback()`.
    func snapshotBeforeApply() { snapshot = snapshotBox() }
    /// Performs the category's write.
    func run() throws { try applyBox() }
    /// Restores the captured snapshot, if any.
    func rollback() {
        if let snapshot { restoreBox(snapshot) }
    }
}

/// Reads settings families out of a `SettingsPersistenceStore` into a
/// backup payload and applies a payload back, per ADR-0076 decisions 2–4.
enum SettingsBackupCodec {
    /// Exports every included family. `accountIDs` scopes the related-mail
    /// consent export to accounts actually present in the backup.
    static func export(
        from store: SettingsPersistenceStore,
        consentStore: RelatedConversationConsentStore = .shared,
        accountIDs: [BrevAccount.ID] = []
    ) -> SettingsBackupPayload {
        SettingsBackupPayload(
            appearanceTheme: store.appearanceThemeSettings(),
            windowAppearance: store.windowAppearancePreferences(),
            appIcon: store.appIconVariant(),
            mailboxView: store.mailboxViewSettings(),
            inboxClassification: store.inboxClassificationSettings(),
            avatarPrivacy: store.avatarPrivacySettings(),
            browser: store.browserSettings(),
            compose: store.composeSettings(),
            signature: store.signatureSettings(),
            remoteContentPolicy: store.remoteContentPolicy(),
            notification: NotificationBackupSettings(store.notificationSettings()),
            update: store.updateSettings(),
            smartMailbox: store.smartMailboxSettings(),
            localRules: store.localRulesSettings(),
            folderPreferences: store.folderPreferences(),
            vipSender: store.vipSenderSettings(),
            followUp: store.followUpSettings(),
            messageTemplate: store.messageTemplateSettings(),
            fetchSchedule: store.fetchScheduleSettings(),
            calDAV: CalDAVBackupSettings(store.calDAVSettings()),
            encryption: store.encryptionSettings(),
            accountMailboxSync: store.accountMailboxSyncSettings(),
            mailboxSource: store.mailboxSourcePreferences(),
            folderVisibility: store.folderVisibilityPreferences(),
            preferenceSync: store.preferenceSyncSettings(),
            relatedMailAutoLoadAccountIDs: consentStore.autoLoadEnabledAccountIDs(among: accountIDs)
        )
    }

    /// Applies all payload families, ignoring per-family failures. The
    /// transactional restore path lives in `BackupRestorer`, which drives
    /// `categoryApplications` one at a time.
    static func apply(
        _ payload: SettingsBackupPayload,
        to store: SettingsPersistenceStore,
        mode: BackupRestoreMode,
        consentStore: RelatedConversationConsentStore = .shared
    ) {
        for category in categoryApplications(
            payload: payload,
            store: store,
            mode: mode,
            consentStore: consentStore
        ) {
            try? category.run()
        }
    }

    /// One application per family present in the payload, in a stable order.
    /// Each application merges or replaces its family on `run()` and can
    /// restore the pre-apply snapshot via `rollback()`.
    static func categoryApplications(
        payload: SettingsBackupPayload,
        store: SettingsPersistenceStore,
        mode: BackupRestoreMode,
        consentStore: RelatedConversationConsentStore = .shared
    ) -> [BackupCategoryApplication] {
        var categories: [BackupCategoryApplication] = []

        func scalar<T>(_ name: String, _ incoming: T?,
                       read: @escaping () -> T, write: @escaping (T) -> Void) {
            guard let incoming else { return }
            categories.append(BackupCategoryApplication(name: name, read: read, write: write) {
                write(incoming)
            })
        }

        func mergeable<T>(_ name: String, _ incoming: T?,
                          read: @escaping () -> T, write: @escaping (T) -> Void,
                          merge: @escaping (T, T) -> T) {
            guard let incoming else { return }
            categories.append(BackupCategoryApplication(name: name, read: read, write: write) {
                write(mode == .merge ? merge(read(), incoming) : incoming)
            })
        }

        scalar("appearanceTheme", payload.appearanceTheme,
               read: { store.appearanceThemeSettings() }, write: { store.save($0) })
        scalar("windowAppearance", payload.windowAppearance,
               read: { store.windowAppearancePreferences() }, write: { store.save($0) })
        scalar("appIcon", payload.appIcon,
               read: { store.appIconVariant() }, write: { store.save($0) })
        scalar("mailboxView", payload.mailboxView,
               read: { store.mailboxViewSettings() }, write: { store.save($0) })
        scalar("inboxClassification", payload.inboxClassification,
               read: { store.inboxClassificationSettings() }, write: { store.save($0) })
        scalar("avatarPrivacy", payload.avatarPrivacy,
               read: { store.avatarPrivacySettings() }, write: { store.save($0) })
        scalar("browser", payload.browser,
               read: { store.browserSettings() }, write: { store.save($0) })
        scalar("compose", payload.compose,
               read: { store.composeSettings() }, write: { store.save($0) })
        scalar("remoteContentPolicy", payload.remoteContentPolicy,
               read: { store.remoteContentPolicy() }, write: { store.save($0) })
        scalar("update", payload.update,
               read: { store.updateSettings() }, write: { store.save($0) })
        scalar("folderPreferences", payload.folderPreferences,
               read: { store.folderPreferences() }, write: { store.save($0) })
        scalar("followUp", payload.followUp,
               read: { store.followUpSettings() }, write: { store.save($0) })
        scalar("fetchSchedule", payload.fetchSchedule,
               read: { store.fetchScheduleSettings() }, write: { store.save($0) })
        scalar("encryption", payload.encryption,
               read: { store.encryptionSettings() }, write: { store.save($0) })
        scalar("accountMailboxSync", payload.accountMailboxSync,
               read: { store.accountMailboxSyncSettings() }, write: { store.save($0) })
        scalar("mailboxSource", payload.mailboxSource,
               read: { store.mailboxSourcePreferences() }, write: { store.save($0) })
        scalar("folderVisibility", payload.folderVisibility,
               read: { store.folderVisibilityPreferences() }, write: { store.save($0) })
        scalar("preferenceSync", payload.preferenceSync,
               read: { store.preferenceSyncSettings() }, write: { store.save($0) })

        mergeable("signature", payload.signature,
                  read: { store.signatureSettings() }, write: { store.save($0) }) { local, incoming in
            var merged = incoming
            merged.signatures = Self.mergedByID(local.signatures, incoming.signatures)
            merged.defaultSignatureIDsByAccountID = local.defaultSignatureIDsByAccountID
                .merging(incoming.defaultSignatureIDsByAccountID) { _, new in new }
            merged.accountIDsWithNoDefaultSignature = local.accountIDsWithNoDefaultSignature
                .union(incoming.accountIDsWithNoDefaultSignature)
            return merged
        }
        mergeable("smartMailbox", payload.smartMailbox,
                  read: { store.smartMailboxSettings() }, write: { store.save($0) }) { local, incoming in
            var merged = incoming
            merged.mailboxes = Self.mergedByID(local.mailboxes, incoming.mailboxes)
            merged.disabledBuiltInIDs = local.disabledBuiltInIDs.union(incoming.disabledBuiltInIDs)
            merged.displayOrder = local.displayOrder
                + incoming.displayOrder.filter { !local.displayOrder.contains($0) }
            return merged
        }
        mergeable("localRules", payload.localRules,
                  read: { store.localRulesSettings() }, write: { store.save($0) }) { local, incoming in
            var merged = incoming
            merged.rules = Self.mergedByID(local.rules, incoming.rules)
            return merged
        }
        mergeable("vipSender", payload.vipSender,
                  read: { store.vipSenderSettings() }, write: { store.save($0) }) { local, incoming in
            var merged = incoming
            merged.senders = Self.mergedByID(local.senders, incoming.senders)
            return merged
        }
        mergeable("messageTemplate", payload.messageTemplate,
                  read: { store.messageTemplateSettings() }, write: { store.save($0) }) { local, incoming in
            var merged = incoming
            merged.templates = Self.mergedByID(local.templates, incoming.templates)
            return merged
        }

        // Notification: device-bound fields always keep their local value.
        if let incoming = payload.notification {
            categories.append(BackupCategoryApplication(
                name: "notification",
                read: { store.notificationSettings() },
                write: { store.save($0) }
            ) {
                var merged = store.notificationSettings()
                merged.notificationsEnabled = incoming.notificationsEnabled
                merged.badgeEnabled = incoming.badgeEnabled
                merged.badgePolicy = incoming.badgePolicy
                merged.soundEnabled = incoming.soundEnabled
                merged.showPreviews = incoming.showPreviews
                merged.accountOverrides = incoming.accountOverrides
                merged.quietHoursEnabled = incoming.quietHoursEnabled
                merged.quietHoursStart = incoming.quietHoursStart
                merged.quietHoursEnd = incoming.quietHoursEnd
                store.save(merged)
            })
        }

        // CalDAV: the local Keychain credential pointer is preserved.
        if let incoming = payload.calDAV {
            categories.append(BackupCategoryApplication(
                name: "calDAV",
                read: { store.calDAVSettings() },
                write: { store.save($0) }
            ) {
                var merged = store.calDAVSettings()
                merged.featureFlagEnabled = incoming.featureFlagEnabled
                merged.isEnabled = incoming.isEnabled
                merged.serverURL = incoming.serverURL
                merged.calendarName = incoming.calendarName
                merged.collectionPath = incoming.collectionPath
                merged.useLocalBasicAuth = incoming.useLocalBasicAuth
                store.save(merged)
            })
        }

        // Related-mail consent is additive in both modes: restoring a backup
        // grants the consents recorded in it but never silently revokes a
        // consent the user made locally.
        if let incoming = payload.relatedMailAutoLoadAccountIDs {
            categories.append(BackupCategoryApplication(
                name: "relatedMailConsent",
                read: { consentStore.autoLoadEnabledAccountIDs(among: incoming) },
                write: { (enabled: [String]) in
                    for accountID in incoming where !enabled.contains(accountID) {
                        consentStore.setAutoLoadEnabled(false, accountID: accountID)
                    }
                }
            ) {
                for accountID in incoming {
                    consentStore.setAutoLoadEnabled(true, accountID: accountID)
                }
            })
        }

        return categories
    }

    /// `local` first, then backup items whose `id` is not already present.
    /// Local order is never changed.
    private static func mergedByID<Item: Identifiable>(_ local: [Item], _ incoming: [Item]) -> [Item] {
        let localIDs = Set(local.map(\.id))
        return local + incoming.filter { !localIDs.contains($0.id) }
    }
}
