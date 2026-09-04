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

enum MailProfileManagementPresentationSize: Equatable, Sendable {
    case compact
    case regular
}

enum MailProfileManagementEditorLayout: Equatable, Sendable {
    case stacked
    case columns
}

struct MailProfileManagementSheetFrame: Equatable, Sendable {
    let minimumWidth: CGFloat?
    let maximumWidth: CGFloat?
    let minimumHeight: CGFloat?
    let maximumHeight: CGFloat?
}

enum MailProfileManagementLayoutPolicy {
    static func sheetFrame(for size: MailProfileManagementPresentationSize) -> MailProfileManagementSheetFrame {
        switch size {
        case .compact:
            MailProfileManagementSheetFrame(
                minimumWidth: nil,
                maximumWidth: .infinity,
                minimumHeight: nil,
                maximumHeight: .infinity
            )
        case .regular:
            MailProfileManagementSheetFrame(
                minimumWidth: 520,
                maximumWidth: nil,
                minimumHeight: 420,
                maximumHeight: nil
            )
        }
    }

    static func editorLayout(for availableWidth: CGFloat) -> MailProfileManagementEditorLayout {
        availableWidth < 560 ? .stacked : .columns
    }
}

struct MailProfileManagementSheet: View {
    @Environment(\.brevTheme) private var theme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private let availableSources: [MailSourceSection]
    private let onSave: ([MailProfile]) -> Void
    private let onClose: (() -> Void)?

    @State private var draftProfiles: [MailProfile]
    @State private var selectedProfileID: MailProfile.ID?
    @State private var newProfileName = ""

    init(
        availableSources: [MailSourceSection],
        customProfiles: [MailProfile],
        onSave: @escaping ([MailProfile]) -> Void,
        onClose: (() -> Void)? = nil
    ) {
        self.availableSources = availableSources
        self.onSave = onSave
        self.onClose = onClose
        _draftProfiles = State(initialValue: customProfiles)
        _selectedProfileID = State(initialValue: customProfiles.first?.id)
    }

    var body: some View {
        #if os(macOS)
        // Keep auxiliary-window actions in its content. NavigationStack toolbars
        // can remain attached to the owner's window when this hosting controller closes.
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(String(localized: "Cancel", bundle: .module)) { onClose?() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Done", bundle: .module)) { saveAndClose() }
                    .keyboardShortcut(.defaultAction)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, BrevSpacing.lg)
            .padding(.top, BrevSpacing.md)
            profileForm
        }
        .background(theme.bgPrimary.color)
        #else
        NavigationStack {
            profileForm
                .navigationTitle(String(localized: "Profiles", bundle: .module))
                .profileSheetNavigationTitleStyle()
                .profileSheetNavigationBackground(theme: theme)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Cancel", bundle: .module)) { onClose?() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Done", bundle: .module)) { saveAndClose() }
                    }
                }
        }
        #endif
    }

    private func saveAndClose() {
        onSave(normalizedDraftProfiles)
        onClose?()
    }

    private var profileForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrevSpacing.lg) {
                profileCreator
                BrevDivider()
                if draftProfiles.isEmpty {
                    emptyState
                } else {
                    profileEditor
                }
            }
            .padding(BrevSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: sheetFrame.minimumWidth, maxWidth: sheetFrame.maximumWidth,
               minHeight: sheetFrame.minimumHeight, maxHeight: sheetFrame.maximumHeight,
               alignment: .topLeading)
        .background(theme.bgPrimary.color)
    }

    @ViewBuilder
    private var profileCreator: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            Text("Profiles", bundle: .module)
                .brevFont(.headline)
                .foregroundStyle(theme.textPrimary.color)
            HStack(spacing: BrevSpacing.sm) {
                themedTextField("New profile name", text: $newProfileName)
                Button {
                    addProfile()
                } label: {
                    Image(systemName: "plus")
                        .brevFont(.headline)
                        .foregroundStyle(theme.accent.color)
                        .frame(width: 40, height: 40)
                        .background(BrevWindowSurfaceBackground(role: .card))
                        .overlay {
                            RoundedRectangle(cornerRadius: BrevRadius.md)
                                .stroke(theme.border.color, lineWidth: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: BrevRadius.md))
                }
                .buttonStyle(.plain)
                .disabled(availableSources.isEmpty)
                .opacity(availableSources.isEmpty ? 0.5 : 1)
                .accessibilityLabel(String(localized: "Add profile", bundle: .module))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            let helpText = "All Mailboxes is always available. Custom profiles choose which "
                + "sources appear in the sidebar and Unified Inbox."
            Text(helpText)
                .brevFont(.caption)
                .foregroundStyle(theme.textTertiary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            Text("No custom profiles", bundle: .module)
                .brevFont(.subheadline)
                .foregroundStyle(theme.textPrimary.color)
            Text("Create a profile to show a focused set of mailboxes without disconnecting the rest.", bundle: .module)
                .brevFont(.footnote)
                .foregroundStyle(theme.textSecondary.color)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var profileEditor: some View {
        switch editorLayout {
        case .stacked:
            stackedProfileEditor
        case .columns:
            columnProfileEditor
        }
    }

    @ViewBuilder
    private var columnProfileEditor: some View {
        HStack(alignment: .top, spacing: BrevSpacing.lg) {
            profileList
                .frame(width: 180, alignment: .topLeading)
            BrevDivider()
                .frame(width: 1)
            selectedProfileEditor
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var stackedProfileEditor: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.lg) {
            profileList
                .frame(maxWidth: .infinity, alignment: .topLeading)
            BrevDivider()
            selectedProfileEditor
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var profileList: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
            ForEach(draftProfiles) { profile in
                Button {
                    selectedProfileID = profile.id
                } label: {
                    HStack(spacing: BrevSpacing.xs) {
                        Image(systemName: selectedProfileID == profile.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(
                                selectedProfileID == profile.id
                                    ? theme.accent.color
                                    : theme.textTertiary.color
                            )
                        Text(profile.name)
                            .brevFont(.footnote)
                            .foregroundStyle(theme.textPrimary.color)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, BrevSpacing.sm)
                    .padding(.vertical, BrevSpacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: BrevRadius.sm, style: .continuous)
                            .fill(selectedProfileID == profile.id ? theme.selection.color : Color.clear)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: BrevRadius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var selectedProfileEditor: some View {
        if let selectedProfile {
            VStack(alignment: .leading, spacing: BrevSpacing.lg) {
                HStack(alignment: .center, spacing: BrevSpacing.sm) {
                    themedTextField(
                        "Profile name",
                        text: Binding(
                            get: { selectedProfile.name },
                            set: { renameSelectedProfile($0) }
                        )
                    )
                    reorderButton(systemImage: "chevron.up", label: "Move up", enabled: canMoveSelectedProfileUp) {
                        moveSelectedProfile(.up)
                    }
                    reorderButton(systemImage: "chevron.down", label: "Move down", enabled: canMoveSelectedProfileDown) {
                        moveSelectedProfile(.down)
                    }
                }

                VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                    Text("VISIBLE MAILBOXES", bundle: .module)
                        .brevFont(.caption)
                        .foregroundStyle(theme.textSecondary.color)
                    VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                        ForEach(availableSources) { source in
                            Toggle(
                                isOn: membershipBinding(for: source.id),
                                label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(source.title)
                                            .brevFont(.footnote)
                                            .foregroundStyle(theme.textPrimary.color)
                                        Text(source.subtitle)
                                            .brevFont(.caption)
                                            .foregroundStyle(theme.textTertiary.color)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }
                            )
                            #if os(macOS)
                            .toggleStyle(.checkbox)
                            #endif
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(BrevSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: BrevRadius.md, style: .continuous)
                            .fill(theme.bgSecondary.color)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: BrevRadius.md, style: .continuous)
                            .stroke(theme.border.color, lineWidth: 1)
                    )
                }

                if !unavailableSourceIDs.isEmpty {
                    Text(
                        "\(unavailableSourceIDs.count) unavailable mailboxes are still part of this profile. Reconnect them in Accounts, or remove their membership here.",
                        bundle: .module
                    )
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                    Button(String(localized: "Remove unavailable mailboxes", bundle: .module)) {
                        for sourceID in unavailableSourceIDs {
                            membershipBinding(for: sourceID).wrappedValue = false
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.accent.color)
                }
                Spacer(minLength: 0)
                BrevButton("Delete Profile", style: .destructive) {
                    deleteSelectedProfile()
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func reorderButton(
        systemImage: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .brevFont(.subheadline)
                .foregroundStyle(enabled ? theme.textSecondary.color : theme.textTertiary.color)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: BrevRadius.sm, style: .continuous)
                        .fill(theme.bgSecondary.color)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: BrevRadius.sm, style: .continuous)
                        .stroke(theme.border.color, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .help(label)
        .accessibilityLabel(label)
    }

    private var presentationSize: MailProfileManagementPresentationSize {
        #if os(iOS)
        horizontalSizeClass == .compact ? .compact : .regular
        #else
        .regular
        #endif
    }

    private var sheetFrame: MailProfileManagementSheetFrame {
        MailProfileManagementLayoutPolicy.sheetFrame(for: presentationSize)
    }

    private var editorLayout: MailProfileManagementEditorLayout {
        switch presentationSize {
        case .compact:
            .stacked
        case .regular:
            .columns
        }
    }

    private var selectedProfile: MailProfile? {
        guard let selectedProfileID else { return nil }
        return draftProfiles.first { $0.id == selectedProfileID }
    }

    private var selectedProfileIndex: Int? {
        guard let selectedProfileID else { return nil }
        return draftProfiles.firstIndex { $0.id == selectedProfileID }
    }

    private var canMoveSelectedProfileUp: Bool {
        guard let selectedProfileIndex else { return false }
        return selectedProfileIndex > 0
    }

    private var canMoveSelectedProfileDown: Bool {
        guard let selectedProfileIndex else { return false }
        return selectedProfileIndex < draftProfiles.count - 1
    }

    private var unavailableSourceIDs: [MailSourceID] {
        guard let selectedProfile else { return [] }
        let available = Set(availableSources.map(\.id))
        return selectedProfile.sourceIDs.filter { !available.contains($0) }
    }

    private var normalizedDraftProfiles: [MailProfile] {
        MailProfileSelectionPolicy.normalizedCustomProfiles(
            draftProfiles,
            availableSourceIDs: availableSources.map(\.id)
        )
    }

    private func addProfile() {
        let trimmedName = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedName.isEmpty ? "New Profile" : trimmedName
        let sourceIDs = availableSources.map(\.id)
        let profile = MailProfile(name: name, sourceIDs: sourceIDs)
        draftProfiles.append(profile)
        selectedProfileID = profile.id
        newProfileName = ""
    }

    private func renameSelectedProfile(_ name: String) {
        guard let selectedProfileID,
              let index = draftProfiles.firstIndex(where: { $0.id == selectedProfileID })
        else { return }
        draftProfiles[index].name = name
    }

    private func moveSelectedProfile(_ direction: MailProfileMoveDirection) {
        guard let selectedProfileID else { return }
        draftProfiles = MailProfileSelectionPolicy.moveCustomProfile(
            id: selectedProfileID,
            direction: direction,
            in: draftProfiles
        )
    }

    private func membershipBinding(for sourceID: MailSourceID) -> Binding<Bool> {
        Binding(
            get: {
                guard let selectedProfile else { return false }
                return selectedProfile.sourceIDs.contains(sourceID)
            },
            set: { isIncluded in
                guard let selectedProfileID,
                      let index = draftProfiles.firstIndex(where: { $0.id == selectedProfileID })
                else { return }
                if isIncluded {
                    if !draftProfiles[index].sourceIDs.contains(sourceID) {
                        draftProfiles[index].sourceIDs.append(sourceID)
                    }
                } else {
                    draftProfiles[index].sourceIDs.removeAll { $0 == sourceID }
                }
            }
        )
    }

    private func deleteSelectedProfile() {
        guard let selectedProfileID else { return }
        draftProfiles.removeAll { $0.id == selectedProfileID }
        self.selectedProfileID = draftProfiles.first?.id
    }

    @ViewBuilder
    private func themedTextField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text, prompt: Text(title).foregroundStyle(theme.textTertiary.color))
            .textFieldStyle(.plain)
            .brevFont(.body)
            .foregroundStyle(theme.textPrimary.color)
            .padding(.horizontal, BrevSpacing.md)
            .padding(.vertical, BrevSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(BrevWindowSurfaceBackground(role: .card))
            .overlay {
                RoundedRectangle(cornerRadius: BrevRadius.md)
                    .stroke(theme.border.color, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: BrevRadius.md))
    }
}

private extension View {
    @ViewBuilder
    func profileSheetNavigationTitleStyle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func profileSheetNavigationBackground(theme: BrevTheme) -> some View {
        #if os(iOS)
        toolbarBackground(theme.bgPrimary.color, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        #else
        self
        #endif
    }
}
