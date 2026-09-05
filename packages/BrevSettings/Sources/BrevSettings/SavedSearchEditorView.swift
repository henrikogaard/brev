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

/// Shared compact condition editor used from Mail and Settings.
public struct SavedSearchEditorView: View {
    @Environment(\.brevTheme) private var theme
    @State private var presentation: SavedSearchEditorPresentation
    private let editingID: SmartMailbox.ID?
    private let mailboxes: [SettingsMailbox]
    private let settingsStore: SettingsPersistenceStore
    private let onFinished: () -> Void

    /// Opens a new or existing saved view using cached mailbox choices.
    public init(editing: SmartMailbox? = nil, mailboxes: [SettingsMailbox] = [],
                settingsStore: SettingsPersistenceStore = .standard, onFinished: @escaping () -> Void) {
        _presentation = State(initialValue: editing.map(SavedSearchEditorPresentation.init)
            ?? SavedSearchEditorPresentation(kind: .messageSearch))
        editingID = editing?.id
        self.mailboxes = mailboxes
        self.settingsStore = settingsStore
        self.onFinished = onFinished
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.lg) {
            Text(editingID == nil ? String(localized: "New Smart View", bundle: .module)
                : String(localized: "Edit Smart View", bundle: .module))
                .brevFont(.title)
            HStack(spacing: BrevSpacing.md) {
                Text("Name", bundle: .module)
                TextField(String(localized: "Smart View name", bundle: .module), text: $presentation.name)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Picker(String(localized: "Show", bundle: .module), selection: $presentation.kind) {
                    Text("Messages", bundle: .module).tag(SmartMailboxKind.messageSearch)
                    Text("Attachments", bundle: .module).tag(SmartMailboxKind.attachmentSearch)
                }
                .frame(maxWidth: 230)
                Spacer()
                Toggle(String(localized: "Show in sidebar", bundle: .module), isOn: $presentation.isEnabled)
            }
            if presentation.kind == .messageSearch {
                messageConditions
            } else {
                attachmentConditions
            }
            footer
        }
        .brevFont(.body)
        .foregroundStyle(theme.textPrimary.color)
        .padding(BrevSpacing.xl)
        .background(theme.bgPrimary.color)
        .tint(theme.accent.color)
        #if os(macOS)
            .frame(width: 720, height: presentation.kind == .messageSearch
                ? min(640, 345 + CGFloat(max(1, presentation.conditions.count)) * 36) : 340)
        #endif
    }

    private var messageConditions: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            HStack {
                Text("Match", bundle: .module)
                Picker(String(localized: "Match conditions", bundle: .module), selection: $presentation.matchMode) {
                    Text("all", bundle: .module).tag(SmartViewMatchMode.all)
                    Text("any", bundle: .module).tag(SmartViewMatchMode.any)
                }
                .labelsHidden()
                .frame(width: 85)
                Text("of these conditions", bundle: .module)
                Spacer()
            }
            ScrollView {
                VStack(spacing: BrevSpacing.sm) {
                    ForEach($presentation.conditions) { $condition in
                        SmartViewConditionRow(condition: $condition, mailboxes: mailboxes) {
                            presentation.conditions.removeAll { $0.id == condition.id }
                        }
                    }
                    Button {
                        presentation.conditions.append(.init())
                    } label: {
                        Label(String(localized: "Add condition", bundle: .module), systemImage: "plus")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(BrevSpacing.md)
            }
            .background(theme.bgSecondary.color, in: RoundedRectangle(cornerRadius: 8))
            Toggle(String(localized: "Include messages in Trash", bundle: .module), isOn: $presentation.includeTrash)
            Toggle(String(localized: "Include messages in Sent", bundle: .module), isOn: $presentation.includeSent)
            Text(
                "Searches cached mail in the current profile. Message preview searches subject, people and preview text.",
                bundle: .module
            )
            .brevFont(.footnote)
            .foregroundStyle(theme.textSecondary.color)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var attachmentConditions: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.md) {
            TextField(
                String(localized: "Search attachment names and message metadata", bundle: .module),
                text: $presentation.queryText
            )
            TextField(String(localized: "From", bundle: .module), text: $presentation.fromText)
            Text("Uses cached attachment metadata. Attachment contents are not searched.", bundle: .module)
                .brevFont(.footnote)
                .foregroundStyle(theme.textSecondary.color)
        }
        .textFieldStyle(.roundedBorder)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var footer: some View {
        HStack {
            if editingID != nil {
                Button(String(localized: "Delete", bundle: .module), role: .destructive) { delete() }
            }
            Spacer()
            Button(String(localized: "Cancel", bundle: .module), action: onFinished)
                .keyboardShortcut(.cancelAction)
            Button(String(localized: "Save", bundle: .module)) { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(!presentation.isValid)
        }
    }

    private func save() {
        var settings = SmartMailboxSettings.load(from: settingsStore.defaults)
        let mailbox = presentation.makeSmartMailbox()
        if editingID == nil { settings.add(mailbox) } else { settings.update(mailbox) }
        settings.save(to: settingsStore.defaults)
        onFinished()
    }

    private func delete() {
        guard let editingID else { return }
        var settings = SmartMailboxSettings.load(from: settingsStore.defaults)
        settings.remove(id: editingID)
        settings.save(to: settingsStore.defaults)
        onFinished()
    }
}

private struct SmartViewConditionRow: View {
    @Binding var condition: SmartViewCondition
    let mailboxes: [SettingsMailbox]
    let onRemove: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: BrevSpacing.xs) {
                fieldPicker.frame(width: 155)
                comparisonPicker.frame(width: 145)
                valueControl.frame(minWidth: 130, maxWidth: .infinity)
                removeButton
            }
            VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                HStack { fieldPicker; removeButton }
                HStack { comparisonPicker; valueControl }
            }
        }
        .onChange(of: condition.field) { _, field in
            condition.comparison = field.comparisons[0]
            condition.value = field == .received ? "7" : ""
            condition.sourceID = nil
        }
    }

    private var fieldPicker: some View {
        Picker(String(localized: "Condition field", bundle: .module), selection: $condition.field) {
            ForEach(SmartViewCondition.Field.allCases, id: \.self) { field in
                Text(field.title).tag(field)
            }
        }.labelsHidden()
    }

    private var comparisonPicker: some View {
        Picker(String(localized: "Comparison", bundle: .module), selection: $condition.comparison) {
            ForEach(condition.field.comparisons, id: \.self) { comparison in
                Text(comparison.title).tag(comparison)
            }
        }.labelsHidden()
    }

    @ViewBuilder
    private var valueControl: some View {
        switch condition.field {
        case .isRead, .isFlagged, .isAnswered, .hasAttachments:
            Spacer(minLength: 0)
        case .received:
            if condition.comparison == .inLastDays {
                HStack {
                    TextField(String(localized: "Number of days", bundle: .module), text: $condition.value)
                        .textFieldStyle(.roundedBorder)
                    Text("days", bundle: .module)
                }
            } else {
                DatePicker(String(localized: "Date", bundle: .module), selection: $condition.date, displayedComponents: .date)
                    .labelsHidden()
            }
        case .mailbox:
            Picker(String(localized: "Mailbox", bundle: .module), selection: $condition.sourceID) {
                Text("Choose mailbox", bundle: .module).tag(MailSourceID?.none)
                if let source = condition.sourceID, !mailboxes.contains(where: { $0.id == source }) {
                    Text("Unavailable mailbox", bundle: .module).tag(Optional(source))
                }
                ForEach(mailboxes) { mailbox in
                    Text(verbatim: mailbox.mailbox.displayName + " · " + mailbox.mailbox.email).tag(Optional(mailbox.id))
                }
            }.labelsHidden()
        case .folder:
            Picker(String(localized: "Folder", bundle: .module), selection: folderSelection) {
                Text("Choose folder", bundle: .module).tag("")
                if !condition.value.isEmpty {
                    Text(verbatim: currentFolderTitle).tag(folderKey(source: condition.sourceID, folder: condition.value))
                }
                ForEach(mailboxes) { mailbox in
                    ForEach(mailbox.folders) { folder in
                        if mailbox.id != condition.sourceID || folder.id != condition.value {
                            Text(verbatim: mailbox.mailbox.displayName + " / " + folder.name)
                                .tag(folderKey(source: mailbox.id, folder: folder.id))
                        }
                    }
                }
            }.labelsHidden()
        default:
            TextField(String(localized: "Value", bundle: .module), text: $condition.value)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var currentFolderTitle: String {
        if let mailbox = mailboxes.first(where: { $0.id == condition.sourceID }),
           let folder = mailbox.folders.first(where: { $0.id == condition.value }) {
            return mailbox.mailbox.displayName + " / " + folder.name
        }
        return condition.value
    }

    private func folderKey(source: MailSourceID?, folder: String) -> String {
        // Encode components so provider IDs containing punctuation cannot collide.
        let parts = [source?.accountID ?? "", source?.mailboxID ?? "", folder]
        return (try? JSONEncoder().encode(parts).base64EncodedString()) ?? ""
    }

    private var folderSelection: Binding<String> {
        Binding(get: {
            condition.value.isEmpty ? "" : folderKey(source: condition.sourceID, folder: condition.value)
        }, set: { key in
            guard let data = Data(base64Encoded: key),
                  let parts = try? JSONDecoder().decode([String].self, from: data), parts.count == 3 else {
                condition.value = ""
                condition.sourceID = nil
                return
            }
            condition.sourceID = parts[0].isEmpty ? nil : MailSourceID(accountID: parts[0], mailboxID: parts[1])
            condition.value = parts[2]
        })
    }

    private var removeButton: some View {
        Button(action: onRemove) {
            Image(systemName: "minus.circle")
            #if os(iOS)
                .frame(minWidth: 44, minHeight: 44)
            #endif
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Remove condition", bundle: .module))
        .help(String(localized: "Remove condition", bundle: .module))
    }
}
