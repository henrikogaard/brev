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

/// The same disclosure sits above the body in the single reader and expanded conversation cards.
struct SenderWarningBanner: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.senderWarningHistory) private var history
    let header: MessageHeader
    let authenticationResults: String?

    var body: some View {
        if let warning = MessageHeaderAnalyzer.warning(
            for: header, authenticationResults: authenticationResults,
            writtenAddresses: history?.written ?? [], knownDomains: history?.knownDomains ?? []
        ), history != nil || MessageHeaderAnalyzer.hasDMARCFail(in: authenticationResults) {
            VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                Label {
                    Text(verbatim: title(for: warning))
                        .foregroundStyle(theme.textPrimary.color)
                } icon: {
                    Image(systemName: "exclamationmark.shield")
                        .foregroundStyle(theme.warning.color)
                }
                .brevFont(.headline)
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                        Text(verbatim: explanation(for: warning))
                        Text(verbatim: String(localized: "Sender address: \(header.from.email)", bundle: .module))
                    }
                    .foregroundStyle(theme.textSecondary.color)
                    .textSelection(.enabled)
                } label: {
                    Text("Show sender details", bundle: .module)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(BrevSpacing.md)
            .brevQuietSurface(cornerRadius: BrevRadius.sm)
            .id(header.id)
        }
    }

    private func title(for warning: SenderAuthWarning) -> String {
        switch warning {
        case .dmarcFail, .dmarcFailAndDisplayNameMismatch:
            return String(localized: "The sender’s domain could not be verified", bundle: .module)
        case .displayNameMismatch:
            return String(localized: "The name and sender domain don’t match", bundle: .module)
        case .lookAlikeDomain(let expected):
            let actual = String(header.from.email.split(separator: "@").last ?? "")
            return String(localized: "This message came from \(actual), which may be impersonating \(expected).", bundle: .module)
        }
    }

    private func explanation(for warning: SenderAuthWarning) -> String {
        switch warning {
        case .dmarcFail, .dmarcFailAndDisplayNameMismatch:
            String(
                localized: "The authentication header reports a DMARC failure. Check the address before replying.",
                bundle: .module
            )
        case .displayNameMismatch:
            String(localized: "The display name mentions a different domain from the sender’s address.", bundle: .module)
        case .lookAlikeDomain:
            String(
                localized: "The name or domain resembles a familiar sender. Check the spelling before replying.",
                bundle: .module
            )
        }
    }
}
