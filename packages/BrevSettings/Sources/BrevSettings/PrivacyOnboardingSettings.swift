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
import BrevAvatars
import Foundation

/// Device-local completion state for the optional Privacy & Convenience Choices walkthrough.
///
/// Deliberately excluded from `PreferenceSyncAllowlist` and `.brevbackup` exports so
/// onboarding completion remains strictly per-device and never silently changes opt-in
/// settings across devices.
public struct PrivacyOnboardingSettings: Equatable, Sendable {
    /// Stable `UserDefaults` storage keys.
    public enum Key {
        /// Whether this device has completed or dismissed the first-run walkthrough.
        public static let hasCompletedOnboarding = "onboarding.privacyChoices.completed"
        /// Device-local record of a default AI provider displaced when enabling Apple Intelligence
        /// from the walkthrough so opting back out can restore it cleanly.
        static let displacedDefaultAIProviderID = "onboarding.privacyChoices.displacedDefaultAIProviderID"
        /// Device-local record of whether AI Writer was already available before the walkthrough
        /// enabled Apple Intelligence, preventing opt-out from leaving an unconsented provider active.
        static let aiWriterWasAvailableBeforeOnDeviceOptIn =
            "onboarding.privacyChoices.aiWriterWasAvailableBeforeOnDeviceOptIn"
    }

    /// `true` once the user has finished, kept defaults, or dismissed the first-run walkthrough.
    public var hasCompletedOnboarding: Bool

    /// Default state for a fresh installation: not yet shown.
    public static let defaults = PrivacyOnboardingSettings(hasCompletedOnboarding: false)

    /// Creates device-local privacy onboarding state.
    public init(hasCompletedOnboarding: Bool = false) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    /// Loads device-local onboarding completion state from `defaults`.
    public static func load(from defaults: UserDefaults = .standard) -> PrivacyOnboardingSettings {
        PrivacyOnboardingSettings(
            hasCompletedOnboarding: defaults.bool(forKey: Key.hasCompletedOnboarding)
        )
    }

    /// Persists device-local onboarding completion state to `defaults`.
    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding)
    }
}

/// Presentation context for the Privacy & Convenience Choices walkthrough.
public enum PrivacyOnboardingMode: Equatable, Sendable {
    /// Presented automatically once after first-run account setup.
    case firstRun
    /// Reopened deliberately by the user from Settings → Privacy.
    case reviewFromSettings
}

/// Plain-language localized copy helpers for the Privacy & Convenience Choices walkthrough.
public enum PrivacyOnboardingCopy {
    /// Accurate explanation for the trusted-sender remote images toggle given the active
    /// rich-HTML reader and tracking-pixel stripping settings.
    public static func trustedSendersSubtitle(
        useRichRenderer: Bool,
        stripTrackingPixels: Bool
    ) -> String {
        guard useRichRenderer else {
            return String(
                localized: "Requires the rich HTML reader in Settings → Reading → Mailbox View before remote images can load automatically.",
                bundle: .module
            )
        }
        if stripTrackingPixels {
            return String(
                localized: "Loads remote images automatically only for Contacts and senders you have replied to. Unknown senders stay blocked and tracking-pixel removal stays on.",
                bundle: .module
            )
        }
        return String(
            localized: "Loads remote images automatically only for Contacts and senders you have replied to. Tracking-pixel removal is currently off in Settings → Privacy, so trusted senders may load tracking images.",
            bundle: .module
        )
    }

    /// Explanation shown when turning on global AI consent from the walkthrough is blocked
    /// because an external per-account AI override is configured while AI Writer is disabled.
    public static let externalAccountAIRouteBlockedMessage = String(
        localized: "An external AI provider is assigned to an account. Review per-account routing in Settings → Writing → AI Writer before turning AI on.",
        bundle: .module
    )
}

/// Editable opt-in convenience choices presented by the Privacy & Convenience walkthrough.
///
/// Every convenience starts strictly `false` by default to preserve Brev's
/// zero-network-by-default privacy invariant.
public struct PrivacyOnboardingChoices: Equatable, Sendable {
    private static let legacyBuiltInExternalProviderID = AIProviderID("euria")

    /// Domain-only sender avatars (`AvatarPrivacySettings.useBIMI` + `useFavicon`).
    public var useDomainAvatars: Bool
    /// Gravatar sender lookup (`AvatarPrivacySettings.useGravatar`, sends SHA-256 email hash).
    public var useGravatar: Bool
    /// Trusted-sender remote HTML images (`MailboxViewSettings.allowRemoteContentForTrustedSenders`).
    public var allowRemoteContentForTrustedSenders: Bool
    /// Cross-device iCloud Key-Value preference sync (`PreferenceSyncSettings.isICloudSyncEnabled`).
    public var iCloudPreferenceSyncEnabled: Bool
    /// Keep checking configured mail servers with no window open on macOS (`NotificationSettings.backgroundMailEnabled`).
    public var backgroundMailEnabled: Bool
    /// Throttled background recent-mail and attachment indexing (`BackgroundIndexingSettings.isEnabled`).
    public var backgroundIndexingEnabled: Bool
    /// Zero-network on-device Apple Intelligence (`AIWriterSettings` + `.appleIntelligence` provider).
    public var onDeviceAIEnabled: Bool
    /// Automatic local thread summaries and priority triage (`AIWriterSettings.proactiveOnDeviceTriageEnabled`).
    public var proactiveOnDeviceTriageEnabled: Bool

    /// Conservative privacy defaults: every opt-in convenience is off.
    public static let allOff = PrivacyOnboardingChoices(
        useDomainAvatars: false,
        useGravatar: false,
        allowRemoteContentForTrustedSenders: false,
        iCloudPreferenceSyncEnabled: false,
        backgroundMailEnabled: false,
        backgroundIndexingEnabled: false,
        onDeviceAIEnabled: false,
        proactiveOnDeviceTriageEnabled: false
    )

    /// Creates a walkthrough selection snapshot.
    public init(
        useDomainAvatars: Bool = false,
        useGravatar: Bool = false,
        allowRemoteContentForTrustedSenders: Bool = false,
        iCloudPreferenceSyncEnabled: Bool = false,
        backgroundMailEnabled: Bool = false,
        backgroundIndexingEnabled: Bool = false,
        onDeviceAIEnabled: Bool = false,
        proactiveOnDeviceTriageEnabled: Bool = false
    ) {
        self.useDomainAvatars = useDomainAvatars
        self.useGravatar = useGravatar
        self.allowRemoteContentForTrustedSenders = allowRemoteContentForTrustedSenders
        self.iCloudPreferenceSyncEnabled = iCloudPreferenceSyncEnabled
        self.backgroundMailEnabled = backgroundMailEnabled
        self.backgroundIndexingEnabled = backgroundIndexingEnabled
        self.onDeviceAIEnabled = onDeviceAIEnabled
        self.proactiveOnDeviceTriageEnabled = proactiveOnDeviceTriageEnabled
    }

    /// Loads current persisted values into the walkthrough draft.
    public static func load(
        from settingsStore: SettingsPersistenceStore = .standard,
        appleIntelligenceAvailability: AppleIntelligenceAvailability = .current()
    ) -> PrivacyOnboardingChoices {
        let avatars = settingsStore.avatarPrivacySettings()
        let mailboxView = settingsStore.mailboxViewSettings()
        let preferenceSync = settingsStore.preferenceSyncSettings()
        let notifications = settingsStore.notificationSettings()
        let backgroundIndexing = settingsStore.backgroundIndexingSettings()
        let aiWriter = settingsStore.aiWriterSettings()
        let aiConfigs = (try? settingsStore.aiProviderConfigurations()) ?? []
        let aiAssignments = (try? settingsStore.aiProviderAssignments()) ?? AIProviderAccountAssignments()
        let assignedProviderIDs = aiAssignments.assignedProviderIDs
        let hasActiveAppleIntelligence = aiConfigs.contains { config in
            guard config.kind == .appleIntelligence,
                  config.isEnabled,
                  config.validationIssues.isEmpty
            else { return false }
            return config.isDefault
                || config.assignedAccountID != nil
                || assignedProviderIDs.contains(config.id)
        }
        let onDeviceAIActive = appleIntelligenceAvailability.isSelectable
            && aiWriter.isAvailable
            && hasActiveAppleIntelligence

        return PrivacyOnboardingChoices(
            useDomainAvatars: avatars.useBIMI || avatars.useFavicon,
            useGravatar: avatars.useGravatar,
            allowRemoteContentForTrustedSenders: mailboxView.allowRemoteContentForTrustedSenders,
            iCloudPreferenceSyncEnabled: preferenceSync.isICloudSyncEnabled,
            backgroundMailEnabled: notifications.backgroundMailEnabled,
            backgroundIndexingEnabled: backgroundIndexing.isEnabled,
            onDeviceAIEnabled: onDeviceAIActive,
            proactiveOnDeviceTriageEnabled: onDeviceAIActive && aiWriter.proactiveOnDeviceTriageEnabled
        )
    }

    /// Returns `true` when turning on global AI consent from the walkthrough would immediately
    /// activate an external/non-on-device per-account AI override without separate endpoint consent.
    ///
    /// Fails closed so a zero-network on-device prompt can never silently grant consent for a
    /// previously configured cloud or BYOK per-account route.
    public static func blocksOnDeviceAIOptInDueToExternalAccountRoutes(
        in settingsStore: SettingsPersistenceStore = .standard
    ) -> Bool {
        guard !settingsStore.aiWriterSettings().isAvailable else { return false }
        let configs = (try? settingsStore.aiProviderConfigurations()) ?? []
        let assignments = (try? settingsStore.aiProviderAssignments()) ?? AIProviderAccountAssignments()
        let assignedIDs = assignments.assignedProviderIDs

        if assignedIDs.contains(legacyBuiltInExternalProviderID) {
            return true
        }
        return configs.contains { config in
            guard !config.kind.isOnDevice,
                  config.isEnabled,
                  config.validationIssues.isEmpty
            else { return false }
            return config.assignedAccountID != nil || assignedIDs.contains(config.id)
        }
    }

    /// Result describing which subsystems changed when applying walkthrough choices.
    public struct ApplyResult: Equatable, Sendable {
        /// Updated avatar preferences when sender-avatar settings changed.
        public let updatedAvatarPreferences: AvatarPreferences?
        /// `true` when AI settings or provider configuration changed and backends should reload.
        public let aiConfigurationChanged: Bool

        /// Creates an apply result summary.
        public init(
            updatedAvatarPreferences: AvatarPreferences? = nil,
            aiConfigurationChanged: Bool = false
        ) {
            self.updatedAvatarPreferences = updatedAvatarPreferences
            self.aiConfigurationChanged = aiConfigurationChanged
        }
    }

    /// Applies only choices that changed relative to `initial` and marks onboarding complete.
    ///
    /// Diffing against `initial` preserves granular settings the user did not touch
    /// (for example a single BIMI-only avatar setting, or a separately configured BYOK
    /// AI provider) while never flipping `allowRemoteContent` on or disabling tracking-pixel
    /// stripping.
    @discardableResult
    public func apply(
        to settingsStore: SettingsPersistenceStore = .standard,
        relativeTo initial: PrivacyOnboardingChoices,
        appleIntelligenceAvailability: AppleIntelligenceAvailability = .current()
    ) -> ApplyResult {
        var updatedAvatarPreferences: AvatarPreferences?
        if useDomainAvatars != initial.useDomainAvatars || useGravatar != initial.useGravatar {
            var avatars = settingsStore.avatarPrivacySettings()
            if useDomainAvatars != initial.useDomainAvatars {
                avatars.useBIMI = useDomainAvatars
                avatars.useFavicon = useDomainAvatars
            }
            if useGravatar != initial.useGravatar {
                avatars.useGravatar = useGravatar
            }
            settingsStore.save(avatars)
            updatedAvatarPreferences = avatars.avatarPreferences
        }

        if allowRemoteContentForTrustedSenders != initial.allowRemoteContentForTrustedSenders {
            var mailboxView = settingsStore.mailboxViewSettings()
            // Never persist or silently enable remote images when the rich HTML reader is off.
            if mailboxView.useRichRenderer {
                mailboxView.allowRemoteContentForTrustedSenders = allowRemoteContentForTrustedSenders
                settingsStore.save(mailboxView)
            }
        }

        if iCloudPreferenceSyncEnabled != initial.iCloudPreferenceSyncEnabled {
            var syncSettings = settingsStore.preferenceSyncSettings()
            syncSettings.isICloudSyncEnabled = iCloudPreferenceSyncEnabled
            settingsStore.save(syncSettings)
        }

        if backgroundMailEnabled != initial.backgroundMailEnabled {
            var notifications = settingsStore.notificationSettings()
            notifications.backgroundMailEnabled = backgroundMailEnabled
            settingsStore.save(notifications)
        }

        if backgroundIndexingEnabled != initial.backgroundIndexingEnabled {
            var indexing = settingsStore.backgroundIndexingSettings()
            indexing.isEnabled = backgroundIndexingEnabled
            settingsStore.save(indexing)
        }

        let aiConfigurationChanged = applyOnDeviceAIChanges(
            to: settingsStore,
            relativeTo: initial,
            appleIntelligenceAvailability: appleIntelligenceAvailability
        )

        PrivacyOnboardingSettings(hasCompletedOnboarding: true).save(to: settingsStore.defaults)

        return ApplyResult(
            updatedAvatarPreferences: updatedAvatarPreferences,
            aiConfigurationChanged: aiConfigurationChanged
        )
    }

    /// Marks onboarding completed without modifying any persisted opt-in setting.
    public static func keepPrivacyDefaults(
        in settingsStore: SettingsPersistenceStore = .standard
    ) {
        PrivacyOnboardingSettings(hasCompletedOnboarding: true).save(to: settingsStore.defaults)
    }

    /// Returns `true` when any onboarding-covered privacy or convenience option is already enabled.
    public static func hasExistingCustomizedSettings(
        in settingsStore: SettingsPersistenceStore = .standard
    ) -> Bool {
        let avatars = settingsStore.avatarPrivacySettings()
        if avatars != .initialsOnly {
            return true
        }
        let mailboxView = settingsStore.mailboxViewSettings()
        if mailboxView.allowRemoteContent || mailboxView.allowRemoteContentForTrustedSenders {
            return true
        }
        if settingsStore.preferenceSyncSettings().isICloudSyncEnabled {
            return true
        }
        if settingsStore.notificationSettings().backgroundMailEnabled {
            return true
        }
        if settingsStore.backgroundIndexingSettings().isEnabled {
            return true
        }
        if settingsStore.aiWriterSettings().isAvailable {
            return true
        }
        return false
    }

    private func applyOnDeviceAIChanges(
        to settingsStore: SettingsPersistenceStore,
        relativeTo initial: PrivacyOnboardingChoices,
        appleIntelligenceAvailability: AppleIntelligenceAvailability
    ) -> Bool {
        let isBlockedByExternalRoutes = Self.blocksOnDeviceAIOptInDueToExternalAccountRoutes(in: settingsStore)
        let effectiveOnDeviceAI = appleIntelligenceAvailability.isSelectable
            && onDeviceAIEnabled
            && (!isBlockedByExternalRoutes || initial.onDeviceAIEnabled)
        let effectiveProactive = effectiveOnDeviceAI && proactiveOnDeviceTriageEnabled
        let initialProactive = initial.onDeviceAIEnabled && initial.proactiveOnDeviceTriageEnabled

        guard effectiveOnDeviceAI != initial.onDeviceAIEnabled
            || effectiveProactive != initialProactive
        else {
            return false
        }

        var aiWriter = settingsStore.aiWriterSettings()
        var configs = (try? settingsStore.aiProviderConfigurations()) ?? []
        let defaults = settingsStore.defaults

        if effectiveOnDeviceAI != initial.onDeviceAIEnabled {
            if effectiveOnDeviceAI {
                let wasAlreadyAvailable = aiWriter.isAvailable
                defaults.set(
                    wasAlreadyAvailable,
                    forKey: PrivacyOnboardingSettings.Key.aiWriterWasAvailableBeforeOnDeviceOptIn
                )

                if let displacedDefault = configs.first(where: {
                    $0.kind != .appleIntelligence && $0.isDefault && $0.isEnabled && $0.validationIssues.isEmpty
                }) {
                    defaults.set(
                        displacedDefault.id.rawValue,
                        forKey: PrivacyOnboardingSettings.Key.displacedDefaultAIProviderID
                    )
                } else {
                    defaults.removeObject(forKey: PrivacyOnboardingSettings.Key.displacedDefaultAIProviderID)
                }

                let existing = configs.first { $0.id == AppleIntelligenceAIBackend.providerID }
                let appleConfig = AIProviderConfiguration.appleIntelligence(
                    isEnabled: true,
                    isDefault: true,
                    assignedAccountID: existing?.assignedAccountID
                )
                configs.removeAll { $0.id == appleConfig.id }
                configs = configs.map { existingConfig in
                    var updated = existingConfig
                    updated.isDefault = false
                    return updated
                }
                configs.append(appleConfig)
                try? settingsStore.saveAIProviderConfigurations(configs)

                aiWriter.setAvailable(true)
                aiWriter.proactiveOnDeviceTriageEnabled = effectiveProactive
                settingsStore.save(aiWriter)
            } else {
                configs = configs.map { existingConfig in
                    guard existingConfig.kind == .appleIntelligence else { return existingConfig }
                    var updated = existingConfig
                    updated.isEnabled = false
                    updated.isDefault = false
                    return updated
                }

                let hasExplicitOtherDefault = configs.contains {
                    $0.kind != .appleIntelligence && $0.isDefault && $0.isEnabled && $0.validationIssues.isEmpty
                }
                if !hasExplicitOtherDefault,
                   let displacedRawID = defaults.string(
                       forKey: PrivacyOnboardingSettings.Key.displacedDefaultAIProviderID
                   ) {
                    let displacedID = AIProviderID(displacedRawID)
                    if let index = configs.firstIndex(where: {
                        $0.id == displacedID && $0.isEnabled && $0.validationIssues.isEmpty
                    }) {
                        configs[index].isDefault = true
                    }
                }
                defaults.removeObject(forKey: PrivacyOnboardingSettings.Key.displacedDefaultAIProviderID)
                try? settingsStore.saveAIProviderConfigurations(configs)

                let assignments = (try? settingsStore.aiProviderAssignments()) ?? AIProviderAccountAssignments()
                let assignedIDs = assignments.assignedProviderIDs
                let hasOtherUsableRoute = configs.contains { config in
                    guard config.kind != .appleIntelligence,
                          config.isEnabled,
                          config.validationIssues.isEmpty
                    else { return false }
                    return config.isDefault
                        || config.assignedAccountID != nil
                        || assignedIDs.contains(config.id)
                }
                let hadPriorAIWriterConsent = defaults.object(
                    forKey: PrivacyOnboardingSettings.Key.aiWriterWasAvailableBeforeOnDeviceOptIn
                ) as? Bool ?? true
                defaults.removeObject(
                    forKey: PrivacyOnboardingSettings.Key.aiWriterWasAvailableBeforeOnDeviceOptIn
                )

                aiWriter.proactiveOnDeviceTriageEnabled = false
                if !hasOtherUsableRoute || !hadPriorAIWriterConsent {
                    aiWriter.setAvailable(false)
                }
                settingsStore.save(aiWriter)
            }
            return true
        }

        // Only proactive on-device triage changed while on-device AI remained enabled.
        aiWriter.proactiveOnDeviceTriageEnabled = effectiveProactive
        settingsStore.save(aiWriter)
        return true
    }
}

/// Pure policy governing when the first-run Privacy & Convenience walkthrough auto-presents.
public enum PrivacyOnboardingPresentationPolicy {
    /// Returns `true` when demo/mock mode, automated tests, or snapshot runs should suppress onboarding.
    public static func isSuppressedByEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        defaults: UserDefaults = .standard,
        isDeveloperBuild: Bool
    ) -> Bool {
        if DeveloperSettings.isDemoModeRequested(
            environment: environment,
            defaults: defaults,
            isDeveloperBuild: isDeveloperBuild
        ) {
            return true
        }
        if environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
            || environment["RECORD_SNAPSHOTS"] != nil
            || environment["BREV_UI_TESTING"] != nil
            || environment["BREV_SKIP_PRIVACY_ONBOARDING"] != nil
            || arguments.contains("-UITesting")
            || arguments.contains("--uitesting") {
            return true
        }
        return false
    }

    /// Returns `true` only when the app launched with zero persisted or restored real accounts
    /// and no restore failure awaiting retry.
    ///
    /// Checking the persisted account store as well as restore-error/retry state ensures a
    /// transient restore failure followed by a retry from `LoginView` never treats an existing
    /// user as a brand-new installation.
    public static func didStartWithoutAccounts(
        storedAccountBackendIdentifiers: [String],
        visibleBackendIdentifiers: [String],
        demoBackendIdentifier: String,
        accountRestoreErrorCount: Int,
        canRetrySessionRestore: Bool
    ) -> Bool {
        let hasStoredRealAccount = storedAccountBackendIdentifiers.contains {
            $0 != demoBackendIdentifier
        }
        let hasVisibleRealAccount = visibleBackendIdentifiers.contains {
            $0 != demoBackendIdentifier
        }
        return !hasStoredRealAccount
            && !hasVisibleRealAccount
            && accountRestoreErrorCount == 0
            && !canRetrySessionRestore
    }

    /// Returns `true` only when a brand-new user finishes adding their first real account
    /// and no suppression, demo session, in-flight sign-in/restore, prior completion, or
    /// competing modal is active.
    public static func shouldPresentAfterFirstAccountSetup(
        hasCompletedOnboarding: Bool,
        isSuppressedByEnvironment: Bool,
        isDemoSession: Bool,
        didStartWithoutAccounts: Bool,
        hasVisibleRealAccount: Bool,
        isSigningIn: Bool = false,
        isRestoringSession: Bool = false,
        hasPendingInitialMailboxSelection: Bool,
        hasOtherModalPresented: Bool,
        hasExistingCustomizedSettings: Bool
    ) -> Bool {
        guard !hasCompletedOnboarding,
              !isSuppressedByEnvironment,
              !isDemoSession,
              didStartWithoutAccounts,
              hasVisibleRealAccount,
              !isSigningIn,
              !isRestoringSession,
              !hasPendingInitialMailboxSelection,
              !hasOtherModalPresented,
              !hasExistingCustomizedSettings
        else {
            return false
        }
        return true
    }
}
