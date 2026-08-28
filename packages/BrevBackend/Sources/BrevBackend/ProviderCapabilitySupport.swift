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

/// User-facing support state for a feature on a concrete backend.
public enum BackendFeatureSupportKind: String, Sendable, Hashable, Codable, CaseIterable {
    case supported
    case partial
    case unsupported
    case requiresProviderAPI
    case requiresStandardsExtension
    case readOnly
    case policyDisabled
    case localOnly
    case unknown
}

/// Mail-client features whose availability varies by provider,
/// standards extension, or local-only Brev behavior.
public enum BackendFeature: String, Sendable, Hashable, Codable, CaseIterable {
    case autoReply
    case serverRules
    case serverAliases
    case serverSignatures
    case forwarding
    case sharedMailboxAccess
    case mailboxRoleMappings
    case folderSubscriptionSync
    case listUnsubscribe
    case syncHealthDiagnostics
    case flagColors
    case retentionPolicies
    case sensitivityLabels

    public func availability(in capabilities: BackendCapabilities) -> BackendFeatureSupport {
        availability(in: BackendFeatureAvailabilityContext(capabilities: capabilities))
    }

    public func availability(in context: BackendFeatureAvailabilityContext) -> BackendFeatureSupport {
        let capabilities = context.capabilities

        switch self {
        case .autoReply:
            if capabilities.contains(.sieveVacation) {
                return supported("Server-side auto-reply is available for this account.")
            }
            if capabilities.contains(.autoReply) {
                return supported(
                    "Provider auto-reply management is available: Brev can list, create, update, activate, deactivate, delete, and reset the provider counter where the account has permission."
                )
            }
            if capabilities.contains(.manageSieve) {
                return support(
                    .requiresStandardsExtension,
                    "This server exposes ManageSieve, but Sieve vacation support has not been discovered."
                )
            }
            return support(
                .requiresProviderAPI,
                "Auto-reply requires provider API support or a server-side Sieve vacation extension."
            )

        case .serverRules:
            if capabilities.contains(.serverRules) {
                return supported(
                    "Provider server rules are available for compatible filters: Brev can list, create, rename, enable, disable, delete, and reorder them where the account has permission."
                )
            }
            if capabilities.contains(.manageSieve) {
                return support(
                    .requiresStandardsExtension,
                    "Server-side rules require a compatible Sieve rule capability before editing is available."
                )
            }
            return support(
                .requiresProviderAPI,
                "Server-side rules require provider API support or ManageSieve."
            )

        case .serverAliases:
            if capabilities.contains(.aliases) {
                return supported("Server-side aliases are available for this account.")
            }
            return support(
                .requiresProviderAPI,
                "Server-side aliases require provider API support; generic IMAP/SMTP does not expose them."
            )

        case .serverSignatures:
            if capabilities.contains(.serverSignatures) {
                return supported("Server-side signatures are available for this account.")
            }
            return support(
                .requiresProviderAPI,
                "Server-side signatures require provider API support; generic IMAP/SMTP does not expose them."
            )

        case .forwarding:
            if capabilities.contains(.providerAPI) && capabilities.contains(.serverRules) {
                return support(
                    .partial,
                    "Forwarding is available for provider-backed accounts. Brev requires explicit confirmation and validation before enabling delivery to external destinations."
                )
            }
            return support(
                .requiresProviderAPI,
                "Forwarding requires provider API support; generic IMAP/SMTP does not expose account-level forwarding controls."
            )

        case .sharedMailboxAccess:
            if context.policyRestrictions.contains(.sharedMailboxManagement) {
                return policyDisabled(
                    "Shared mailbox management is disabled by admin policy for this account."
                )
            }
            if capabilities.contains(.sharedMailboxes) {
                if context.enterpriseCapabilities.contains(.sharedMailboxManagement) {
                    var operations = ["shared/delegated mailbox management"]
                    if context.enterpriseCapabilities.contains(.sendAs) {
                        operations.append("Send As")
                    }
                    if context.enterpriseCapabilities.contains(.sendOnBehalf) {
                        operations.append("Send on Behalf")
                    }
                    return supported(
                        "Shared and delegated mailbox controls are available, including \(operations.joined(separator: ", ")) where the current user has permission."
                    )
                }
                return supported("Shared and delegated mailbox access is available for this account.")
            }
            return support(
                .requiresProviderAPI,
                "Shared/delegated mailbox controls require provider capabilities. Generic IMAP/SMTP accounts do not expose delegation semantics."
            )

        case .mailboxRoleMappings:
            if capabilities.contains(.providerAPI) || capabilities.contains(.imapOAuth) || capabilities.contains(.jmapMail) {
                return support(
                    .partial,
                    "Mailbox role mappings can be configured for supported sources. Writable role assignment is capability-gated per provider."
                )
            }
            return support(
                .requiresProviderAPI,
                "Mailbox role mappings require provider-backed metadata or standards-backed source capabilities."
            )

        case .folderSubscriptionSync:
            if capabilities.contains(.multipleMailboxes) || capabilities.contains(.imapOAuth) || capabilities
                .contains(.jmapMail) {
                return support(
                    .partial,
                    "Folder subscription/sync controls are available for sources that expose subscription metadata."
                )
            }
            return support(
                .requiresStandardsExtension,
                "Folder subscription controls require source metadata support (for example IMAP/JMAP folder subscription semantics)."
            )

        case .listUnsubscribe:
            return support(
                .localOnly,
                "Unsubscribe header detection is local; any unsubscribe request still requires explicit confirmation."
            )

        case .syncHealthDiagnostics:
            if capabilities.contains(.providerSyncHealth) {
                return supported("Provider sync health is available for this account.")
            }
            return support(
                .localOnly,
                "Brev can show local sync, cache, and index health even when the provider has no health API."
            )

        case .flagColors:
            if capabilities.contains(.flagColors) {
                return supported("Flag colors round-trip with this account, including Apple Mail-compatible clients.")
            }
            return support(
                .localOnly,
                "Flag colors are stored in Brev and sync across your devices, but won't appear in the provider's webmail."
            )

        case .retentionPolicies:
            if context.policyRestrictions.contains(.retentionPolicies) {
                return policyDisabled(
                    "Retention policy controls are disabled by admin policy for this account."
                )
            }
            if context.enterpriseCapabilities.contains(.retentionPolicyManagement) {
                return supported(
                    "Provider retention policies are visible and manageable where the current user has permission. Brev's local cache retention remains separate."
                )
            }
            if context.enterpriseCapabilities.contains(.retentionPolicyVisibility) {
                return support(
                    .readOnly,
                    "Provider retention policies are visible for this account. Editing remains read-only in Brev, and local cache retention stays separate."
                )
            }
            return support(
                .requiresProviderAPI,
                "Provider retention policy visibility requires provider/admin policy metadata beyond ordinary IMAP/SMTP."
            )

        case .sensitivityLabels:
            if context.policyRestrictions.contains(.sensitivityLabels) {
                return policyDisabled(
                    "Sensitivity labels are disabled by admin policy for this account."
                )
            }
            if context.enterpriseCapabilities.contains(.sensitivityLabels) {
                return supported(
                    "Sensitivity labels are available where the provider exposes policy metadata for the current user."
                )
            }
            return support(
                .requiresProviderAPI,
                "Sensitivity labels require provider policy metadata beyond ordinary IMAP/SMTP."
            )
        }
    }

    private func supported(_ explanation: String) -> BackendFeatureSupport {
        support(.supported, explanation)
    }

    private func support(
        _ kind: BackendFeatureSupportKind,
        _ explanation: String
    ) -> BackendFeatureSupport {
        BackendFeatureSupport(feature: self, kind: kind, explanation: explanation)
    }

    private func policyDisabled(_ explanation: String) -> BackendFeatureSupport {
        support(.policyDisabled, explanation)
    }
}

public struct BackendFeatureAvailabilityContext: Sendable, Hashable {
    public let capabilities: BackendCapabilities
    public let enterpriseCapabilities: BackendExtendedCapabilities
    public let policyRestrictions: BackendPolicyRestrictions

    public init(
        capabilities: BackendCapabilities,
        enterpriseCapabilities: BackendExtendedCapabilities = [],
        policyRestrictions: BackendPolicyRestrictions = []
    ) {
        self.capabilities = capabilities
        self.enterpriseCapabilities = enterpriseCapabilities
        self.policyRestrictions = policyRestrictions
    }
}

public struct BackendFeatureSupport: Sendable, Hashable, Codable {
    public let feature: BackendFeature
    public let kind: BackendFeatureSupportKind
    public let explanation: String

    public init(
        feature: BackendFeature,
        kind: BackendFeatureSupportKind,
        explanation: String
    ) {
        self.feature = feature
        self.kind = kind
        self.explanation = explanation
    }

    public var isAvailable: Bool {
        switch kind {
        case .supported, .partial, .readOnly, .localOnly:
            true
        case .unsupported, .requiresProviderAPI, .requiresStandardsExtension, .policyDisabled, .unknown:
            false
        }
    }
}

public extension MailBackend {
    func availability(for feature: BackendFeature) -> BackendFeatureSupport {
        feature.availability(in: capabilities)
    }
}
