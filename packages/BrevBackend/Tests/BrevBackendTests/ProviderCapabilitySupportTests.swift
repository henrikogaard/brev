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

@testable import BrevBackend
import Testing

@Suite("Provider capability support")
struct ProviderCapabilitySupportTests {
    @Test("Provider-native features require explicit provider support")
    func providerNativeFeaturesRequireExplicitProviderSupport() {
        let support = BackendFeature.autoReply.availability(in: [.oauthAuth])

        #expect(support.kind == .requiresProviderAPI)
        #expect(support.isAvailable == false)
        #expect(support.explanation.contains("provider"))
    }

    @Test("standards-backed features can be supported by discovered extensions")
    func standardsBackedFeaturesCanBeSupportedByDiscoveredExtensions() {
        let support = BackendFeature.autoReply.availability(
            in: [.oauthAuth, .manageSieve, .sieveVacation]
        )

        #expect(support.kind == .supported)
        #expect(support.isAvailable)
    }

    @Test("provider-native auto-reply is supported when management mutations exist")
    func providerNativeAutoReplyIsSupportedWhenManagementMutationsExist() {
        let support = BackendFeature.autoReply.availability(in: [.oauthAuth, .providerAPI, .autoReply])

        #expect(support.kind == .supported)
        #expect(support.isAvailable)
        #expect(support.explanation.contains("create, update, activate, deactivate, delete"))
    }

    @Test("local-only diagnostics remain available without provider support")
    func localOnlyDiagnosticsRemainAvailableWithoutProviderSupport() {
        let support = BackendFeature.syncHealthDiagnostics.availability(in: [])

        #expect(support.kind == .localOnly)
        #expect(support.isAvailable)
    }

    @Test("server rules explain missing standards extensions")
    func serverRulesExplainMissingStandardsExtensions() {
        let support = BackendFeature.serverRules.availability(in: [.manageSieve])

        #expect(support.kind == .requiresStandardsExtension)
        #expect(support.isAvailable == false)
        #expect(support.explanation.contains("Sieve"))
    }

    @Test("provider-native server rules are supported when compatible mutations exist")
    func providerNativeServerRulesAreSupportedWhenCompatibleMutationsExist() {
        let support = BackendFeature.serverRules.availability(in: [.oauthAuth, .providerAPI, .serverRules])

        #expect(support.kind == .supported)
        #expect(support.isAvailable)
        #expect(support.explanation.contains("rename, enable, disable, delete, and reorder"))
    }

    @Test("forwarding is partially available when provider server-rule APIs exist")
    func forwardingUsesCapabilityGate() {
        let support = BackendFeature.forwarding.availability(in: [.providerAPI, .serverRules])

        #expect(support.kind == .partial)
        #expect(support.isAvailable)
        #expect(support.explanation.contains("explicit confirmation"))
    }

    @Test("shared mailbox access requires explicit shared mailbox capability")
    func sharedMailboxAccessRequiresCapability() {
        let unsupported = BackendFeature.sharedMailboxAccess.availability(in: [.providerAPI])
        let supported = BackendFeature.sharedMailboxAccess.availability(in: [.providerAPI, .sharedMailboxes])

        #expect(unsupported.kind == .requiresProviderAPI)
        #expect(unsupported.isAvailable == false)
        #expect(supported.kind == .supported)
        #expect(supported.isAvailable)
    }

    @Test("enterprise shared mailbox operations distinguish access management and policy restrictions")
    func enterpriseSharedMailboxOperationsDistinguishAccessManagementAndPolicyRestrictions() {
        let context = BackendFeatureAvailabilityContext(
            capabilities: [.providerAPI, .sharedMailboxes],
            enterpriseCapabilities: [.sharedMailboxManagement, .sendAs, .sendOnBehalf]
        )
        let restricted = BackendFeatureAvailabilityContext(
            capabilities: [.providerAPI, .sharedMailboxes],
            enterpriseCapabilities: [.sharedMailboxManagement, .sendAs, .sendOnBehalf],
            policyRestrictions: [.sharedMailboxManagement]
        )

        let supported = BackendFeature.sharedMailboxAccess.availability(in: context)
        let policyDisabled = BackendFeature.sharedMailboxAccess.availability(in: restricted)

        #expect(supported.kind == .supported)
        #expect(supported.isAvailable)
        #expect(supported.explanation.contains("Send As"))
        #expect(supported.explanation.contains("Send on Behalf"))
        #expect(policyDisabled.kind == .policyDisabled)
        #expect(policyDisabled.isAvailable == false)
        #expect(policyDisabled.explanation.contains("admin policy"))
    }

    @Test("enterprise retention and sensitivity labels expose read only or policy disabled states")
    func enterpriseRetentionAndSensitivityExposeReadOnlyOrPolicyDisabledStates() {
        let readOnlyRetention = BackendFeature.retentionPolicies.availability(
            in: BackendFeatureAvailabilityContext(
                capabilities: [.providerAPI],
                enterpriseCapabilities: [.retentionPolicyVisibility]
            )
        )
        let sensitivityLabels = BackendFeature.sensitivityLabels.availability(
            in: BackendFeatureAvailabilityContext(
                capabilities: [.providerAPI],
                enterpriseCapabilities: [.sensitivityLabels],
                policyRestrictions: [.sensitivityLabels]
            )
        )

        #expect(readOnlyRetention.kind == .readOnly)
        #expect(readOnlyRetention.isAvailable)
        #expect(readOnlyRetention.explanation.contains("visible"))
        #expect(sensitivityLabels.kind == .policyDisabled)
        #expect(sensitivityLabels.isAvailable == false)
        #expect(sensitivityLabels.explanation.contains("admin policy"))
    }

    @Test("mailbox role mapping and folder subscription settings are source-capability gated")
    func accountSettingsCapabilitiesAreGated() {
        let mappings = BackendFeature.mailboxRoleMappings.availability(in: [.imapOAuth])
        let subscriptions = BackendFeature.folderSubscriptionSync.availability(in: [.multipleMailboxes])

        #expect(mappings.kind == .partial)
        #expect(mappings.isAvailable)
        #expect(subscriptions.kind == .partial)
        #expect(subscriptions.isAvailable)
    }

    @Test("full preview capabilities enable provider-native feature gates")
    func fullPreviewCapabilitiesEnableProviderNativeFeatureGates() {
        let capabilities = BackendCapabilities.full

        #expect(BackendFeature.autoReply.availability(in: capabilities).isAvailable)
        #expect(BackendFeature.serverRules.availability(in: capabilities).isAvailable)
        #expect(BackendFeature.serverAliases.availability(in: capabilities).isAvailable)
        #expect(BackendFeature.serverSignatures.availability(in: capabilities).isAvailable)
        #expect(BackendFeature.forwarding.availability(in: capabilities).isAvailable)
        #expect(BackendFeature.sharedMailboxAccess.availability(in: capabilities).isAvailable)
        #expect(BackendFeature.mailboxRoleMappings.availability(in: capabilities).isAvailable)
        #expect(BackendFeature.folderSubscriptionSync.availability(in: capabilities).isAvailable)
    }
}
