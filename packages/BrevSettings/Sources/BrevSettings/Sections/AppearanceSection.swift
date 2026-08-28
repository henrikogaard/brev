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

struct AppearanceSection: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppearancePreferenceKey.transparentMainTitlebar)
    private var transparentMainTitlebar = true
    @Binding var activeTheme: BrevTheme
    @Binding var activeAppIcon: AppIconVariant
    @State private var themeSettings: AppearanceThemeSettings
    @State private var windowAppearance: WindowAppearancePreferences
    @State private var isThemePickerPresented = false

    private let appearanceControls = AppearanceControlsPolicy.current
    private let settingsStore: SettingsPersistenceStore

    private let iconColumns = [
        GridItem(.adaptive(minimum: 112, maximum: 132), spacing: BrevSpacing.sm)
    ]
    private var prefersDarkTheme: Bool {
        colorScheme == .dark
    }

    init(
        activeTheme: Binding<BrevTheme>,
        activeAppIcon: Binding<AppIconVariant>,
        settingsStore: SettingsPersistenceStore = .standard
    ) {
        _activeTheme = activeTheme
        _activeAppIcon = activeAppIcon
        self.settingsStore = settingsStore
        _themeSettings = State(initialValue: settingsStore.appearanceThemeSettings())
        _windowAppearance = State(initialValue: settingsStore.windowAppearancePreferences())
    }

    var body: some View {
        SectionScaffold(
            title: String(localized: "Appearance", bundle: .module),
            subtitle: String(localized: "Choose Brev's colors, window style, and Dock icon.", bundle: .module)
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.xl) {
                themeGroup
                if appearanceControls.showsWindowTranslucencyControls {
                    SettingsGroup(
                        title: String(localized: "Window design", bundle: .module),
                        subtitle: String(localized: "Choose how transparent Brev's window surfaces feel.", bundle: .module),
                        symbolName: "macwindow"
                    ) {
                        VStack(alignment: .leading, spacing: BrevSpacing.md) {
                            SettingsSegmentedRow(
                                symbolName: "circle.lefthalf.filled",
                                title: String(localized: "Style", bundle: .module),
                                subtitle: windowAppearance.mode.subtitle,
                                selection: windowAppearanceBinding(for: \.mode)
                            ) {
                                ForEach(WindowTranslucencyMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }

                            SettingsPickerRow(
                                symbolName: "rectangle.3.group",
                                title: String(localized: "Apply to", bundle: .module),
                                subtitle: windowAppearance.scope.subtitle,
                                selection: windowAppearanceBinding(for: \.scope)
                            ) {
                                ForEach(WindowTranslucencyScope.allCases) { scope in
                                    Text(scope.title).tag(scope)
                                }
                            }

                            if appearanceControls.showsTransparentTitleBarToggle {
                                SettingsToggleRow(
                                    symbolName: "macwindow.on.rectangle",
                                    title: String(localized: "Unified title bar", bundle: .module),
                                    subtitle: String(
                                        localized: "Extends the current surface styling into the main and Settings title bars.",
                                        bundle: .module
                                    ),
                                    isOn: $transparentMainTitlebar,
                                    isEnabled: true
                                )
                            }

                            windowOpacityControls

                            WindowMaterialPreview(preferences: windowAppearance)

                            SettingsInfoCallout(
                                symbolName: reduceTransparency ? "accessibility" : "sparkles",
                                message: windowDesignStatusText,
                                tone: reduceTransparency ? .warning : .info
                            )
                        }
                    }
                }

                SettingsGroup(
                    title: String(localized: "App icon", bundle: .module),
                    subtitle: String(localized: "Select the logo style used by the app and Dock.", bundle: .module),
                    symbolName: "app.badge"
                ) {
                    LazyVGrid(columns: iconColumns, alignment: .leading, spacing: BrevSpacing.sm) {
                        ForEach(AppIconVariant.allCases) { candidate in
                            AppIconVariantButton(
                                variant: candidate,
                                isSelected: candidate == activeAppIcon
                            ) {
                                activeAppIcon = candidate
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: colorScheme) { _, _ in
            applyResolvedTheme()
        }
        .sheet(isPresented: $isThemePickerPresented) {
            ThemePickerSheet(
                themeSettings: $themeSettings,
                initialMode: themeSettings.resolvedThemeMode(prefersDark: prefersDarkTheme),
                onSettingsChanged: persistAndApplyThemeSettings
            )
        }
    }

    private var themeGroup: some View {
        SettingsGroup(
            title: String(localized: "Color and themes", bundle: .module),
            subtitle: String(localized: "Choose how Brev follows your system and colors its controls.", bundle: .module),
            symbolName: "paintpalette"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                SettingsSegmentedRow(
                    symbolName: "circle.lefthalf.filled",
                    title: String(localized: "Mode", bundle: .module),
                    subtitle: themeSettings.mode.subtitle,
                    selection: themeSettingsBinding(for: \.mode)
                ) {
                    ForEach(AppearanceThemeMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                accentColorRow

                themePairRow
            }
        }
    }

    private var accentColorRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: BrevSpacing.md) {
                accentColorLabel
                Spacer(minLength: BrevSpacing.md)
                accentColorControls
            }

            VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                accentColorLabel
                accentColorControls
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var accentColorLabel: some View {
        HStack(alignment: .top, spacing: BrevSpacing.sm) {
            Image(systemName: "paintbrush.pointed")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.accent.color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                Text("Accent", bundle: .module)
                    .brevFont(.subheadline)
                    .foregroundStyle(theme.textPrimary.color)
                Text(accentColorSubtitle)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var accentColorControls: some View {
        HStack(spacing: BrevSpacing.sm) {
            Text(themeSettings.accentHex == nil ? String(localized: "Theme", bundle: .module) : String(
                localized: "Custom",
                bundle: .module
            ))
            .brevFont(.caption)
            .foregroundStyle(theme.textTertiary.color)

            ColorPicker(
                String(localized: "Accent color", bundle: .module),
                selection: accentColorBinding,
                supportsOpacity: false
            )
            .labelsHidden()
            .accessibilityLabel(String(localized: "Accent color", bundle: .module))

            if themeSettings.accentHex != nil {
                Button(String(localized: "Follow theme", bundle: .module)) {
                    updateThemeSettings { $0.accentHex = nil }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(theme.accent.color)
            }
        }
    }

    private var accentColorSubtitle: String {
        themeSettings.accentHex == nil
            ? String(localized: "Follows \(effectiveBaseTheme.name) and changes with your theme.", bundle: .module)
            : String(localized: "Overrides the accent supplied by each theme.", bundle: .module)
    }

    private var effectiveBaseTheme: BrevTheme {
        themeSettings.selectedTheme(
            for: themeSettings.resolvedThemeMode(prefersDark: prefersDarkTheme)
        )
    }

    private var themePairRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: BrevSpacing.md) {
                themePairLabel
                Spacer(minLength: BrevSpacing.md)
                selectedThemePair
                chooseThemesButton
            }

            VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                themePairLabel
                HStack(spacing: BrevSpacing.sm) {
                    selectedThemePair
                    Spacer(minLength: BrevSpacing.sm)
                    chooseThemesButton
                }
            }
        }
    }

    private var themePairLabel: some View {
        HStack(alignment: .top, spacing: BrevSpacing.sm) {
            Image(systemName: "swatchpalette")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.accent.color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                Text("Themes", bundle: .module)
                    .brevFont(.subheadline)
                    .foregroundStyle(theme.textPrimary.color)
                Text("Your saved light and dark pair.", bundle: .module)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
            }
        }
    }

    private var selectedThemePair: some View {
        HStack(spacing: BrevSpacing.md) {
            SelectedThemeSummary(
                label: String(localized: "Light", bundle: .module),
                candidate: themeSettings.selectedTheme(for: .light)
            )
            SelectedThemeSummary(
                label: String(localized: "Dark", bundle: .module),
                candidate: themeSettings.selectedTheme(for: .dark)
            )
        }
    }

    private var chooseThemesButton: some View {
        Button(String(localized: "Choose…", bundle: .module)) {
            isThemePickerPresented = true
        }
        .accessibilityLabel(String(localized: "Choose light and dark themes", bundle: .module))
    }

    private var windowDesignStatusText: String {
        if reduceTransparency {
            return String(
                localized: "macOS Reduce Transparency is enabled, so Brev keeps the selected window layout with opaque surfaces.",
                bundle: .module
            )
        }
        #if os(macOS)
        if !transparentMainTitlebar {
            return String(
                localized: "Main and Settings windows use standard title bars until Unified title bar is enabled.",
                bundle: .module
            )
        }
        #endif
        if windowAppearance.mode == .solid {
            return String(
                localized: "Solid keeps Subtle's unified window structure with fully opaque themed surfaces.",
                bundle: .module
            )
        }
        if windowAppearance.mode == .glass {
            return String(
                localized: "Glass uses Liquid Glass where available with separate pane and sidebar opacity layers for readability.",
                bundle: .module
            )
        }
        return String(
            localized: "Material effects apply to mail and Settings chrome; pane and sidebar opacity keep content readable.",
            bundle: .module
        )
    }

    private var windowOpacityControls: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.md) {
            opacityControl(
                title: String(localized: "Pane opacity", bundle: .module),
                subtitle: String(localized: "Controls mail, settings, cards, and reading surfaces.", bundle: .module),
                symbolName: "rectangle.split.3x1",
                value: windowAppearanceBinding(for: \.surfaceOpacity),
                range: WindowAppearancePreferences.surfaceOpacityRange
            )

            opacityControl(
                title: String(localized: "Sidebar opacity", bundle: .module),
                subtitle: String(localized: "Controls folder and settings sidebars separately.", bundle: .module),
                symbolName: "sidebar.leading",
                value: windowAppearanceBinding(for: \.sidebarOpacity),
                range: WindowAppearancePreferences.sidebarOpacityRange
            )

            SettingsPickerRow(
                symbolName: "doc.richtext",
                title: String(localized: "Message content", bundle: .module),
                subtitle: windowAppearance.messageContentOpacityMode.subtitle,
                selection: windowAppearanceBinding(for: \.messageContentOpacityMode),
                selectionTitle: windowAppearance.messageContentOpacityMode.title
            ) {
                ForEach(MessageContentOpacityMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            if windowAppearance.messageContentOpacityMode == .custom {
                opacityControl(
                    title: String(localized: "Message opacity", bundle: .module),
                    subtitle: String(localized: "Controls only the surface directly behind a message.", bundle: .module),
                    symbolName: "text.document",
                    value: windowAppearanceBinding(for: \.messageContentOpacity),
                    range: WindowAppearancePreferences.messageContentOpacityRange
                )
            }
        }
        .disabled(windowAppearance.mode == .solid || reduceTransparency)
        .opacity(windowAppearance.mode == .solid || reduceTransparency ? 0.55 : 1)
    }

    private func opacityControl(
        title: String,
        subtitle: String,
        symbolName: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            HStack(alignment: .top, spacing: BrevSpacing.sm) {
                Image(systemName: symbolName)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(theme.accent.color)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                    Text(title)
                        .brevFont(.subheadline)
                        .foregroundStyle(theme.textPrimary.color)
                    Text(subtitle)
                        .brevFont(.caption)
                        .foregroundStyle(theme.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: BrevSpacing.md)

                Text(opacityValueLabel(value.wrappedValue))
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                    .monospacedDigit()
            }

            Slider(
                value: value,
                in: range,
                step: 0.01
            )
            .tint(theme.accent.color)
            .accessibilityLabel(title)
            .accessibilityValue(opacityValueLabel(value.wrappedValue))
        }
    }

    private func opacityValueLabel(_ value: Double) -> String {
        value >= 1 ? String(localized: "Opaque", bundle: .module) : String(
            localized: "\(Int((value * 100).rounded()))%",
            bundle: .module
        )
    }

    private func windowAppearanceBinding<Value>(
        for keyPath: WritableKeyPath<WindowAppearancePreferences, Value>
    ) -> Binding<Value> {
        Binding(
            get: { windowAppearance[keyPath: keyPath] },
            set: { newValue in
                windowAppearance[keyPath: keyPath] = newValue
                settingsStore.save(windowAppearance)
            }
        )
    }

    private func themeSettingsBinding<Value>(
        for keyPath: WritableKeyPath<AppearanceThemeSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { themeSettings[keyPath: keyPath] },
            set: { newValue in
                updateThemeSettings { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private var accentColorBinding: Binding<Color> {
        Binding(
            get: {
                AccentColorCodec.color(from: themeSettings.accentHex ?? activeTheme.accent.hex)
            },
            set: { color in
                updateThemeSettings { $0.accentHex = AccentColorCodec.hex(from: color) }
            }
        )
    }

    private func updateThemeSettings(
        _ mutate: (inout AppearanceThemeSettings) -> Void
    ) {
        mutate(&themeSettings)
        persistAndApplyThemeSettings()
    }

    private func persistAndApplyThemeSettings() {
        settingsStore.save(themeSettings)
        applyResolvedTheme()
    }

    private func applyResolvedTheme() {
        activeTheme = themeSettings.resolvedTheme(
            in: BrevTheme.brevBuiltIns,
            prefersDark: prefersDarkTheme
        )
    }
}

private struct SelectedThemeSummary: View {
    @Environment(\.brevTheme) private var theme
    let label: String
    let candidate: BrevTheme

    var body: some View {
        HStack(spacing: BrevSpacing.xs) {
            ThemeSwatch(candidate: candidate)
                .frame(width: 28, height: 20)

            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                Text(label)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textTertiary.color)
                Text(candidate.name)
                    .brevFont(.footnote)
                    .foregroundStyle(theme.textPrimary.color)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(label) theme, \(candidate.name)", bundle: .module))
    }
}

private struct ThemePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.brevTheme) private var theme
    @Binding var themeSettings: AppearanceThemeSettings
    @State private var selectedMode: BrevThemeMode
    let onSettingsChanged: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 168, maximum: 240), spacing: BrevSpacing.sm)
    ]

    init(
        themeSettings: Binding<AppearanceThemeSettings>,
        initialMode: BrevThemeMode,
        onSettingsChanged: @escaping () -> Void
    ) {
        _themeSettings = themeSettings
        _selectedMode = State(initialValue: initialMode)
        self.onSettingsChanged = onSettingsChanged
    }

    private var candidates: [BrevTheme] {
        BrevTheme.brevBuiltIns.filter { $0.mode == selectedMode }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                Text(
                    "Pick one light and one dark palette. Brev uses the appropriate theme for the selected mode.",
                    bundle: .module
                )
                .brevFont(.subheadline)
                .foregroundStyle(theme.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)

                Picker(String(localized: "Theme appearance", bundle: .module), selection: $selectedMode) {
                    Text("Light", bundle: .module).tag(BrevThemeMode.light)
                    Text("Dark", bundle: .module).tag(BrevThemeMode.dark)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: BrevSpacing.sm) {
                        ForEach(candidates) { candidate in
                            Button {
                                themeSettings.selectTheme(candidate)
                                onSettingsChanged()
                            } label: {
                                ThemeTile(
                                    candidate: candidate,
                                    isSelected: themeSettings.selectedTheme(for: selectedMode).id == candidate.id
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(
                                localized: "\(candidate.name), \(selectedMode == .dark ? "dark" : "light") theme",
                                bundle: .module
                            ))
                            .accessibilityValue(
                                themeSettings.selectedTheme(for: selectedMode).id == candidate.id
                                    ? String(localized: "Selected", bundle: .module)
                                    : ""
                            )
                        }
                    }
                }
            }
            .padding(BrevSpacing.lg)
            .navigationTitle(String(localized: "Choose themes", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done", bundle: .module)) { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 620, minHeight: 520)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }
}

private enum AppearancePreferenceKey {
    static let transparentMainTitlebar = "window.transparentMainTitlebar"
}

private struct WindowMaterialPreview: View {
    @Environment(\.brevTheme) private var theme
    let preferences: WindowAppearancePreferences

    var body: some View {
        HStack(spacing: BrevSpacing.sm) {
            previewSwatch(role: .sidebar, label: String(localized: "Sidebar", bundle: .module))
            previewSwatch(role: .content, label: String(localized: "Pane", bundle: .module))
            previewSwatch(role: .messageContent, label: String(localized: "Message", bundle: .module))
            previewSwatch(role: .settings, label: String(localized: "Settings", bundle: .module))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func previewSwatch(role: WindowSurfaceRole, label: String) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            RoundedRectangle(cornerRadius: BrevRadius.sm)
                .fill(previewFill(for: role))
                .overlay {
                    RoundedRectangle(cornerRadius: BrevRadius.sm)
                        .stroke(theme.border.color, lineWidth: 1)
                }
                .frame(width: 56, height: 34)
            Text(label)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
        }
    }

    private func previewFill(for role: WindowSurfaceRole) -> Color {
        let baseColor = switch role {
        case .sidebar, .messageContent, .card:
            theme.bgSecondary.color
        case .mainWindow, .content, .settings, .utility:
            theme.bgPrimary.color
        }
        guard let opacity = preferences.surfaceFillOpacity(
            for: role,
            reduceTransparency: false
        ) else {
            return Color.clear
        }
        return baseColor.opacity(opacity)
    }
}

private struct AppIconVariantButton: View {
    @Environment(\.brevTheme) private var theme
    let variant: AppIconVariant
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                ZStack(alignment: .topTrailing) {
                    Image(variant.previewAssetName, bundle: .main)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: BrevRadius.lg))

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(theme.accent.color)
                            .padding(BrevSpacing.xs)
                    }
                }
                .aspectRatio(1, contentMode: .fit)

                VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                    Text(variant.title)
                        .brevFont(.footnote)
                        .foregroundStyle(theme.textPrimary.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(variant.subtitle)
                        .brevFont(.caption)
                        .foregroundStyle(theme.textTertiary.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(BrevSpacing.sm)
            .background(isSelected ? theme.selection.color : theme.bgPrimary.color)
            .clipShape(RoundedRectangle(cornerRadius: BrevRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: BrevRadius.md)
                    .stroke(isSelected ? theme.accent.color : theme.border.color, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: BrevRadius.md))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "\(variant.title) app icon", bundle: .module))
    }
}

private struct ThemeTile: View {
    @Environment(\.brevTheme) private var theme
    let candidate: BrevTheme
    let isSelected: Bool

    var body: some View {
        HStack(spacing: BrevSpacing.sm) {
            ThemeSwatch(candidate: candidate)
                .frame(width: 34, height: 24)

            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                Text(candidate.name)
                    .brevFont(.footnote)
                    .foregroundStyle(theme.textPrimary.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(candidate.mode == .dark ? String(localized: "Dark", bundle: .module) : String(
                    localized: "Light",
                    bundle: .module
                ))
                .brevFont(.caption)
                .foregroundStyle(theme.textTertiary.color)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(theme.accent.color)
            }
        }
        .frame(minHeight: 50)
        .padding(.horizontal, BrevSpacing.sm)
        .padding(.vertical, BrevSpacing.sm)
        .background(isSelected ? theme.selection.color : theme.bgPrimary.color)
        .clipShape(RoundedRectangle(cornerRadius: BrevRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: BrevRadius.md)
                .stroke(isSelected ? theme.accent.color : theme.border.color, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: BrevRadius.md))
    }
}

private struct ThemeSwatch: View {
    let candidate: BrevTheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: BrevRadius.sm)
                .fill(candidate.bgPrimary.color)
            RoundedRectangle(cornerRadius: BrevRadius.sm)
                .stroke(candidate.accent.color, lineWidth: 2)
        }
    }
}
