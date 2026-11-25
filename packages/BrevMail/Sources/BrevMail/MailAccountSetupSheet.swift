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

import BrevDesign
import BrevThemes
import SwiftUI

/// Entry sheet for adding a mail account via standards IMAP/SMTP or native JMAP.
public struct MailAccountSetupSheet: View {
    public enum ProtocolChoice: String, CaseIterable, Identifiable, Sendable {
        case imapSMTP
        case jmap

        public var id: String { rawValue }
    }

    @Environment(\.brevTheme) private var theme
    @Bindable private var session: AppSession
    @State private var selectedProtocol: ProtocolChoice
    private let initialEmailAddress: String
    private let onClose: () -> Void

    public init(
        session: AppSession,
        initialEmailAddress: String = "",
        initialProtocol: ProtocolChoice? = nil,
        onClose: @escaping () -> Void
    ) {
        self.session = session
        self.initialEmailAddress = initialEmailAddress
        self.onClose = onClose
        let resolvedProtocol: ProtocolChoice = if let initialProtocol {
            initialProtocol
        } else if session.authFailureRequiresJMAPTokenUpdate {
            .jmap
        } else {
            .imapSMTP
        }
        _selectedProtocol = State(initialValue: resolvedProtocol)
    }

    public var body: some View {
        let isReauth = !initialEmailAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if session.authFailureRequiresJMAPTokenUpdate {
            JMAPAccountSetupView(
                session: session,
                initialEmailAddress: initialEmailAddress,
                onClose: onClose
            )
        } else if session.canUseJMAPAccountSetup, !isReauth {
            VStack(spacing: 0) {
                protocolSwitcher
                Group {
                    switch selectedProtocol {
                    case .imapSMTP:
                        IMAPAccountSetupSheet(
                            session: session,
                            initialEmailAddress: initialEmailAddress,
                            onClose: onClose
                        )
                    case .jmap:
                        JMAPAccountSetupView(
                            session: session,
                            initialEmailAddress: initialEmailAddress,
                            onClose: onClose
                        )
                    }
                }
            }
            .background(theme.bgPrimary.color)
        } else {
            IMAPAccountSetupSheet(
                session: session,
                initialEmailAddress: initialEmailAddress,
                onClose: onClose
            )
        }
    }

    private var protocolSwitcher: some View {
        HStack {
            Picker(
                String(localized: "Mail protocol", bundle: .module),
                selection: $selectedProtocol
            ) {
                Text("IMAP / SMTP", bundle: .module).tag(ProtocolChoice.imapSMTP)
                Text("JMAP", bundle: .module).tag(ProtocolChoice.jmap)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 280)
        }
        .padding(.horizontal, BrevSpacing.lg)
        .padding(.top, BrevSpacing.md)
        .padding(.bottom, BrevSpacing.xs)
        .frame(maxWidth: .infinity)
        .background(theme.bgPrimary.color)
    }
}
