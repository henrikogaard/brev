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

public struct ComposeSignatureOption: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let body: String

    public init(id: String, title: String, body: String) {
        self.id = id
        self.title = title
        self.body = body
    }
}

public struct ComposeSignatureContext: Equatable, Sendable {
    public let selectedSignatureID: String?
    public let options: [ComposeSignatureOption]

    public init(
        selectedSignatureID: String?,
        options: [ComposeSignatureOption]
    ) {
        self.selectedSignatureID = selectedSignatureID
        self.options = options
    }

    var selectedSignature: ComposeSignatureOption? {
        guard let selectedSignatureID else { return nil }
        return options.first(where: { $0.id == selectedSignatureID })
    }
}

/// Resolves provider signatures for the active From identity while retaining
/// local compose signatures as a fallback when no matching server signature
/// exists.
public enum ComposeServerSignaturePolicy {
    /// Builds a context for one sender identity. Server records for another
    /// alias are intentionally excluded from the picker.
    public static func context(
        from signatures: [ServerSignature],
        selectedAliasID: String?,
        senderEmail: String
    ) -> ComposeSignatureContext? {
        let identity = (selectedAliasID ?? senderEmail).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identity.isEmpty else { return nil }
        let options = signatures.filter {
            $0.id.caseInsensitiveCompare(identity) == .orderedSame
        }.map {
            ComposeSignatureOption(id: $0.id, title: $0.name, body: $0.body)
        }
        guard !options.isEmpty else { return nil }
        let selected = signatures.first {
            $0.id.caseInsensitiveCompare(identity) == .orderedSame && $0.isDefault
        } ?? signatures.first { $0.id.caseInsensitiveCompare(identity) == .orderedSame }
        return ComposeSignatureContext(
            selectedSignatureID: selected?.id,
            options: options
        )
    }

    /// Resolves a signature reload without allowing a stale identity's server
    /// context to survive a missing or failed server response.
    public static func contextForReload(
        serverSignatures: [ServerSignature]?,
        selectedAliasID: String?,
        senderEmail: String,
        localContext: ComposeSignatureContext?
    ) -> ComposeSignatureContext? {
        guard let serverSignatures else { return localContext }
        return context(
            from: serverSignatures,
            selectedAliasID: selectedAliasID,
            senderEmail: senderEmail
        ) ?? localContext
    }
}
