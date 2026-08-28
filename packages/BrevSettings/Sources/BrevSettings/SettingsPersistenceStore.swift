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

import BrevAI
import BrevBackend
import BrevDesign
import Foundation

/// Narrow persistence boundary for the shared settings surface.
///
/// Section views interact with this typed store instead of reaching
/// directly for `UserDefaults`, keeping key ownership in the model
/// layer while still sharing values with the mail surface.
public struct SettingsPersistenceStore: Equatable {
    public static let standard = SettingsPersistenceStore(defaults: .standard)

    let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public static func == (
        lhs: SettingsPersistenceStore,
        rhs: SettingsPersistenceStore
    ) -> Bool {
        lhs.defaults === rhs.defaults
    }

    func appearanceThemeSettings() -> AppearanceThemeSettings {
        AppearanceThemeSettings.load(from: defaults)
    }

    func save(_ settings: AppearanceThemeSettings) {
        settings.save(to: defaults)
    }

    func windowAppearancePreferences() -> WindowAppearancePreferences {
        WindowAppearancePreferences.load(from: defaults)
    }

    func save(_ preferences: WindowAppearancePreferences) {
        preferences.save(to: defaults)
    }

    func appIconVariant() -> AppIconVariant {
        AppIconPreferences.load(defaults: defaults)
    }

    func save(_ variant: AppIconVariant) {
        AppIconPreferences.save(variant, defaults: defaults)
    }

    func developerSettings() -> DeveloperSettings {
        DeveloperSettings.load(from: defaults)
    }

    func save(_ settings: DeveloperSettings) {
        settings.save(to: defaults)
    }

    func mailboxViewSettings() -> MailboxViewSettings {
        MailboxViewSettings.load(from: defaults)
    }

    func save(_ settings: MailboxViewSettings) {
        settings.save(to: defaults)
    }

    func inboxClassificationSettings() -> InboxClassificationSettings {
        InboxClassificationSettings.load(from: defaults)
    }

    func save(_ settings: InboxClassificationSettings) {
        settings.save(to: defaults)
    }

    func avatarPrivacySettings() -> AvatarPrivacySettings {
        AvatarPrivacySettings.load(from: defaults)
    }

    func save(_ settings: AvatarPrivacySettings) {
        settings.save(to: defaults)
    }

    func browserSettings() -> BrowserSettings {
        BrowserSettings.load(from: defaults)
    }

    func save(_ settings: BrowserSettings) {
        settings.save(to: defaults)
    }

    func composeSettings() -> ComposeSettings {
        ComposeSettings.load(from: defaults)
    }

    func save(_ settings: ComposeSettings) {
        settings.save(to: defaults)
    }

    public func signatureSettings() -> SignatureSettings {
        SignatureSettings.load(from: defaults)
    }

    public func save(_ settings: SignatureSettings) {
        settings.save(to: defaults)
    }

    func remoteContentPolicy() -> RemoteContentPolicy {
        RemoteContentPolicy.load(from: defaults)
    }

    func save(_ policy: RemoteContentPolicy) {
        policy.save(to: defaults)
    }

    func notificationSettings() -> NotificationSettings {
        NotificationSettings.load(from: defaults)
    }

    func save(_ settings: NotificationSettings) {
        settings.save(to: defaults)
    }

    public func updateSettings() -> UpdateSettings {
        UpdateSettings.load(from: defaults)
    }

    public func save(_ settings: UpdateSettings) {
        settings.save(to: defaults)
    }

    func aiWriterSettings() -> AIWriterSettings {
        AIWriterSettings.load(from: defaults)
    }

    func save(_ settings: AIWriterSettings) {
        settings.save(to: defaults)
    }

    var isAIProviderConfigurationVisible: Bool {
        AIProviderFeatureFlags.isProviderConfigurationVisible(defaults: defaults)
    }

    func aiProviderConfigurations() throws -> [AIProviderConfiguration] {
        try AIProviderConfigurationStore(defaults: defaults).load()
    }

    func saveAIProviderConfigurations(_ configurations: [AIProviderConfiguration]) throws {
        try AIProviderConfigurationStore(defaults: defaults).save(configurations)
    }

    func aiProviderAssignments() throws -> AIProviderAccountAssignments {
        try AIProviderAccountAssignmentStore(defaults: defaults).load()
    }

    func saveAIProviderAssignments(_ assignments: AIProviderAccountAssignments) throws {
        try AIProviderAccountAssignmentStore(defaults: defaults).save(assignments)
    }

    func removeAIProviderAssignments(providerID: AIProviderID) throws {
        try AIProviderAccountAssignmentStore(defaults: defaults).removeProvider(providerID)
    }

    func smartMailboxSettings() -> SmartMailboxSettings {
        SmartMailboxSettings.load(from: defaults)
    }

    func save(_ settings: SmartMailboxSettings) {
        settings.save(to: defaults)
    }

    public func localRulesSettings() -> LocalRulesSettings {
        LocalRulesSettings.load(from: defaults)
    }

    public func save(_ settings: LocalRulesSettings) {
        settings.save(to: defaults)
    }

    func folderPreferences() -> FolderPreferences {
        FolderPreferences.load(from: defaults)
    }

    func save(_ preferences: FolderPreferences) {
        preferences.save(to: defaults)
    }

    public func vipSenderSettings() -> VIPSenderSettings {
        VIPSenderSettings.load(from: defaults)
    }

    public func save(_ settings: VIPSenderSettings) {
        settings.save(to: defaults)
    }

    public func followUpSettings() -> FollowUpSettings {
        FollowUpSettings.load(from: defaults)
    }

    public func save(_ settings: FollowUpSettings) {
        settings.save(to: defaults)
    }

    public func messageTemplateSettings() -> MessageTemplateSettings {
        MessageTemplateSettings.load(from: defaults)
    }

    public func save(_ settings: MessageTemplateSettings) {
        settings.save(to: defaults)
    }

    func fetchScheduleSettings() -> FetchScheduleSettings {
        FetchScheduleSettings.load(from: defaults)
    }

    func save(_ settings: FetchScheduleSettings) {
        settings.save(to: defaults)
    }

    func calDAVSettings() -> CalDAVSettings {
        CalDAVSettings.load(from: defaults)
    }

    func save(_ settings: CalDAVSettings) {
        settings.save(to: defaults)
    }

    func encryptionSettings() -> EncryptionSettings {
        EncryptionSettings.load(from: defaults)
    }

    func save(_ settings: EncryptionSettings) {
        settings.save(to: defaults)
    }

    func securityKeyMaterialSettings() -> SecurityKeyMaterialSettings {
        SecurityKeyMaterialSettings.load(from: defaults)
    }

    func save(_ settings: SecurityKeyMaterialSettings) {
        settings.save(to: defaults)
    }

    public func accountMailboxSyncSettings() -> AccountMailboxSyncSettings {
        AccountMailboxSyncSettings.load(from: defaults)
    }

    public func save(_ settings: AccountMailboxSyncSettings) {
        settings.save(to: defaults)
    }

    func mailboxSourcePreferences() -> MailboxSourcePreferences {
        MailboxSourcePreferencesStorage.load(from: defaults)
    }

    func save(_ preferences: MailboxSourcePreferences) {
        MailboxSourcePreferencesStorage.save(preferences, to: defaults)
    }

    func folderVisibilityPreferences() -> FolderVisibilityPreferences {
        FolderVisibilityPreferencesStorage.load(from: defaults)
    }

    func save(_ preferences: FolderVisibilityPreferences) {
        FolderVisibilityPreferencesStorage.save(preferences, to: defaults)
    }

    func preferenceSyncSettings() -> PreferenceSyncSettings {
        PreferenceSyncSettings.load(from: defaults)
    }

    func save(_ settings: PreferenceSyncSettings) {
        settings.save(to: defaults)
    }

    public func removeAccountScopedState(accountID: String) {
        RecentRecipientStore(defaults: defaults).removeAccount(accountID)
    }
}
