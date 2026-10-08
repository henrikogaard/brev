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

/// One grid for every Settings pane: a fixed symbol column, one gap between
/// symbol and text, and a fixed trailing control slot. Group content indents
/// by exactly one symbol column, so row symbols sit under the group title and
/// stacked controls, previews and notes share the row text edge.
enum SettingsLayout {
    static let symbolWidth: CGFloat = 24
    static let symbolSpacing: CGFloat = BrevSpacing.sm
    static let symbolColumn: CGFloat = symbolWidth + symbolSpacing
    /// Trailing slot for popups; each popup hugs its value and ends on the
    /// same right edge as the switches above and below it.
    static let trailingControlWidth: CGFloat = 220

    /// Leading/trailing inset shared by pane headers, scope bars and content.
    /// iOS menu pickers pad their label inside the tappable button; offset it
    /// so the visible value lines up with neighbouring text and switches.
    /// Measured on iOS 27: ~16 pt trailing inline, ~18 pt leading when stacked
    /// (stacking only happens at accessibility sizes).
    static let menuButtonInset: CGFloat = {
        #if os(iOS)
        BrevSpacing.lg
        #else
        0
        #endif
    }()

    static let stackedMenuButtonInset: CGFloat = {
        #if os(iOS)
        BrevSpacing.lg + BrevSpacing.xxs
        #else
        0
        #endif
    }()

    static func paneHorizontalInset(_ density: MailboxListDensity) -> CGFloat {
        #if os(iOS)
        BrevSpacing.lg
        #else
        density.desktopSpacing(BrevSpacing.xxl)
        #endif
    }
}

enum SettingsCalloutTone {
    case info
    case success
    case warning

    var symbolColor: KeyPath<BrevTheme, BrevColor> {
        switch self {
        case .info: return \.info
        case .success: return \.success
        case .warning: return \.warning
        }
    }
}

/// A titled group of settings rows, drawn like System Settings: a plain
/// heading and footnote above one rounded inset surface holding the rows.
struct SettingsGroup<Content: View>: View {
    @AppStorage(MailboxViewPreferenceKey.listDensity) private var interfaceDensityRaw = MailboxListDensity.platformDefault
        .rawValue
    private var interfaceDensity: MailboxListDensity { MailboxListDensity(rawValue: interfaceDensityRaw) ?? .comfortable }
    @Environment(\.brevTheme) private var theme
    let title: String
    let subtitle: String
    /// Kept for call sites and search metadata; Apple's grouped headings
    /// carry no glyph, so only rows show symbols.
    let symbolName: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                Text(title)
                    .id(title)
                    .brevFont(.headline)
                    .foregroundStyle(theme.textPrimary.color)
                Text(subtitle)
                    .brevFont(.footnote)
                    .foregroundStyle(theme.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: interfaceDensity.desktopSpacing(BrevSpacing.md)) {
                content
            }
            .settingsGroupedSurface()
        }
        .padding(.bottom, interfaceDensity.desktopSpacing(BrevSpacing.xs))
    }
}

struct SettingsToggleRow: View {
    @Environment(\.brevTheme) private var theme
    let symbolName: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var isEnabled = true

    var body: some View {
        // A macOS switch hugs its label, so without the greedy frame each
        // row's switch landed just after its own text — every row at a
        // different x, and none lined up with the pickers beside them.
        Toggle(isOn: $isOn) {
            SettingsRowLabel(
                symbolName: symbolName,
                title: title,
                subtitle: subtitle
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .help(subtitle)
        .tint(theme.accent.color)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
    }
}

struct SettingsPickerRow<Selection: Hashable, Content: View>: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let symbolName: String
    let title: String
    let subtitle: String
    @Binding var selection: Selection
    var selectionTitle: String?
    @ViewBuilder let content: Content

    init(
        symbolName: String,
        title: String,
        subtitle: String,
        selection: Binding<Selection>,
        selectionTitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.symbolName = symbolName
        self.title = title
        self.subtitle = subtitle
        _selection = selection
        self.selectionTitle = selectionTitle
        self.content = content()
    }

    var body: some View {
        #if os(iOS)
        // On iPhone the label wraps beside a hugging menu, matching the
        // switch rows; only accessibility sizes stack the menu below.
        if dynamicTypeSize.isAccessibilitySize {
            stacked
        } else {
            HStack(alignment: .center, spacing: BrevSpacing.md) {
                label.frame(maxWidth: .infinity, alignment: .leading)
                picker.fixedSize()
                    .padding(.trailing, -SettingsLayout.menuButtonInset)
            }
        }
        #else
        ViewThatFits(in: .horizontal) {
            if !dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .center, spacing: BrevSpacing.md) {
                    label
                    Spacer(minLength: BrevSpacing.md)
                    picker
                        .frame(width: SettingsLayout.trailingControlWidth, alignment: .trailing)
                }
            }
            stacked
        }
        #endif
    }

    private var label: some View {
        SettingsRowLabel(symbolName: symbolName, title: title, subtitle: subtitle)
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            label
            picker
                .settingsStackedControl(isMenu: true)
        }
    }

    @ViewBuilder
    private var picker: some View {
        if let selectionTitle {
            pickerContent.accessibilityValue(selectionTitle)
        } else {
            pickerContent
        }
    }

    private var pickerContent: some View {
        ZStack(alignment: .trailing) {
            Picker(title, selection: $selection) {
                content
            }
            .labelsHidden()
            #if os(macOS)
                .fixedSize()
            #endif
                .opacity(selectionTitle == nil ? 1 : 0.01)

            if let selectionTitle {
                HStack(spacing: BrevSpacing.xs) {
                    Text(selectionTitle)
                        .brevFont(.subheadline)
                    Image(systemName: "chevron.up.chevron.down")
                        .brevFont(.caption)
                }
                .foregroundStyle(theme.textPrimary.color)
                .padding(.horizontal, BrevSpacing.sm)
                .padding(.vertical, BrevSpacing.xs)
                .brevQuietSurface(cornerRadius: BrevRadius.sm)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

struct SettingsSegmentedRow<Selection: Hashable, Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let symbolName: String
    let title: String
    let subtitle: String
    @Binding var selection: Selection
    var isEnabled = true
    @ViewBuilder let content: Content

    var body: some View {
        // Same trailing column as switches and popups when it fits; otherwise
        // the control drops under the title text, never under the symbol.
        ViewThatFits(in: .horizontal) {
            if !dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .center, spacing: BrevSpacing.md) {
                    label
                    Spacer(minLength: BrevSpacing.md)
                    picker.pickerStyle(.segmented).fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                    label
                    picker.pickerStyle(.segmented).fixedSize(horizontal: true, vertical: false)
                        .settingsStackedControl()
                }
            }
            VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                label
                picker.pickerStyle(.menu)
                    .settingsStackedControl(isMenu: true)
            }
        }
        .opacity(isEnabled ? 1 : 0.55)
    }

    private var label: some View {
        SettingsRowLabel(symbolName: symbolName, title: title, subtitle: subtitle)
    }

    private var picker: some View {
        Picker(title, selection: $selection) { content }
            .labelsHidden()
            .disabled(!isEnabled)
    }
}

struct SettingsInfoCallout: View {
    @Environment(\.brevTheme) private var theme
    let symbolName: String
    let message: String
    let tone: SettingsCalloutTone

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SettingsLayout.symbolSpacing) {
            SettingsSymbol(symbolName: symbolName, color: theme[keyPath: tone.symbolColor])
            Text(message)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(BrevSpacing.sm)
        // The frame must precede the surface: applied after it, the surface
        // still hugged the text and each note ended at a different x.
        .frame(maxWidth: .infinity, alignment: .leading)
        .brevQuietSurface(cornerRadius: BrevRadius.sm)
    }
}

struct SettingsRowLabel: View {
    @Environment(\.brevTheme) private var theme
    let symbolName: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SettingsLayout.symbolSpacing) {
            SettingsSymbol(symbolName: symbolName)
            // `.body` is the token's documented size for settings rows.
            // These were a step down at `.subheadline`, which left the
            // controls reading as secondary to the sidebar next to them.
            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                Text(title)
                    .id(title)
                    .brevFont(.body)
                    .foregroundStyle(theme.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .brevFont(.footnote)
                    .foregroundStyle(theme.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Fixed-width symbol column. Glyph widths vary ("Aa", "Abc", "a.magnify"),
/// so a minimum width let wide symbols push their titles off the shared edge.
struct SettingsSymbol: View {
    @Environment(\.brevTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var width = SettingsLayout.symbolWidth
    let symbolName: String
    var color: BrevColor?

    var body: some View {
        // Wide glyphs (Abc, signature) step down a scale to stay inside the
        // column instead of overlapping the title.
        ViewThatFits(in: .horizontal) {
            glyph.imageScale(.medium)
            glyph.imageScale(.small)
        }
        .frame(width: width, alignment: .center)
    }

    private var glyph: some View {
        Image(systemName: symbolName)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle((color ?? theme.textSecondary).color)
    }
}

extension View {
    /// Indents a control stacked below a row label to the label's text edge.
    /// - Parameter isMenu: Offsets the iOS menu button's internal label padding.
    func settingsStackedControl(isMenu: Bool = false) -> some View {
        modifier(SettingsStackedControl(isMenu: isMenu))
    }
}

private struct SettingsStackedControl: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var symbolWidth = SettingsLayout.symbolWidth
    let isMenu: Bool

    func body(content: Content) -> some View {
        content
            .padding(
                .leading,
                symbolWidth + SettingsLayout.symbolSpacing - (isMenu ? SettingsLayout.stackedMenuButtonInset : 0)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// The rounded inset surface every Settings group draws its rows on.
    func settingsGroupedSurface() -> some View {
        padding(.horizontal, BrevSpacing.md)
            .padding(.vertical, BrevSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .brevQuietSurface(cornerRadius: BrevRadius.md)
    }
}
