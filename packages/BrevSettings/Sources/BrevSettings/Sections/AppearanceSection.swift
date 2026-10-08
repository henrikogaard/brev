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
    @State private var showsWindowDetails = false
    @Environment(\.settingsSearchTarget) private var searchTarget
    @Environment(\.brevTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(AppearancePreferenceKey.transparentMainTitlebar)
    private var transparentMainTitlebar = true
    @Binding var activeTheme: BrevTheme
    @Binding var activeAppIcon: AppIconVariant
    @State private var themeSettings: AppearanceThemeSettings
    @State private var windowAppearance: WindowAppearancePreferences
    @State private var mailboxSettings: MailboxViewSettings
    @State private var isThemePickerPresented = false
    @State private var isResetConfirmationPresented = false

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
        _mailboxSettings = State(initialValue: settingsStore.mailboxViewSettings())
    }

    var body: some View {
        SectionScaffold(
            title: String(localized: "Appearance", bundle: .module),
            subtitle: appearanceSubtitle
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.xl) {
                #if os(macOS)
                DesktopInterfaceSettings(settingsStore: settingsStore)
                #endif
                themeGroup
                #if os(iOS)
                SettingsMailPreview(settings: mailboxSettings)
                #endif
                if appearanceControls.showsWindowTranslucencyControls {
                    WindowAppearanceControls(
                        preferences: $windowAppearance,
                        unifiedTitlebar: $transparentMainTitlebar,
                        showsAdvanced: $showsWindowDetails,
                        onChange: { settingsStore.save(windowAppearance) }
                    )
                }

                SettingsGroup(
                    title: String(localized: "App icon", bundle: .module),
                    subtitle: appIconSubtitle,
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

                resetRow
            }
        }
        .defaultAppStorage(settingsStore.defaults)
        .brevDesktopSizing()
        .onChange(of: searchTarget, initial: true) { _, target in
            if target != nil { showsWindowDetails = true }
        }
        .onChange(of: colorScheme) { _, _ in
            applyResolvedTheme()
        }
        .onChange(of: colorSchemeContrast) { _, _ in applyResolvedTheme() }
        .onReceive(NotificationCenter.default.publisher(for: .brevAppearanceThemeSettingsDidChange)) { _ in
            themeSettings = settingsStore.appearanceThemeSettings()
        }
        .sheet(isPresented: $isThemePickerPresented) {
            ThemePickerSheet(
                themeSettings: $themeSettings,
                initialMode: themeSettings.resolvedThemeMode(prefersDark: prefersDarkTheme),
                onSettingsChanged: persistAndApplyThemeSettings
            )
        }
    }

    private var resetRow: some View {
        HStack {
            Spacer(minLength: 0)
            Button(String(localized: "Reset to Defaults", bundle: .module)) {
                isResetConfirmationPresented = true
            }
            #if os(iOS)
            .buttonStyle(.bordered)
            #endif
            .help(resetMessage)
            .confirmationDialog(
                String(localized: "Reset appearance to defaults?", bundle: .module),
                isPresented: $isResetConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button(String(localized: "Reset Appearance", bundle: .module), role: .destructive) {
                    resetToDefaults()
                }
                Button(String(localized: "Cancel", bundle: .module), role: .cancel) {}
            } message: {
                Text(resetMessage)
            }
        }
    }

    private var resetMessage: String {
        #if os(macOS)
        String(
            localized: "Restores the default themes, accent, window style, text size, density, and app icon.",
            bundle: .module
        )
        #else
        String(localized: "Restores the default themes, accent, and app icon.", bundle: .module)
        #endif
    }

    private func resetToDefaults() {
        AppearanceReset.apply(to: settingsStore)
        themeSettings = settingsStore.appearanceThemeSettings()
        windowAppearance = settingsStore.windowAppearancePreferences()
        mailboxSettings = settingsStore.mailboxViewSettings()
        transparentMainTitlebar = true
        activeAppIcon = AppIconVariant.defaultVariant
        applyResolvedTheme()
        NotificationCenter.default.post(name: .brevAppearanceThemeSettingsDidChange, object: nil)
    }

    private var appearanceSubtitle: String {
        #if os(macOS)
        String(localized: "Choose Brev's colors, window style, and Dock icon.", bundle: .module)
        #else
        String(localized: "Choose Brev's colors and app icon.", bundle: .module)
        #endif
    }

    private var appIconSubtitle: String {
        #if os(macOS)
        String(localized: "Select the logo style used by the app and Dock.", bundle: .module)
        #else
        String(localized: "Select the icon shown on your Home Screen.", bundle: .module)
        #endif
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

                themePairRow

                accentColorRow
            }
        }
    }

    @ViewBuilder
    private var accentColorRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                accentColorLabel
                accentColorControls
                    .settingsStackedControl(isMenu: true)
            }
        } else {
            #if os(iOS)
            HStack(alignment: .center, spacing: BrevSpacing.md) {
                accentColorLabel.frame(maxWidth: .infinity, alignment: .leading)
                accentColorControls.fixedSize()
                    .padding(.trailing, -SettingsLayout.menuButtonInset)
            }
            #else
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: BrevSpacing.md) {
                    accentColorLabel
                    Spacer(minLength: BrevSpacing.md)
                    accentColorControls
                }

                VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                    accentColorLabel
                    accentColorControls
                        .settingsStackedControl(isMenu: true)
                }
            }
            #endif
        }
    }

    private var accentColorLabel: some View {
        SettingsRowLabel(
            symbolName: "paintbrush.pointed",
            title: String(localized: "Accent", bundle: .module),
            subtitle: accentColorSubtitle
        )
        .id(String(localized: "Accent color", bundle: .module))
    }

    private var accentColorControls: some View {
        VStack(alignment: .trailing, spacing: BrevSpacing.sm) {
            Picker(String(localized: "Accent source", bundle: .module), selection: accentSourceBinding) {
                ForEach(AppearanceAccentSource.availableSources) { source in
                    Text(source.title).tag(source)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .id(String(localized: "Accent source", bundle: .module))

            if themeSettings.accentSource == .custom {
                ColorPicker(
                    String(localized: "Accent color", bundle: .module),
                    selection: accentColorBinding,
                    supportsOpacity: false
                )
                .fixedSize(horizontal: false, vertical: true)
            }

            if themeSettings.accentSource != .theme {
                Button(String(localized: "Follow theme", bundle: .module)) {
                    updateThemeSettings { $0.accentSource = .theme }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(theme.textPrimary.color)
            }
        }
    }

    private var accentColorSubtitle: String {
        switch themeSettings.accentSource {
        case .theme:
            String(localized: "Follows \(effectiveBaseTheme.name) and changes with your theme.", bundle: .module)
        case .system:
            #if os(macOS)
            String(localized: "Uses the macOS accent, adjusted for readable controls.", bundle: .module)
            #else
            String(localized: "System accent is available on Mac. This device uses the theme accent.", bundle: .module)
            #endif
        case .custom:
            String(localized: "Your color is saved unchanged. Controls adjust for contrast when needed.", bundle: .module)
        }
    }

    private var accentSourceBinding: Binding<AppearanceAccentSource> {
        Binding(
            get: {
                #if os(iOS)
                themeSettings.accentSource == .system ? .theme : themeSettings.accentSource
                #else
                themeSettings.accentSource
                #endif
            },
            set: { source in
                updateThemeSettings {
                    if source == .custom, $0.accentHex == nil {
                        $0.accentHex = activeTheme.accent.hex
                    }
                    $0.accentSource = source
                }
            }
        )
    }

    private var effectiveBaseTheme: BrevTheme {
        themeSettings.selectedTheme(
            for: themeSettings.resolvedThemeMode(prefersDark: prefersDarkTheme)
        )
    }

    @ViewBuilder
    private var themePairRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                themePairLabel
                VStack(alignment: .leading, spacing: BrevSpacing.md) {
                    selectedThemePair
                    chooseThemesButton
                }
                .settingsStackedControl()
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: BrevSpacing.md) {
                    themePairLabel
                    Spacer(minLength: BrevSpacing.md)
                    selectedThemePair
                    chooseThemesButton
                }

                VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                    themePairLabel
                    HStack(spacing: BrevSpacing.md) {
                        selectedThemePair
                        chooseThemesButton
                    }
                    .settingsStackedControl()
                }
            }
        }
    }

    private var themePairLabel: some View {
        SettingsRowLabel(
            symbolName: "swatchpalette",
            title: String(localized: "Themes", bundle: .module),
            subtitle: String(localized: "Your saved light and dark pair.", bundle: .module)
        )
    }

    private var selectedThemePair: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: BrevSpacing.sm))
            : AnyLayout(HStackLayout(spacing: BrevSpacing.md))
        return layout {
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
                updateThemeSettings {
                    $0.accentHex = AccentColorCodec.hex(from: color)
                    $0.accentSource = .custom
                }
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
            prefersDark: prefersDarkTheme,
            increasedContrast: colorSchemeContrast == .increased
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
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(label) theme, \(candidate.name)", bundle: .module))
    }
}

private struct ThemePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.brevTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var themeSettings: AppearanceThemeSettings
    @State private var selectedMode: BrevThemeMode
    let onSettingsChanged: () -> Void

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 168, maximum: 240), spacing: BrevSpacing.sm)]
    }

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
                        .foregroundStyle(theme.textPrimary.color)
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

enum AppearancePreferenceKey {
    static let transparentMainTitlebar = "window.transparentMainTitlebar"
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
                        .fixedSize(horizontal: false, vertical: true)
                    Text(variant.subtitle)
                        .brevFont(.caption)
                        .foregroundStyle(theme.textTertiary.color)
                        .fixedSize(horizontal: false, vertical: true)
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
                    .fixedSize(horizontal: false, vertical: true)
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

#if os(macOS)
/// One control pair for desktop content and interface sizing, backed by existing preferences.
struct DesktopInterfaceSettings: View {
    @AppStorage private var textSizeRaw: String
    @AppStorage private var densityRaw: String
    private let settingsStore: SettingsPersistenceStore

    init(settingsStore: SettingsPersistenceStore = .standard) {
        self.settingsStore = settingsStore
        _textSizeRaw = AppStorage(wrappedValue: MailboxTextSize.medium.rawValue,
                                  MailboxViewPreferenceKey.textSize, store: settingsStore.defaults)
        _densityRaw = AppStorage(wrappedValue: MailboxListDensity.platformDefault.rawValue,
                                 MailboxViewPreferenceKey.listDensity, store: settingsStore.defaults)
    }

    var body: some View {
        SettingsGroup(
            title: String(localized: "Text and spacing", bundle: .module),
            subtitle: String(localized: "Customize the whole desktop app without changing message formatting.", bundle: .module),
            symbolName: "textformat.size"
        ) {
            SettingsSegmentedRow(
                symbolName: "textformat.size",
                title: String(localized: "Text size", bundle: .module),
                subtitle: String(localized: "Applies to sidebars, lists, reading, composing, and settings.", bundle: .module),
                selection: $textSizeRaw
            ) {
                ForEach(MailboxTextSize.allCases) { size in
                    Text(size.title).tag(size.rawValue)
                }
            }
            SettingsSegmentedRow(
                symbolName: "rectangle.compress.vertical",
                title: String(localized: "Interface density", bundle: .module),
                subtitle: String(
                    localized: "Adjust spacing in sidebars, mail views, and settings independently of text size.",
                    bundle: .module
                ),
                selection: $densityRaw
            ) {
                ForEach(MailboxListDensity.allCases) { density in
                    Text(density.title).tag(density.rawValue)
                }
            }
            SettingsMailPreview(settings: previewSettings)
        }
    }

    private var previewSettings: MailboxViewSettings {
        var settings = settingsStore.mailboxViewSettings()
        settings.textSize = MailboxTextSize(rawValue: textSizeRaw) ?? .medium
        settings.listDensity = MailboxListDensity(rawValue: densityRaw) ?? .comfortable
        return settings
    }
}
#endif

/// Restores every preference the Appearance pane owns to its shipped default.
enum AppearanceReset {
    static func apply(to store: SettingsPersistenceStore) {
        store.save(AppearanceThemeSettings.defaults)
        store.save(WindowAppearancePreferences.defaults)
        store.save(AppIconVariant.defaultVariant)
        store.defaults.set(true, forKey: AppearancePreferenceKey.transparentMainTitlebar)
        #if os(macOS)
        store.defaults.removeObject(forKey: MailboxViewPreferenceKey.textSize)
        store.defaults.removeObject(forKey: MailboxViewPreferenceKey.listDensity)
        #endif
    }
}
