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

/// Keeps mailbox scope visible while grouping optional search controls in one menu.
struct MailSearchOptionsBar: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var execution: SearchExecution
    let availableExecutions: [SearchExecution]
    var folderScope: Binding<Bool>?
    var fieldScope: Binding<SearchScope>?

    var body: some View {
        controls
            .brevFont(.subheadline).fontWeight(.regular)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(theme.textSecondary.color)
            .padding(.horizontal, BrevSpacing.md)
            .padding(.vertical, BrevSpacing.xs)
            .overlay(alignment: .bottom) {
                Rectangle().fill(BrevSeparator.color(for: theme)).frame(height: 0.5)
            }
    }

    @ViewBuilder
    private var controls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                mailboxScope
                filters
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: BrevSpacing.sm) {
                mailboxScope
                Spacer(minLength: BrevSpacing.sm)
                filters
            }
        }
    }

    @ViewBuilder
    private var mailboxScope: some View {
        if let folderScope {
            Menu {
                Picker(String(localized: "Search folder scope", bundle: .module), selection: folderScope) {
                    Text("This folder", bundle: .module).tag(false)
                    Text("All mailboxes", bundle: .module).tag(true)
                }
            } label: {
                Label(folderScope.wrappedValue
                    ? String(localized: "All mailboxes", bundle: .module)
                    : String(localized: "This folder", bundle: .module), systemImage: "tray")
                    .searchOptionsTouchTarget()
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel(String(localized: "Search folder scope", bundle: .module))
        } else {
            Label(String(localized: "All mailboxes", bundle: .module), systemImage: "tray.2")
                .searchOptionsTouchTarget()
        }
    }

    private var filters: some View {
        Menu {
            if let fieldScope {
                Picker(String(localized: "Search scope", bundle: .module), selection: fieldScope) {
                    ForEach(SearchScope.allCases) { scope in
                        Label(scope.title, systemImage: scope.symbolName).tag(scope)
                    }
                }
                Divider()
            }
            Picker(String(localized: "Search location", bundle: .module), selection: $execution) {
                ForEach(availableExecutions, id: \.self) { option in
                    Label(option.messageListTitle, systemImage: option.messageListSymbolName).tag(option)
                }
            }
        } label: {
            Label(filterTitle, systemImage: "line.3.horizontal.decrease.circle")
                .searchOptionsTouchTarget()
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel(String(localized: "Search filters", bundle: .module))
        .accessibilityValue(execution.messageListTitle)
    }

    private var filterTitle: String {
        var parts: [String] = []
        if let scope = fieldScope?.wrappedValue, scope != .all { parts.append(scope.title) }
        if execution != .cacheThenServer { parts.append(execution.messageListTitle) }
        return parts.isEmpty ? String(localized: "Filters", bundle: .module) : parts.joined(separator: " · ")
    }
}

private extension View {
    func searchOptionsTouchTarget() -> some View {
        #if os(iOS)
        frame(minHeight: 44).contentShape(Rectangle())
        #else
        self
        #endif
    }
}
