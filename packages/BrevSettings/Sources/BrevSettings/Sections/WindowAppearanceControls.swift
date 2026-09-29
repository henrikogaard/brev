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

/// Simple coverage choices mapped to the existing stored material preferences.
enum WindowTransparencySelection: CaseIterable, Identifiable {
    case off, sidebars, fullWindows

    var id: Self { self }

    init(_ preferences: WindowAppearancePreferences) {
        self = preferences.mode == .solid ? .off : preferences.scope == .sidebarOnly ? .sidebars : .fullWindows
    }

    var title: String {
        switch self {
        case .off: String(localized: "Off", bundle: .module)
        case .sidebars: String(localized: "Sidebars only", bundle: .module)
        case .fullWindows: String(localized: "Full windows", bundle: .module)
        }
    }

    var detail: String {
        switch self {
        case .off: String(localized: "All window backgrounds are solid.", bundle: .module)
        case .sidebars:
            String(localized: "Only the Mail and Settings sidebars are transparent. Messages and compose windows stay solid.",
                   bundle: .module)
        case .fullWindows:
            String(
                localized: "Applies to Mail, Settings, compose windows, and messages opened in separate windows.",
                bundle: .module
            )
        }
    }

    func apply(to preferences: inout WindowAppearancePreferences) {
        if self == .off {
            preferences.mode = .solid
        } else {
            if preferences.mode == .solid { preferences.mode = .subtle }
            preferences.scope = self == .sidebars ? .sidebarOnly : .allWindows
        }
    }
}

struct WindowAppearanceControls: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Binding var preferences: WindowAppearancePreferences
    @Binding var unifiedTitlebar: Bool
    @Binding var showsAdvanced: Bool
    let onChange: () -> Void

    private var selection: WindowTransparencySelection { WindowTransparencySelection(preferences) }

    var body: some View {
        SettingsGroup(title: String(localized: "Window transparency", bundle: .module),
                      subtitle: String(localized: "Choose where the background shows through.", bundle: .module),
                      symbolName: "macwindow") {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                Picker(String(localized: "Transparency", bundle: .module), selection: Binding(
                    get: { selection }, set: { $0.apply(to: &preferences); onChange() }
                )) {
                    ForEach(WindowTransparencySelection.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .id(String(localized: "Transparency", bundle: .module))
                .labelsHidden()
                Text(selection.detail).brevFont(.caption).foregroundStyle(theme.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                WindowTransparencyPreview(preferences: preferences)

                if selection != .off {
                    VStack(alignment: .leading, spacing: BrevSpacing.md) {
                        opacityControl(String(localized: "Sidebar background opacity", bundle: .module),
                                       value: binding(\.sidebarOpacity), range: WindowAppearancePreferences.sidebarOpacityRange)
                        if selection == .fullWindows {
                            opacityControl(String(localized: "Window background opacity", bundle: .module),
                                           value: binding(\.surfaceOpacity),
                                           range: WindowAppearancePreferences.surfaceOpacityRange)
                        }
                        Text("Lower opacity shows more of the blurred background. Text and icons stay opaque.", bundle: .module)
                            .brevFont(.caption).foregroundStyle(theme.textSecondary.color)
                    }
                    .disabled(reduceTransparency)
                }

                DisclosureGroup(String(localized: "Advanced", bundle: .module), isExpanded: $showsAdvanced) {
                    VStack(alignment: .leading, spacing: BrevSpacing.md) {
                        if selection != .off {
                            SettingsPickerRow(symbolName: "circle.lefthalf.filled",
                                              title: String(localized: "Background effect", bundle: .module),
                                              subtitle: String(
                                                  localized: "Choose the blur style for transparent areas.",
                                                  bundle: .module
                                              ),
                                              selection: binding(\.mode)) {
                                ForEach(WindowTranslucencyMode.allCases.filter { $0 != .solid }) { Text($0.title).tag($0) }
                            }
                            .disabled(reduceTransparency)
                        }
                        SettingsToggleRow(symbolName: "macwindow.on.rectangle",
                                          title: String(localized: "Unified title bar", bundle: .module),
                                          subtitle: String(
                                              localized: "Extend content behind the title bar. This does not change transparency.",
                                              bundle: .module
                                          ), isOn: $unifiedTitlebar, isEnabled: true)
                    }
                    .padding(.top, BrevSpacing.sm)
                }
                .brevFont(.caption)

                if reduceTransparency {
                    SettingsInfoCallout(symbolName: "accessibility",
                                        message: String(
                                            localized: "macOS Reduce Transparency is enabled. Backgrounds stay solid until it is turned off in System Settings.",
                                            bundle: .module
                                        ), tone: .warning)
                }
            }
        }
    }

    private func binding<Value>(_ path: WritableKeyPath<WindowAppearancePreferences, Value>) -> Binding<Value> {
        Binding(get: { preferences[keyPath: path] }, set: { preferences[keyPath: path] = $0; onChange() })
    }

    private func opacityControl(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            HStack {
                Text(verbatim: title).brevFont(.subheadline).id(title)
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded()))% opaque", bundle: .module)
                    .brevFont(.caption).monospacedDigit().foregroundStyle(theme.textSecondary.color)
            }
            Slider(value: value, in: range)
                .accessibilityLabel(title)
                .accessibilityValue(String(localized: "\(Int((value.wrappedValue * 100).rounded()))% opaque", bundle: .module))
            HStack {
                Text("More transparent", bundle: .module)
                Spacer()
                Text("Fully opaque", bundle: .module)
            }
            .brevFont(.caption).foregroundStyle(theme.textSecondary.color)
        }
    }
}

private struct WindowTransparencyPreview: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let preferences: WindowAppearancePreferences

    var body: some View {
        HStack(alignment: .top, spacing: BrevSpacing.lg) {
            previewWindow(label: String(localized: "Mail and Settings", bundle: .module), hasSidebar: true)
            previewWindow(label: String(localized: "Compose and messages", bundle: .module), hasSidebar: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Transparency preview", bundle: .module))
        .accessibilityValue(WindowTransparencySelection(preferences).detail)
    }

    private func previewWindow(label: String, hasSidebar: Bool) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            HStack(spacing: 0) {
                if hasSidebar { previewPane(role: .sidebar).frame(maxWidth: 70) }
                previewPane(role: hasSidebar ? .content : .utility)
            }
            .frame(height: 88)
            .background(LinearGradient(colors: [theme.info.color, theme.success.color, theme.warning.color],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: BrevRadius.md))
            .overlay(RoundedRectangle(cornerRadius: BrevRadius.md).stroke(theme.border.color, lineWidth: 1))
            Text(verbatim: label).brevFont(.caption).foregroundStyle(theme.textSecondary.color)
        }
        .frame(maxWidth: .infinity)
    }

    private func previewPane(role: WindowSurfaceRole) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            ForEach(0 ..< 3) { index in
                RoundedRectangle(cornerRadius: 2).fill(theme.textSecondary.color.opacity(0.6))
                    .frame(maxWidth: index == 2 ? 40 : .infinity).frame(height: 3)
            }
        }
        .padding(BrevSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background((role == .sidebar ? theme.bgSecondary.color : theme.bgPrimary.color)
            .opacity(preferences.surfaceFillOpacity(for: role, reduceTransparency: reduceTransparency) ?? 1))
    }
}
