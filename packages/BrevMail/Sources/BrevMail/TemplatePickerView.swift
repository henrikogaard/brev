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
import BrevSettings
import BrevThemes
import SwiftUI

/// Sheet presented from the compose toolbar "Templates" button.
///
/// Lists all available templates and lets the user:
/// - Tap a template to insert its subject + body into the compose fields.
/// - Save the current compose state as a new named template.
struct TemplatePickerView: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @Binding var templateSettings: MessageTemplateSettings

    let accountID: String?
    let currentSubject: String
    let currentBody: String
    let onInsert: (MessageTemplate) -> Void
    let onSaveAsTemplate: (String) -> Void

    @State private var saveAsName = ""
    @State private var showSaveAsField = false
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                BrevDivider()
                if filteredTemplates.isEmpty && !showSaveAsField {
                    emptyState
                } else {
                    templateList
                }
                BrevDivider()
                saveAsBar
            }
            .navigationTitle(String(localized: "Templates", bundle: .module))
            #if os(macOS)
                .navigationSubtitle(String(localized: "\(filteredTemplates.count) template(s)", bundle: .module))
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Done", bundle: .module)) { dismiss() }
                    }
                }
        }
        .frame(minWidth: 400, minHeight: 360)
    }

    // MARK: - Sub-views

    private var searchBar: some View {
        HStack(spacing: BrevSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.textTertiary.color)
            TextField(String(localized: "Search templates", bundle: .module), text: $searchText)
                .brevFont(.body)
                .foregroundStyle(theme.textPrimary.color)
        }
        .padding(.horizontal, BrevSpacing.lg)
        .padding(.vertical, BrevSpacing.sm)
    }

    private var emptyState: some View {
        VStack(spacing: BrevSpacing.md) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 40))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.textTertiary.color)
            Text(
                searchText.isEmpty
                    ? String(localized: "No Templates", bundle: .module)
                    : String(localized: "No templates match your search", bundle: .module)
            )
            .brevFont(.headline)
            .foregroundStyle(theme.textPrimary.color)
            Text("Save the current message as a template\nto reuse it in future conversations.", bundle: .module)
                .brevFont(.subheadline)
                .foregroundStyle(theme.textSecondary.color)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(BrevSpacing.xl)
    }

    private var templateList: some View {
        List(filteredTemplates) { template in
            Button {
                onInsert(template)
                dismiss()
            } label: {
                HStack(spacing: BrevSpacing.md) {
                    VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                        Text(verbatim: template.name)
                            .brevFont(.body)
                            .foregroundStyle(theme.textPrimary.color)
                            .lineLimit(1)
                        if let subject = template.subject, !subject.isEmpty {
                            Text("Subject: \(subject)", bundle: .module)
                                .brevFont(.caption)
                                .foregroundStyle(theme.textTertiary.color)
                        }
                        Text(verbatim: template.body)
                            .brevFont(.footnote)
                            .foregroundStyle(theme.textSecondary.color)
                            .lineLimit(2)
                    }
                    Spacer()
                    if template.isPinned {
                        Image(systemName: "pin.fill")
                            .foregroundStyle(theme.accent.color)
                            .font(.caption)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
    }

    private var saveAsBar: some View {
        Group {
            if showSaveAsField {
                HStack(spacing: BrevSpacing.sm) {
                    TextField(String(localized: "Template name", bundle: .module), text: $saveAsName)
                        .textFieldStyle(.plain)
                        .brevFont(.body)
                        .foregroundStyle(theme.textPrimary.color)
                        .frame(maxWidth: .infinity)
                    Button(String(localized: "Save", bundle: .module)) {
                        onSaveAsTemplate(saveAsName)
                        saveAsName = ""
                        showSaveAsField = false
                        templateSettings = MessageTemplateSettings.load()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(saveAsName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(String(localized: "Cancel", bundle: .module)) {
                        saveAsName = ""
                        showSaveAsField = false
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, BrevSpacing.lg)
                .padding(.vertical, BrevSpacing.md)
            } else {
                Button {
                    showSaveAsField = true
                } label: {
                    Label(String(localized: "Save current message as template…", bundle: .module), systemImage: "plus")
                        .brevFont(.subheadline)
                        .foregroundStyle(theme.accent.color)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, BrevSpacing.lg)
                .padding(.vertical, BrevSpacing.md)
            }
        }
        .background(BrevWindowSurfaceBackground(role: .utility))
    }

    // MARK: - Helpers

    private var filteredTemplates: [MessageTemplate] {
        TemplatePickerPresentation.visibleTemplates(
            settings: templateSettings,
            accountID: accountID,
            searchText: searchText
        )
    }
}
