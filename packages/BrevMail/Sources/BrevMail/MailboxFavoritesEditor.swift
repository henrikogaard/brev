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

struct MailboxFavoritesEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.brevTheme) private var theme
    @Binding var data: Data
    let candidates: [MailboxFavorite]

    private var preferences: MailboxFavorites { MailboxFavorites(data: data) }
    private var ordered: [MailboxFavorite] { preferences.ordered(candidates) }

    var body: some View {
        #if os(macOS)
        desktopEditor
        #else
        NavigationStack {
            List {
                Section {
                    ForEach(ordered) { favorite in
                        Button {
                            var updated = preferences
                            updated.setVisible(!preferences.isVisible(favorite), id: favorite.id)
                            data = updated.data
                        } label: {
                            HStack(spacing: BrevSpacing.md) {
                                Image(systemName: preferences.isVisible(favorite) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(preferences.isVisible(favorite) ? theme.accent.color : theme.textTertiary
                                        .color)
                                    .frame(width: 22)
                                    .dynamicTypeSize(...DynamicTypeSize.large)
                                    .accessibilityHidden(true)
                                Image(systemName: favorite.symbol).frame(width: 22)
                                    .dynamicTypeSize(...DynamicTypeSize.large)
                                    .foregroundStyle(theme.textSecondary.color)
                                VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                                    Text(verbatim: favorite.title).foregroundStyle(theme.textPrimary.color)
                                    if let subtitle = favorite.subtitle {
                                        Text(verbatim: subtitle).brevFont(.caption)
                                            .foregroundStyle(theme.textSecondary.color)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .brevFont(.body)
                            .padding(.vertical, BrevSpacing.xs)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(preferences.isVisible(favorite) ? .isSelected : [])
                        .tint(theme.accent.color)
                        .listRowBackground(theme.bgPrimary.color)
                        .listRowInsets(EdgeInsets(top: 0, leading: BrevSpacing.lg, bottom: 0, trailing: BrevSpacing.md))
                        .accessibilityAction(named: String(localized: "Move up", bundle: .module)) {
                            move(favorite, by: -1)
                        }
                        .accessibilityAction(named: String(localized: "Move down", bundle: .module)) {
                            move(favorite, by: 1)
                        }
                    }
                    .onMove { offsets, destination in
                        var ids = ordered.map(\.id)
                        ids.move(fromOffsets: offsets, toOffset: destination)
                        var updated = preferences
                        updated.reorder(ids)
                        data = updated.data
                    }
                } footer: {
                    Text(
                        "Choose your shortcuts and drag to reorder. Inbox counts show unread mail; Drafts counts show all drafts.",
                        bundle: .module
                    )
                }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background(theme.bgSecondary.color)
            .navigationTitle(String(localized: "Favourites", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done", bundle: .module)) { dismiss() }
                }
            }
        }
        .tint(theme.accent.color)
        #endif
    }

    #if os(macOS)
    private var desktopEditor: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.md) {
            Text("Favourites", bundle: .module).brevFont(.title).fontWeight(.semibold)
            Text(
                "Choose your shortcuts and drag to reorder. Inbox counts show unread mail; Drafts counts show all drafts.",
                bundle: .module
            )
            .brevFont(.caption).foregroundStyle(theme.textSecondary.color)
            List {
                ForEach(ordered) { favorite in
                    HStack(spacing: BrevSpacing.sm) {
                        Toggle(isOn: Binding(
                            get: { preferences.isVisible(favorite) },
                            set: { visible in
                                var updated = preferences
                                updated.setVisible(visible, id: favorite.id)
                                data = updated.data
                            }
                        )) {
                            Label {
                                Text(verbatim: [favorite.title, favorite.subtitle].compactMap { $0 }.joined(separator: " · "))
                                    .lineLimit(1)
                            } icon: {
                                Image(systemName: favorite.symbol).frame(width: 18)
                                    .foregroundStyle(theme.textSecondary.color)
                            }
                        }
                        .toggleStyle(.checkbox)
                        Spacer(minLength: BrevSpacing.sm)
                        Button { move(favorite, by: -1) } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.borderless)
                            .help(String(localized: "Move up", bundle: .module))
                            .accessibilityLabel(String(localized: "Move up", bundle: .module))
                            .disabled(favorite.id == ordered.first?.id)
                        Button { move(favorite, by: 1) } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.borderless)
                            .help(String(localized: "Move down", bundle: .module))
                            .accessibilityLabel(String(localized: "Move down", bundle: .module))
                            .disabled(favorite.id == ordered.last?.id)
                    }
                    .brevFont(.body)
                    .padding(.vertical, BrevSpacing.xs)
                    .listRowBackground(theme.bgPrimary.color)
                    .accessibilityAction(named: String(localized: "Move up", bundle: .module)) { move(favorite, by: -1) }
                    .accessibilityAction(named: String(localized: "Move down", bundle: .module)) { move(favorite, by: 1) }
                }
                .onMove { offsets, destination in
                    var ids = ordered.map(\.id)
                    ids.move(fromOffsets: offsets, toOffset: destination)
                    var updated = preferences
                    updated.reorder(ids)
                    data = updated.data
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(theme.bgPrimary.color, in: RoundedRectangle(cornerRadius: BrevRadius.md))
            HStack {
                Spacer()
                Button(String(localized: "Done", bundle: .module)) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(BrevSpacing.lg)
        .foregroundStyle(theme.textPrimary.color)
        .background(theme.bgSecondary.color)
        .tint(theme.accent.color)
        .brevDesktopSizing()
        .frame(width: 520, height: 440)
    }
    #endif

    private func move(_ favorite: MailboxFavorite, by offset: Int) {
        var ids = ordered.map(\.id)
        guard let index = ids.firstIndex(of: favorite.id), ids.indices.contains(index + offset) else { return }
        ids.swapAt(index, index + offset)
        var updated = preferences
        updated.reorder(ids)
        data = updated.data
    }
}
