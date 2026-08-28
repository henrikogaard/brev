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
import Foundation
import SwiftUI

struct SecuritySection: View {
    @Environment(\.brevTheme) private var theme
    @State private var encryptionSettings: EncryptionSettings
    @State private var keyMaterialSettings: SecurityKeyMaterialSettings
    @State private var draftRecord = DraftRecord.defaults
    @State private var draftMaterialPayload = ""
    @State private var pendingConfirmation: PendingConfirmation?
    @State private var typedConfirmationInput = ""
    @State private var materialOperationMessage: String?
    @State private var exportPreview: ExportPreview?

    private let settingsStore: SettingsPersistenceStore
    private let materialStore: any SecurityKeyMaterialStore

    init(
        settingsStore: SettingsPersistenceStore = .standard,
        materialStore: any SecurityKeyMaterialStore = SecurityKeychainMaterialStore()
    ) {
        self.settingsStore = settingsStore
        self.materialStore = materialStore
        _encryptionSettings = State(initialValue: settingsStore.encryptionSettings())
        _keyMaterialSettings = State(initialValue: settingsStore.securityKeyMaterialSettings())
    }

    var body: some View {
        SectionScaffold(
            title: String(localized: "Security", bundle: .module),
            subtitle: String(
                localized: "Manage local signing and encryption defaults plus key/certificate material.",
                bundle: .module
            )
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.xl) {
                #if os(macOS)
                defaultsGroup
                keyCatalogGroup
                importExportGroup
                #else
                unavailableOnIOSGroup
                #endif
            }
        }
        .alert(item: $pendingConfirmation) { pending in
            Alert(
                title: Text(pending.confirmation.title),
                message: Text(confirmationMessage(for: pending.confirmation)),
                primaryButton: .destructive(Text(pending.confirmation.confirmButtonTitle)) {
                    applyConfirmationIfSatisfied(pending)
                },
                secondaryButton: .cancel {
                    typedConfirmationInput = ""
                }
            )
        }
        .sheet(item: $exportPreview) { preview in
            exportPreviewSheet(preview)
        }
    }

    #if os(iOS)
    private var unavailableOnIOSGroup: some View {
        SettingsGroup(
            title: String(localized: "Message security", bundle: .module),
            subtitle: String(localized: "Platform availability", bundle: .module),
            symbolName: "lock.shield"
        ) {
            SettingsInfoCallout(
                symbolName: "iphone.slash",
                message: String(
                    localized: "Signing and encryption are unavailable on iOS in this release. Brev blocks a secured send when no supported engine is available; it never silently sends plaintext instead.",
                    bundle: .module
                ),
                tone: .info
            )
        }
    }
    #endif

    private var defaultsGroup: some View {
        SettingsGroup(
            title: String(localized: "Compose defaults", bundle: .module),
            subtitle: String(localized: "Apply security defaults when trusted local material is available.", bundle: .module),
            symbolName: "lock.shield"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                SettingsToggleRow(
                    symbolName: "checkmark.shield",
                    title: String(localized: "Enable S/MIME", bundle: .module),
                    subtitle: String(
                        localized: "Allow S/MIME signing and encryption when local certificates exist.",
                        bundle: .module
                    ),
                    isOn: binding(for: \.smimeEnabled)
                )

                SettingsToggleRow(
                    symbolName: "signature",
                    title: String(localized: "Prefer signing", bundle: .module),
                    subtitle: String(
                        localized: "Preselect signed sends when trusted signing identities are available.",
                        bundle: .module
                    ),
                    isOn: binding(for: \.preferSign),
                    isEnabled: encryptionSettings.smimeEnabled
                )

                SettingsToggleRow(
                    symbolName: "lock",
                    title: String(localized: "Prefer encryption", bundle: .module),
                    subtitle: String(
                        localized: "Preselect encrypted sends when trusted recipient identities are available.",
                        bundle: .module
                    ),
                    isOn: binding(for: \.preferEncrypt),
                    isEnabled: encryptionSettings.smimeEnabled
                )

                SettingsInfoCallout(
                    symbolName: "person.2.badge.key",
                    message: String(
                        localized: "Trusted identities: \(keyMaterialSettings.trustedSigningRecordCount) signing, \(keyMaterialSettings.trustedEncryptionRecordCount) encryption.",
                        bundle: .module
                    ),
                    tone: .info
                )
            }
        }
    }

    private var keyCatalogGroup: some View {
        SettingsGroup(
            title: String(localized: "Local key material", bundle: .module),
            subtitle: String(
                localized: "Inspect, add metadata records, and remove local key/certificate catalog entries.",
                bundle: .module
            ),
            symbolName: "key.viewfinder"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                draftEditor

                BrevDivider()

                if keyMaterialSettings.records.isEmpty {
                    SettingsInfoCallout(
                        symbolName: "key.slash",
                        message: String(localized: "No local key material records yet.", bundle: .module),
                        tone: .warning
                    )
                } else {
                    ForEach(sortedRecords) { record in
                        recordRow(record)
                    }
                }

                HStack(spacing: BrevSpacing.sm) {
                    BrevButton("Remove All S/MIME", style: .destructive) {
                        requestBulkDelete(.removeAllSMIME)
                    }
                    .disabled(!keyMaterialSettings.records.contains(where: { $0.family == .smime }))

                    BrevButton(String(localized: "Remove Everything", bundle: .module), style: .destructive) {
                        requestBulkDelete(.removeAllMaterial)
                    }
                    .disabled(keyMaterialSettings.records.isEmpty)
                }

                if let materialOperationMessage {
                    SettingsInfoCallout(
                        symbolName: "key",
                        message: materialOperationMessage,
                        tone: .info
                    )
                }
            }
        }
    }

    private var importExportGroup: some View {
        SettingsGroup(
            title: String(localized: "Import and export preferences", bundle: .module),
            subtitle: String(localized: "Control preferred export formats and replacement behavior.", bundle: .module),
            symbolName: "square.and.arrow.up.on.square"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                SettingsPickerRow(
                    symbolName: "doc.badge.gearshape",
                    title: String(localized: "S/MIME export format", bundle: .module),
                    subtitle: String(localized: "Pick certificate archive format for export actions.", bundle: .module),
                    selection: importExportBinding(for: \.smimeExportFormat)
                ) {
                    ForEach(SecuritySMIMEExportFormat.allCases, id: \.self) { format in
                        Text(smimeLabel(for: format)).tag(format)
                    }
                }

                SettingsToggleRow(
                    symbolName: "lock.open",
                    title: String(localized: "Allow private material in exports", bundle: .module),
                    subtitle: String(
                        localized: "When enabled, exports may include private key material. Use only on secure devices.",
                        bundle: .module
                    ),
                    isOn: importExportBinding(for: \.includePrivateMaterialInExport)
                )

                SettingsToggleRow(
                    symbolName: "arrow.triangle.2.circlepath",
                    title: String(localized: "Replace existing records on import", bundle: .module),
                    subtitle: String(
                        localized: "Allow importing over existing fingerprints instead of skipping duplicates.",
                        bundle: .module
                    ),
                    isOn: importExportBinding(for: \.allowReplacingExistingMaterialOnImport)
                )
            }
        }
    }

    private var draftEditor: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            Text("Add material record", bundle: .module)
                .brevFont(.headline)
                .foregroundStyle(theme.textPrimary.color)

            HStack(spacing: BrevSpacing.sm) {
                Label("S/MIME", systemImage: "checkmark.shield")
                    .brevFont(.subheadline)
                    .foregroundStyle(theme.textSecondary.color)
                    .frame(maxWidth: 150, alignment: .leading)

                Picker(String(localized: "Trust", bundle: .module), selection: $draftRecord.trust) {
                    ForEach(SecurityKeyMaterialTrustState.allCases, id: \.self) { trust in
                        Text(trustLabel(for: trust)).tag(trust)
                    }
                }
                .frame(maxWidth: 170)
            }

            HStack(spacing: BrevSpacing.sm) {
                TextField(String(localized: "Label", bundle: .module), text: $draftRecord.label)
                TextField(String(localized: "Email (optional)", bundle: .module), text: $draftRecord.emailAddress)
            }

            HStack(spacing: BrevSpacing.sm) {
                TextField(String(localized: "Fingerprint", bundle: .module), text: $draftRecord.fingerprint)
                TextField(String(localized: "Algorithm", bundle: .module), text: $draftRecord.algorithm)
            }

            HStack(spacing: BrevSpacing.md) {
                Toggle(String(localized: "Can sign", bundle: .module), isOn: $draftRecord.canSign)
                Toggle(String(localized: "Can encrypt", bundle: .module), isOn: $draftRecord.canEncrypt)
                Toggle(String(localized: "Private material", bundle: .module), isOn: $draftRecord.hasPrivateMaterial)
            }
            .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                Text("Certificate payload (PEM, DER, or base64 PKCS#12)", bundle: .module)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                TextEditor(text: $draftMaterialPayload)
                    .frame(minHeight: 100)
                    .padding(BrevSpacing.xs)
                    .background(theme.bgSecondary.color)
                    .clipShape(RoundedRectangle(cornerRadius: BrevRadius.sm))
            }

            BrevButton(String(localized: "Add Record", bundle: .module), style: .secondary) {
                addDraftRecord()
            }
            .disabled(!draftRecord.isValid)
        }
    }

    private func recordRow(_ record: SecurityKeyMaterialSettings.Record) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            HStack(spacing: BrevSpacing.sm) {
                Text(record.label)
                    .brevFont(.subheadline)
                    .foregroundStyle(theme.textPrimary.color)
                Text("S/MIME", bundle: .module)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                Text(trustLabel(for: record.trust))
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)

                Spacer(minLength: BrevSpacing.sm)

                BrevButton(String(localized: "Export", bundle: .module), style: .secondary) {
                    exportMaterial(record: record)
                }

                BrevButton(String(localized: "Remove", bundle: .module), style: .destructive) {
                    requestRemoveRecord(record)
                }
            }

            Text(record.fingerprint)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
                .textSelection(.enabled)

            if let emailAddress = record.emailAddress, !emailAddress.isEmpty {
                Text(emailAddress)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
            }
        }
        .padding(BrevSpacing.sm)
        .background(theme.bgSecondary.color.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: BrevRadius.sm))
    }

    private var sortedRecords: [SecurityKeyMaterialSettings.Record] {
        keyMaterialSettings.records.sorted {
            if $0.importedAt != $1.importedAt {
                return $0.importedAt > $1.importedAt
            }
            return $0.id < $1.id
        }
    }

    private func binding(
        for keyPath: WritableKeyPath<EncryptionSettings, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { encryptionSettings[keyPath: keyPath] },
            set: { newValue in
                encryptionSettings[keyPath: keyPath] = newValue
                settingsStore.save(encryptionSettings)
            }
        )
    }

    private func importExportBinding<Value>(
        for keyPath: WritableKeyPath<SecurityKeyMaterialSettings.ImportExportPreferences, Value>
    ) -> Binding<Value> {
        Binding(
            get: { keyMaterialSettings.importExport[keyPath: keyPath] },
            set: { newValue in
                keyMaterialSettings.importExport[keyPath: keyPath] = newValue
                settingsStore.save(keyMaterialSettings)
            }
        )
    }

    private func addDraftRecord() {
        guard draftRecord.isValid else { return }
        let record = draftRecord.asRecord()
        keyMaterialSettings.upsert(record)
        settingsStore.save(keyMaterialSettings)
        draftRecord = .defaults
        let payload = draftMaterialPayload.trimmingCharacters(in: .whitespacesAndNewlines)
        draftMaterialPayload = ""
        materialOperationMessage = nil
        guard !payload.isEmpty else { return }
        Task {
            do {
                let materialData = try SecurityKeyMaterialPayloadDecoder.materialData(
                    from: payload,
                    family: record.family
                )
                try await materialStore.setMaterial(materialData, for: record.id)
                await MainActor.run {
                    materialOperationMessage = String(
                        localized: "Stored local key material in Keychain for \(record.label).",
                        bundle: .module
                    )
                }
            } catch {
                await MainActor.run {
                    materialOperationMessage = String(
                        localized: "Saved record metadata, but key material storage failed.",
                        bundle: .module
                    )
                }
            }
        }
    }

    private func requestRemoveRecord(_ record: SecurityKeyMaterialSettings.Record) {
        let confirmation = SecurityKeyMaterialConfirmationPolicy.confirmation(
            for: .removeSelectedItem,
            subjectLabel: record.label
        )
        pendingConfirmation = PendingConfirmation(
            action: .removeSelectedItem,
            recordID: record.id,
            confirmation: confirmation
        )
        typedConfirmationInput = ""
    }

    private func requestBulkDelete(_ action: SecurityKeyMaterialDestructiveAction) {
        let confirmation = SecurityKeyMaterialConfirmationPolicy.confirmation(for: action)
        pendingConfirmation = PendingConfirmation(
            action: action,
            recordID: nil,
            confirmation: confirmation
        )
        typedConfirmationInput = ""
    }

    private func applyConfirmationIfSatisfied(_ pending: PendingConfirmation) {
        let confirmationInput = typedConfirmationInput.isEmpty
            ? pending.confirmation.typedPhrase
            : typedConfirmationInput
        guard pending.confirmation.isSatisfied(by: confirmationInput) else { return }

        switch pending.action {
        case .removeSelectedItem:
            if let recordID = pending.recordID {
                _ = keyMaterialSettings.removeRecord(id: recordID)
                Task { try? await materialStore.deleteMaterial(for: recordID) }
            }
        case .removeAllSMIME:
            let ids = keyMaterialSettings.records
                .filter { $0.family == .smime }
                .map(\.id)
            _ = keyMaterialSettings.removeAllRecords(in: .smime)
            Task {
                for id in ids {
                    try? await materialStore.deleteMaterial(for: id)
                }
            }
        case .removeAllMaterial:
            let ids = keyMaterialSettings.records.map(\.id)
            _ = keyMaterialSettings.removeAllRecords()
            Task {
                for id in ids {
                    try? await materialStore.deleteMaterial(for: id)
                }
            }
        }

        settingsStore.save(keyMaterialSettings)
        typedConfirmationInput = ""
    }

    private func confirmationMessage(for confirmation: SecurityKeyMaterialConfirmation) -> String {
        confirmation.message
    }

    private func exportMaterial(record: SecurityKeyMaterialSettings.Record) {
        Task {
            do {
                guard let data = try await materialStore.material(for: record.id) else {
                    await MainActor.run {
                        materialOperationMessage = String(
                            localized: "No local payload stored for \(record.label).",
                            bundle: .module
                        )
                    }
                    return
                }
                guard let payload = String(data: data, encoding: .utf8) else {
                    await MainActor.run {
                        materialOperationMessage = String(
                            localized: "Stored payload for \(record.label) is not UTF-8 text.",
                            bundle: .module
                        )
                    }
                    return
                }
                await MainActor.run {
                    exportPreview = ExportPreview(
                        title: record.label,
                        payload: payload
                    )
                }
            } catch {
                await MainActor.run {
                    materialOperationMessage = String(
                        localized: "Couldn't export key material for \(record.label).",
                        bundle: .module
                    )
                }
            }
        }
    }

    private func exportPreviewSheet(_ preview: ExportPreview) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                Text(preview.title)
                    .brevFont(.headline)
                    .foregroundStyle(theme.textPrimary.color)
                TextEditor(text: .constant(preview.payload))
                    .frame(minHeight: 220)
                    .padding(BrevSpacing.xs)
                    .background(theme.bgSecondary.color)
                    .clipShape(RoundedRectangle(cornerRadius: BrevRadius.sm))
            }
            .padding(BrevSpacing.lg)
            .navigationTitle(String(localized: "Export Material", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    BrevButton(String(localized: "Done", bundle: .module), style: .primary) {
                        exportPreview = nil
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 360)
    }

    private func trustLabel(for trust: SecurityKeyMaterialTrustState) -> String {
        switch trust {
        case .trusted: return String(localized: "Trusted", bundle: .module)
        case .untrusted: return String(localized: "Untrusted", bundle: .module)
        case .revoked: return String(localized: "Revoked", bundle: .module)
        case .expired: return String(localized: "Expired", bundle: .module)
        }
    }

    private func smimeLabel(for format: SecuritySMIMEExportFormat) -> String {
        switch format {
        case .pem: return String(localized: "PEM", bundle: .module)
        case .der: return String(localized: "DER", bundle: .module)
        case .pkcs12: return String(localized: "PKCS#12", bundle: .module)
        }
    }
}

private struct ExportPreview: Identifiable {
    let title: String
    let payload: String

    var id: String { title + ":\(payload.count)" }
}

private struct PendingConfirmation: Identifiable {
    let action: SecurityKeyMaterialDestructiveAction
    let recordID: String?
    let confirmation: SecurityKeyMaterialConfirmation

    var id: String {
        "\(action.rawValue):\(recordID ?? "all")"
    }
}

private struct DraftRecord {
    var label: String
    var emailAddress: String
    var fingerprint: String
    var algorithm: String
    var canSign: Bool
    var canEncrypt: Bool
    var hasPrivateMaterial: Bool
    var trust: SecurityKeyMaterialTrustState

    static let defaults = DraftRecord(
        label: "",
        emailAddress: "",
        fingerprint: "",
        algorithm: "RSA",
        canSign: true,
        canEncrypt: true,
        hasPrivateMaterial: false,
        trust: .trusted
    )

    var isValid: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !fingerprint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !algorithm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func asRecord() -> SecurityKeyMaterialSettings.Record {
        SecurityKeyMaterialSettings.Record(
            id: UUID().uuidString,
            family: .smime,
            label: label.trimmingCharacters(in: .whitespacesAndNewlines),
            emailAddress: normalizedEmailAddress,
            fingerprint: fingerprint.trimmingCharacters(in: .whitespacesAndNewlines),
            algorithm: algorithm.trimmingCharacters(in: .whitespacesAndNewlines),
            canSign: canSign,
            canEncrypt: canEncrypt,
            hasPrivateMaterial: hasPrivateMaterial,
            trust: trust,
            importedAt: Date()
        )
    }

    private var normalizedEmailAddress: String? {
        let trimmed = emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
