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

struct SignatureSection: View {
    @Environment(\.brevTheme) private var theme
    @State private var settings: SignatureSettings

    private let settingsStore: SettingsPersistenceStore
    private let accounts: [BrevAccount]

    init(
        settingsStore: SettingsPersistenceStore = .standard,
        accounts: [BrevAccount] = []
    ) {
        self.settingsStore = settingsStore
        self.accounts = accounts
        _settings = State(initialValue: settingsStore.signatureSettings())
    }

    var body: some View {
        SectionScaffold(
            title: String(localized: "Signature", bundle: .module),
            subtitle: String(
                localized: "Save multiple signatures and choose which one each account uses by default.",
                bundle: .module
            )
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.xl) {
                libraryGroup
                accountDefaultsGroup
            }
        }
    }

    private var libraryGroup: some View {
        SettingsGroup(
            title: String(localized: "Signature library", bundle: .module),
            subtitle: String(
                localized: "Add reusable signatures here, then toggle which ones are available in compose.",
                bundle: .module
            ),
            symbolName: "signature"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                if settings.signatures.isEmpty {
                    SettingsInfoCallout(
                        symbolName: "plus.circle",
                        message: String(
                            localized: "Add your first signature to make it available in the composer.",
                            bundle: .module
                        ),
                        tone: .info
                    )
                }

                ForEach(settings.signatures) { signature in
                    signatureCard(signature)
                }

                Button {
                    addSignature()
                } label: {
                    Label(String(localized: "Add Signature", bundle: .module), systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private func signatureCard(_ signature: SignatureSettings.Signature) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.md) {
            HStack(alignment: .center, spacing: BrevSpacing.md) {
                TextField(
                    String(localized: "Signature name", bundle: .module),
                    text: nameBinding(for: signature.id),
                    prompt: Text("Signature name", bundle: .module)
                )
                .textFieldStyle(.roundedBorder)
                .brevFont(.body)
                .foregroundStyle(theme.textPrimary.color)

                Toggle(String(localized: "Enabled", bundle: .module), isOn: enabledBinding(for: signature.id))
                    .toggleStyle(.switch)
                    .tint(theme.accent.color)

                Button {
                    moveSignature(signature.id, direction: .up)
                } label: {
                    Label(String(localized: "Move Signature Up", bundle: .module), systemImage: "chevron.up")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .disabled(!settings.canMoveSignature(id: signature.id, direction: .up))
                .help(String(localized: "Move signature up", bundle: .module))

                Button {
                    moveSignature(signature.id, direction: .down)
                } label: {
                    Label(String(localized: "Move Signature Down", bundle: .module), systemImage: "chevron.down")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .disabled(!settings.canMoveSignature(id: signature.id, direction: .down))
                .help(String(localized: "Move signature down", bundle: .module))

                Button(role: .destructive) {
                    removeSignature(signature.id)
                } label: {
                    Label(String(localized: "Delete Signature", bundle: .module), systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Delete signature", bundle: .module))
            }

            TextEditor(text: bodyBinding(for: signature.id))
                .brevFont(.body)
                .foregroundStyle(theme.textPrimary.color)
                .scrollContentBackground(.hidden)
                .padding(BrevSpacing.sm)
                .frame(minHeight: 120)
                .background(theme.bgSecondary.color.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: BrevRadius.md))
                .overlay {
                    RoundedRectangle(cornerRadius: BrevRadius.md)
                        .stroke(theme.border.color.opacity(0.45), lineWidth: 1)
                }

            if !signature.isEnabled {
                SettingsInfoCallout(
                    symbolName: "eye.slash",
                    message: String(
                        localized: "Disabled signatures stay saved here but do not appear in the composer.",
                        bundle: .module
                    ),
                    tone: .warning
                )
            }
        }
        .padding(BrevSpacing.md)
        .background(theme.bgSecondary.color.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: BrevRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: BrevRadius.md)
                .stroke(theme.border.color.opacity(0.45), lineWidth: 1)
        }
    }

    private var accountDefaultsGroup: some View {
        SettingsGroup(
            title: String(localized: "Default per account", bundle: .module),
            subtitle: String(localized: "Choose which signature opens by default for each mailbox.", bundle: .module),
            symbolName: "person.crop.circle.badge.checkmark"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                if accounts.isEmpty {
                    SettingsInfoCallout(
                        symbolName: "person.crop.circle.badge.questionmark",
                        message: String(localized: "Connect an account to pick per-account default signatures.", bundle: .module),
                        tone: .info
                    )
                } else {
                    ForEach(accounts) { account in
                        SettingsPickerRow(
                            symbolName: "envelope",
                            title: account.displayName,
                            subtitle: account.emailAddress,
                            selection: defaultSignatureBinding(for: account.id)
                        ) {
                            Text("No signature", bundle: .module).tag(String?.none)
                            ForEach(enabledSignatures) { signature in
                                Text(signature.name.isEmpty ? String(localized: "Signature", bundle: .module) : signature.name)
                                    .tag(Optional(signature.id))
                            }
                        }
                    }
                }
            }
        }
    }

    private var enabledSignatures: [SignatureSettings.Signature] {
        settings.signatures.filter(\.isEnabled)
    }

    private func addSignature() {
        _ = settings.addSignature(
            name: String(localized: "Signature \(settings.signatures.count + 1)", bundle: .module),
            body: "",
            isEnabled: false
        )
        settingsStore.save(settings)
    }

    private func removeSignature(_ id: String) {
        settings.removeSignature(id: id)
        settingsStore.save(settings)
    }

    private func moveSignature(
        _ id: String,
        direction: SignatureSettings.MoveDirection
    ) {
        settings.moveSignature(id: id, direction: direction)
        settingsStore.save(settings)
    }

    private func nameBinding(for signatureID: String) -> Binding<String> {
        Binding(
            get: {
                settings.signatures.first { $0.id == signatureID }?.name ?? ""
            },
            set: { newValue in
                updateSignature(signatureID: signatureID) { signature in
                    signature.name = newValue
                }
            }
        )
    }

    private func bodyBinding(for signatureID: String) -> Binding<String> {
        Binding(
            get: {
                settings.signatures.first { $0.id == signatureID }?.body ?? ""
            },
            set: { newValue in
                updateSignature(signatureID: signatureID) { signature in
                    signature.body = newValue
                    signature.isEnabled = signature.isEnabled
                        && !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            }
        )
    }

    private func enabledBinding(for signatureID: String) -> Binding<Bool> {
        Binding(
            get: {
                settings.signatures.first { $0.id == signatureID }?.isEnabled ?? false
            },
            set: { newValue in
                updateSignature(signatureID: signatureID) { signature in
                    let hasBody = !signature.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    signature.isEnabled = newValue && hasBody
                }
            }
        )
    }

    private func defaultSignatureBinding(for accountID: String) -> Binding<String?> {
        Binding(
            get: { settings.defaultSignatureID(forAccountID: accountID) },
            set: { newValue in
                settings.setDefaultSignature(signatureID: newValue, forAccountID: accountID)
                settingsStore.save(settings)
            }
        )
    }

    private func updateSignature(
        signatureID: String,
        transform: (inout SignatureSettings.Signature) -> Void
    ) {
        guard let index = settings.signatures.firstIndex(where: { $0.id == signatureID }) else {
            return
        }
        var signature = settings.signatures[index]
        transform(&signature)
        settings.updateSignature(
            id: signature.id,
            name: signature.name,
            body: signature.body,
            isEnabled: signature.isEnabled
        )
        settingsStore.save(settings)
    }
}
