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

import Foundation

public enum OutboundMessageSecurityMode: Sendable, Hashable, Codable {
    case none
    case sign
    case encrypt
    case signAndEncrypt

    /// Maps a pair of compose toggles to a security mode.
    public init(signing: Bool, encrypting: Bool) {
        switch (signing, encrypting) {
        case (false, false): self = .none
        case (true, false): self = .sign
        case (false, true): self = .encrypt
        case (true, true): self = .signAndEncrypt
        }
    }

    public var requiresSigning: Bool {
        switch self {
        case .sign, .signAndEncrypt:
            true
        case .none, .encrypt:
            false
        }
    }

    public var requiresEncryption: Bool {
        switch self {
        case .encrypt, .signAndEncrypt:
            true
        case .none, .sign:
            false
        }
    }
}

public struct OutboundMessageSecurityRequest: Sendable, Hashable, Codable {
    public let senderEmail: String
    public let to: [String]
    public let cc: [String]
    public let bcc: [String]
    public let mode: OutboundMessageSecurityMode

    public init(
        senderEmail: String,
        to: [String],
        cc: [String] = [],
        bcc: [String] = [],
        mode: OutboundMessageSecurityMode
    ) {
        self.senderEmail = senderEmail
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.mode = mode
    }
}

public struct OutboundSecurityAvailability: Sendable, Hashable, Codable {
    public let hasTrustedSigningIdentity: Bool
    public let trustedEncryptionRecipients: Set<String>

    public init(
        hasTrustedSigningIdentity: Bool,
        trustedEncryptionRecipients: Set<String>
    ) {
        self.hasTrustedSigningIdentity = hasTrustedSigningIdentity
        self.trustedEncryptionRecipients = Set(
            trustedEncryptionRecipients.map(OutboundAddressNormalizer.emailAddress)
        )
    }
}

public struct OutboundMessageSecurityPlan: Sendable, Hashable, Codable {
    public let requiresSigning: Bool
    public let requiresEncryption: Bool
    public let encryptionRecipients: [String]

    public init(
        requiresSigning: Bool,
        requiresEncryption: Bool,
        encryptionRecipients: [String]
    ) {
        self.requiresSigning = requiresSigning
        self.requiresEncryption = requiresEncryption
        self.encryptionRecipients = encryptionRecipients
    }
}

public enum OutboundMessageSecurityError: Error, Sendable, Hashable {
    case missingSigningIdentity(senderEmail: String)
    case missingEncryptionRecipients([String])
}

extension OutboundMessageSecurityError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingSigningIdentity(let senderEmail):
            String(localized: "No trusted signing identity is available for \(senderEmail).", bundle: .module)
        case .missingEncryptionRecipients(let recipients):
            String(
                localized: "No trusted encryption material is available for \(recipients.joined(separator: ", ")).",
                bundle: .module
            )
        }
    }
}

public enum OutboundMessageSecurityPolicy {
    public static func prepare(
        request: OutboundMessageSecurityRequest,
        availability: OutboundSecurityAvailability
    ) throws -> OutboundMessageSecurityPlan {
        let senderEmail = OutboundAddressNormalizer.emailAddress(request.senderEmail)
        if request.mode.requiresSigning, !availability.hasTrustedSigningIdentity {
            throw OutboundMessageSecurityError.missingSigningIdentity(senderEmail: senderEmail)
        }

        let encryptionRecipients = orderedEncryptionRecipients(for: request)
        if request.mode.requiresEncryption {
            let missingRecipients = encryptionRecipients.filter {
                !availability.trustedEncryptionRecipients.contains($0)
            }
            if !missingRecipients.isEmpty {
                throw OutboundMessageSecurityError.missingEncryptionRecipients(missingRecipients)
            }
        }

        return OutboundMessageSecurityPlan(
            requiresSigning: request.mode.requiresSigning,
            requiresEncryption: request.mode.requiresEncryption,
            encryptionRecipients: request.mode.requiresEncryption ? encryptionRecipients : []
        )
    }

    private static func orderedEncryptionRecipients(
        for request: OutboundMessageSecurityRequest
    ) -> [String] {
        var seen = Set<String>()
        return ([request.senderEmail] + request.to + request.cc + request.bcc)
            .map(OutboundAddressNormalizer.emailAddress)
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }
}

private enum OutboundAddressNormalizer {
    static func emailAddress(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let address: String
        if let start = trimmed.lastIndex(of: "<"),
           let end = trimmed[start...].firstIndex(of: ">") {
            address = String(trimmed[trimmed.index(after: start) ..< end])
        } else {
            address = trimmed
        }
        return address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
