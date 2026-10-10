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

enum InitialMailboxSelectionPresentation {
    static let guidanceText = String(
        localized: "Select the mailboxes Brev should show, then choose the default mailbox for compose and first launch.",
        bundle: .module
    )

    struct SelectionState: Equatable, Sendable {
        var selectedSourceIDs: Set<MailSourceID>
        var defaultSourceID: MailSourceID?
    }

    static func initialState(
        availableSourceIDs: [MailSourceID],
        preferredDefaultSourceID: MailSourceID?,
        preferences: MailboxSourcePreferences
    ) -> SelectionState {
        let enabledSourceIDs = MailboxSourcePreferencesPolicy.enabledSourceIDs(
            availableSourceIDs: availableSourceIDs,
            preferences: preferences
        )
        return SelectionState(
            selectedSourceIDs: Set(enabledSourceIDs),
            defaultSourceID: MailboxSourcePreferencesPolicy.defaultSourceID(
                availableSourceIDs: availableSourceIDs,
                preferences: preferences,
                preferredDefaultSourceID: preferredDefaultSourceID
            )
        )
    }

    static func setSource(
        _ sourceID: MailSourceID,
        isEnabled: Bool,
        in state: SelectionState,
        orderedSourceIDs: [MailSourceID]
    ) -> SelectionState {
        var updated = state
        if isEnabled {
            updated.selectedSourceIDs.insert(sourceID)
            updated.defaultSourceID = updated.defaultSourceID ?? sourceID
            return updated
        }

        guard updated.selectedSourceIDs.count > 1 else { return state }
        updated.selectedSourceIDs.remove(sourceID)
        if updated.defaultSourceID == sourceID {
            updated.defaultSourceID = orderedSourceIDs.first {
                updated.selectedSourceIDs.contains($0)
            }
        }
        return updated
    }

    static func makeDefault(
        _ sourceID: MailSourceID,
        in state: SelectionState
    ) -> SelectionState {
        var updated = state
        updated.defaultSourceID = sourceID
        updated.selectedSourceIDs.insert(sourceID)
        return updated
    }
}

struct InitialMailboxSelectionPresentationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let sourceSections: [MailSourceSection]
    let initialPreferences: MailboxSourcePreferences
    let theme: BrevTheme
    let onSave: (MailboxSourcePreferences) -> Void
    /// Leaves the sheet without choosing; the defaults (every mailbox, the
    /// primary one as default) stay in place.
    let onSkip: () -> Void

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            InitialMailboxSelectionSheet(
                sourceSections: sourceSections,
                initialPreferences: initialPreferences,
                onSave: onSave,
                onSkip: onSkip
            )
            .brevSheetAppearance(theme)
            .interactiveDismissDisabled(true)
        }
    }
}

private struct InitialMailboxSelectionSheet: View {
    @Environment(\.brevTheme) private var theme

    let sourceSections: [MailSourceSection]
    let onSave: (MailboxSourcePreferences) -> Void
    let onSkip: () -> Void

    @State private var selectionState: InitialMailboxSelectionPresentation.SelectionState

    init(
        sourceSections: [MailSourceSection],
        initialPreferences: MailboxSourcePreferences,
        onSave: @escaping (MailboxSourcePreferences) -> Void,
        onSkip: @escaping () -> Void
    ) {
        self.sourceSections = sourceSections
        self.onSave = onSave
        self.onSkip = onSkip
        let availableSourceIDs = sourceSections.map(\.id)
        let preferredDefault = sourceSections.first { $0.mailbox.isPrimary }?.id
        _selectionState = State(initialValue: InitialMailboxSelectionPresentation.initialState(
            availableSourceIDs: availableSourceIDs,
            preferredDefaultSourceID: preferredDefault,
            preferences: initialPreferences
        ))
    }

    var body: some View {
        #if os(iOS)
        nativeBody
        #else
        desktopBody
        #endif
    }

    private var canContinue: Bool {
        !selectionState.selectedSourceIDs.isEmpty && selectionState.defaultSourceID != nil
    }

    #if os(iOS)
    /// iOS: a standard sheet with Skip / Continue in the navigation bar, a
    /// switch per mailbox and a checkmark list for the default mailbox.
    private var nativeBody: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(sourceSections) { section in
                        nativeMailboxRow(section)
                    }
                } header: {
                    Text(InitialMailboxSelectionPresentation.guidanceText)
                        .brevFont(.footnote)
                        .foregroundStyle(theme.textSecondary.color)
                        .textCase(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section {
                    ForEach(sourceSections.filter { selectionState.selectedSourceIDs.contains($0.id) }) { section in
                        nativeDefaultRow(section)
                    }
                } header: {
                    Text("Default mailbox", bundle: .module)
                        .brevFont(.footnote)
                        .foregroundStyle(theme.textSecondary.color)
                        .textCase(nil)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(Text("Choose Mailboxes", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onSkip()
                    } label: {
                        Text("Skip", bundle: .module)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        Text("Continue", bundle: .module)
                    }
                    .disabled(!canContinue)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func nativeMailboxRow(_ section: MailSourceSection) -> some View {
        let isEnabled = selectionState.selectedSourceIDs.contains(section.id)
        return Toggle(isOn: Binding(
            get: { isEnabled },
            set: { setEnabled($0, for: section.id) }
        )) {
            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                Text(section.title)
                    .brevFont(.body)
                    .foregroundStyle(theme.textPrimary.color)
                Text(section.subtitle)
                    .brevFont(.footnote)
                    .foregroundStyle(theme.textSecondary.color)
                    .truncationMode(.middle)
            }
        }
        .disabled(isEnabled && selectionState.selectedSourceIDs.count == 1)
        .brevSheetRow()
    }

    private func nativeDefaultRow(_ section: MailSourceSection) -> some View {
        let isDefault = selectionState.defaultSourceID == section.id
        return Button {
            selectionState = InitialMailboxSelectionPresentation.makeDefault(
                section.id,
                in: selectionState
            )
        } label: {
            HStack(spacing: BrevSpacing.md) {
                Text(section.title)
                    .brevFont(.body)
                    .foregroundStyle(theme.textPrimary.color)
                Spacer(minLength: BrevSpacing.sm)
                if isDefault {
                    Image(systemName: "checkmark")
                        .foregroundStyle(theme.accent.color)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .brevSheetRow()
        .accessibilityLabel(
            isDefault
                ? section.title
                : String(localized: "Make \(section.title) the default", bundle: .module)
        )
        .accessibilityValue(isDefault ? String(localized: "Default mailbox", bundle: .module) : "")
        .accessibilityAddTraits(isDefault ? .isSelected : [])
    }
    #endif

    #if os(macOS)
    private var desktopBody: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.lg) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                    ForEach(sourceSections) { section in
                        mailboxRow(section)
                    }
                }
            }
            .scrollIndicators(.visible, axes: .vertical)

            HStack {
                Spacer()
                BrevButton("Continue", style: .primary, bundle: .module) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canContinue)
            }
        }
        .padding(BrevSpacing.xl)
        .frame(maxWidth: 560)
        .background(BrevWindowSurfaceBackground(role: .content).ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            Text("Choose Mailboxes", bundle: .module)
                .brevFont(.headline)
                .foregroundStyle(theme.textPrimary.color)
            Text(InitialMailboxSelectionPresentation.guidanceText)
                .brevFont(.body)
                .foregroundStyle(theme.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func mailboxRow(_ section: MailSourceSection) -> some View {
        let isEnabled = selectionState.selectedSourceIDs.contains(section.id)
        let isDefault = selectionState.defaultSourceID == section.id
        return HStack(alignment: .center, spacing: BrevSpacing.md) {
            Toggle(isOn: Binding(
                get: { isEnabled },
                set: { setEnabled($0, for: section.id) }
            )) {
                VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                    Text(section.title)
                        .brevFont(.subheadline)
                        .foregroundStyle(theme.textPrimary.color)
                        .lineLimit(1)
                    Text(section.subtitle)
                        .brevFont(.caption)
                        .foregroundStyle(theme.textTertiary.color)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .toggleStyle(.switch)
            .tint(theme.accent.color)
            .disabled(isEnabled && selectionState.selectedSourceIDs.count == 1)

            Spacer(minLength: BrevSpacing.md)

            Button {
                selectionState = InitialMailboxSelectionPresentation.makeDefault(
                    section.id,
                    in: selectionState
                )
            } label: {
                Image(systemName: isDefault ? "checkmark.circle.fill" : "circle")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isDefault ? theme.accent.color : theme.textTertiary.color)
                    .frame(minWidth: defaultButtonHitSize, minHeight: defaultButtonHitSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled && !isDefault)
            .accessibilityLabel(
                isDefault
                    ? String(localized: "Default mailbox", bundle: .module)
                    : String(localized: "Make default mailbox", bundle: .module)
            )
            .accessibilityAddTraits(isDefault ? .isSelected : [])
            .help(
                isDefault
                    ? String(localized: "Default mailbox", bundle: .module)
                    : String(localized: "Make default mailbox", bundle: .module)
            )
        }
        .padding(BrevSpacing.md)
        .brevQuietSurface()
    }

    private var defaultButtonHitSize: CGFloat { 30 }
    #endif

    private func setEnabled(_ isEnabled: Bool, for sourceID: MailSourceID) {
        selectionState = InitialMailboxSelectionPresentation.setSource(
            sourceID,
            isEnabled: isEnabled,
            in: selectionState,
            orderedSourceIDs: sourceSections.map(\.id)
        )
    }

    private func save() {
        let availableSourceIDs = sourceSections.map(\.id)
        let enabledSourceIDs = sourceSections
            .map(\.id)
            .filter { selectionState.selectedSourceIDs.contains($0) }
        let preferredDefault = sourceSections.first { $0.mailbox.isPrimary }?.id
        let preferences = MailboxSourcePreferencesPolicy.normalized(
            availableSourceIDs: availableSourceIDs,
            enabledSourceIDs: enabledSourceIDs,
            defaultSourceID: selectionState.defaultSourceID,
            preferredDefaultSourceID: preferredDefault
        )
        onSave(preferences)
    }
}
