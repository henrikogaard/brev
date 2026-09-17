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

import Foundation

// Brev-owned themes. Each is a single ColorScheme pinned palette; the
// system "follow appearance" pair defaults to monochrome light + dark.
//
// All hex values are sRGB. Lint rule `no_literal_colors_in_views`
// applies to *view* code, not to theme palettes — palettes are the
// only legitimate place colors are literal.

public extension BrevTheme {
    // MARK: - Brev Mono Light

    /// Neutral monochrome light theme. Default system-light variant.
    static let brevMonoLight = BrevTheme(
        id: "brev-mono-light",
        name: "Brev Mono Light",
        mode: .light,
        author: "Brev contributors",
        license: "MIT",
        bgPrimary: BrevColor("#FFFFFF"),
        bgSecondary: BrevColor("#F5F5F5"),
        bgTertiary: BrevColor("#EBEBEB"),
        textPrimary: BrevColor("#151515"),
        textSecondary: BrevColor("#505050"),
        textTertiary: BrevColor("#626262"),
        accent: BrevColor("#1F1F1F"),
        accentMuted: BrevColor("#6B6B6B"),
        success: BrevColor("#3B6B4C"),
        warning: BrevColor("#9A6514"),
        danger: BrevColor("#A23A2E"),
        info: BrevColor("#4E667D"),
        border: BrevColor("#D8D8D8"),
        separator: BrevColor("#E8E8E8"),
        selection: BrevColor("#E6E6E6"),
        avatarPalette: [
            BrevColor("#2B2B2B"),
            BrevColor("#3D3D3D"),
            BrevColor("#4F4F4F"),
            BrevColor("#616161"),
            BrevColor("#737373"),
            BrevColor("#555555"),
            BrevColor("#454545"),
            BrevColor("#676767")
        ]
    )

    // MARK: - Brev Mono Dark

    /// Neutral monochrome dark theme. Default system-dark variant.
    static let brevMonoDark = BrevTheme(
        id: "brev-mono-dark",
        name: "Brev Mono Dark",
        mode: .dark,
        author: "Brev contributors",
        license: "MIT",
        bgPrimary: BrevColor("#101010"),
        bgSecondary: BrevColor("#1A1A1A"),
        bgTertiary: BrevColor("#242424"),
        textPrimary: BrevColor("#F2F2F2"),
        textSecondary: BrevColor("#B8B8B8"),
        textTertiary: BrevColor("#A0A0A0"),
        accent: BrevColor("#E6E6E6"),
        accentMuted: BrevColor("#8A8A8A"),
        success: BrevColor("#7FB87D"),
        warning: BrevColor("#D6A24A"),
        danger: BrevColor("#D8806C"),
        info: BrevColor("#9BB2C7"),
        border: BrevColor("#333333"),
        separator: BrevColor("#262626"),
        selection: BrevColor("#2D2D2D"),
        avatarPalette: [
            BrevColor("#CFCFCF"),
            BrevColor("#BBBBBB"),
            BrevColor("#A7A7A7"),
            BrevColor("#939393"),
            BrevColor("#7F7F7F"),
            BrevColor("#D9D9D9"),
            BrevColor("#B1B1B1"),
            BrevColor("#999999")
        ]
    )

    // MARK: - Brev Paper (light)

    /// Warm off-white paper-stock light theme.
    static let brevPaper = BrevTheme(
        id: "brev-paper",
        name: "Brev Paper",
        mode: .light,
        author: "Brev contributors",
        license: "MIT",
        bgPrimary: BrevColor("#FBF7F0"),
        bgSecondary: BrevColor("#F2EDE3"),
        bgTertiary: BrevColor("#E8E1D2"),
        textPrimary: BrevColor("#1F1B16"),
        textSecondary: BrevColor("#5C5448"),
        textTertiary: BrevColor("#8E8676"),
        accent: BrevColor("#3D6792"),
        accentMuted: BrevColor("#7898B7"),
        success: BrevColor("#3B6B4C"),
        warning: BrevColor("#A66B16"),
        danger: BrevColor("#A23A2E"),
        info: BrevColor("#3D6792"),
        border: BrevColor("#D8D0BE"),
        separator: BrevColor("#E5DDCB"),
        selection: BrevColor("#DCE6EF"),
        avatarPalette: [
            BrevColor("#3B6B4C"),
            BrevColor("#A66B16"),
            BrevColor("#3D6792"),
            BrevColor("#7B4D8F"),
            BrevColor("#A23A2E"),
            BrevColor("#6B8E23"),
            BrevColor("#B58A2E"),
            BrevColor("#5C7D90")
        ]
    )

    // MARK: - Brev Forest (light)

    /// Deep forest-green light theme. Brand default — the cover-art
    /// theme on the landing page.
    static let brevForest = BrevTheme(
        id: "brev-forest",
        name: "Brev Forest",
        mode: .light,
        author: "Brev contributors",
        license: "MIT",
        bgPrimary: BrevColor("#F4F1EA"),
        bgSecondary: BrevColor("#E9E4D6"),
        bgTertiary: BrevColor("#DDD6C2"),
        textPrimary: BrevColor("#1A2A22"),
        textSecondary: BrevColor("#3E5A48"),
        textTertiary: BrevColor("#6E8779"),
        accent: BrevColor("#1F5236"),
        accentMuted: BrevColor("#6F9E83"),
        success: BrevColor("#2E7D4F"),
        warning: BrevColor("#9E6B12"),
        danger: BrevColor("#9A2D24"),
        info: BrevColor("#2F628A"),
        border: BrevColor("#CCC3AA"),
        separator: BrevColor("#DDD4BE"),
        selection: BrevColor("#CFE2D6"),
        avatarPalette: [
            BrevColor("#1F5236"),
            BrevColor("#9E6B12"),
            BrevColor("#2F628A"),
            BrevColor("#6E3F86"),
            BrevColor("#9A2D24"),
            BrevColor("#5A7A2A"),
            BrevColor("#A87A2F"),
            BrevColor("#4D7387")
        ]
    )

    // MARK: - Brev Slate (dark)

    /// Cool blue-slate dark theme.
    static let brevSlate = BrevTheme(
        id: "brev-slate",
        name: "Brev Slate",
        mode: .dark,
        author: "Brev contributors",
        license: "MIT",
        bgPrimary: BrevColor("#161A22"),
        bgSecondary: BrevColor("#1E232D"),
        bgTertiary: BrevColor("#262C38"),
        textPrimary: BrevColor("#E6E8EE"),
        textSecondary: BrevColor("#A8B0BD"),
        textTertiary: BrevColor("#727A89"),
        accent: BrevColor("#7AA2C9"),
        accentMuted: BrevColor("#506C84"),
        success: BrevColor("#7FB87D"),
        warning: BrevColor("#D6A24A"),
        danger: BrevColor("#D8806C"),
        info: BrevColor("#7AA2C9"),
        border: BrevColor("#2E3543"),
        separator: BrevColor("#262C38"),
        selection: BrevColor("#2C3B4F"),
        avatarPalette: [
            BrevColor("#7AA2C9"),
            BrevColor("#D6A24A"),
            BrevColor("#7FB87D"),
            BrevColor("#B687C9"),
            BrevColor("#D8806C"),
            BrevColor("#9BC376"),
            BrevColor("#C9A86E"),
            BrevColor("#86B0BD")
        ]
    )

    /// Stable list of built-in themes, in the order they appear in the
    /// settings picker.
    static let brevBuiltIns: [BrevTheme] = [
        .brevMonoLight, .brevMonoDark,
        .brevPaper, .brevForest, .brevSlate,
        .nord, .nordic,
        .gruvboxLight, .gruvboxDark,
        .solarizedLight, .solarizedDark,
        .catppuccinLatte, .catppuccinMocha,
        .tokyoNight,
        .rosePine,
        .forgeLight, .forgeDark,
        .oneDarkPro,
        .commandDark,
        .blurpleNight,
        .midnightTerminal,
        .cobaltNight,
        .codeCandyDark,
        .pearlLight,
        .evergreenNight,
        .inkWave,
        .mirageEmber,
        .oceanicDark,
        .amberTerminal,
        .owlBlue,
        .synthwaveDusk,
        .zenwrittenLight,
        .zenwrittenDark,
        .tender,
        .tomorrowDay,
        .tomorrowNight
    ]

    // MARK: - Nord (dark)

    /// Arctic, north-bluish color palette.
    static let nord = BrevTheme(
        id: "nord",
        name: "Nord",
        mode: .dark,
        author: "Arctic Ice Studio",
        license: "MIT",
        bgPrimary: BrevColor("#2E3440"),
        bgSecondary: BrevColor("#3B4252"),
        bgTertiary: BrevColor("#434C5E"),
        textPrimary: BrevColor("#ECEFF4"),
        textSecondary: BrevColor("#D8DEE9"),
        textTertiary: BrevColor("#7B88A1"),
        accent: BrevColor("#88C0D0"),
        accentMuted: BrevColor("#5E81AC"),
        success: BrevColor("#A3BE8C"),
        warning: BrevColor("#EBCB8B"),
        danger: BrevColor("#BF616A"),
        info: BrevColor("#81A1C1"),
        border: BrevColor("#434C5E"),
        separator: BrevColor("#3B4252"),
        selection: BrevColor("#434C5E"),
        avatarPalette: [
            BrevColor("#88C0D0"),
            BrevColor("#EBCB8B"),
            BrevColor("#A3BE8C"),
            BrevColor("#B48EAD"),
            BrevColor("#BF616A"),
            BrevColor("#81A1C1"),
            BrevColor("#D08770"),
            BrevColor("#5E81AC")
        ]
    )

    // MARK: - Nordic (dark)

    /// Warmer, deeper Nord-adjacent terminal palette from TerminalColors'
    /// Nordic Ghostty scheme.
    static let nordic = BrevTheme(
        id: "nordic",
        name: "Nordic",
        mode: .dark,
        author: "Nordic contributors",
        license: "MIT",
        bgPrimary: BrevColor("#242933"),
        bgSecondary: BrevColor("#1F242D"),
        bgTertiary: BrevColor("#3B4252"),
        textPrimary: BrevColor("#BBC3D4"),
        textSecondary: BrevColor("#AEB7C8"),
        textTertiary: BrevColor("#7F899C"),
        accent: BrevColor("#88C0D0"),
        accentMuted: BrevColor("#5E81AC"),
        success: BrevColor("#A3BE8C"),
        warning: BrevColor("#EBCB8B"),
        danger: BrevColor("#BF616A"),
        info: BrevColor("#88C0D0"),
        border: BrevColor("#3B4252"),
        separator: BrevColor("#2D3440"),
        selection: BrevColor("#1B1F26"),
        avatarPalette: [
            BrevColor("#88C0D0"),
            BrevColor("#EBCB8B"),
            BrevColor("#A3BE8C"),
            BrevColor("#B48EAD"),
            BrevColor("#BF616A"),
            BrevColor("#8FBCBB"),
            BrevColor("#BE9D88"),
            BrevColor("#BBC3D4")
        ]
    )

    // MARK: - Gruvbox Light

    /// Warm retro groove light palette.
    static let gruvboxLight = BrevTheme(
        id: "gruvbox-light",
        name: "Gruvbox Light",
        mode: .light,
        author: "morhetz",
        license: "MIT",
        bgPrimary: BrevColor("#FBF1C7"),
        bgSecondary: BrevColor("#EBDBB2"),
        bgTertiary: BrevColor("#D5C4A1"),
        textPrimary: BrevColor("#3C3836"),
        textSecondary: BrevColor("#504945"),
        textTertiary: BrevColor("#7C6F64"),
        accent: BrevColor("#458588"),
        accentMuted: BrevColor("#689D6A"),
        success: BrevColor("#689D6A"),
        warning: BrevColor("#D79921"),
        danger: BrevColor("#CC241D"),
        info: BrevColor("#458588"),
        border: BrevColor("#BDAE93"),
        separator: BrevColor("#D5C4A1"),
        selection: BrevColor("#D5C4A1"),
        avatarPalette: [
            BrevColor("#458588"),
            BrevColor("#D79921"),
            BrevColor("#689D6A"),
            BrevColor("#B16286"),
            BrevColor("#CC241D"),
            BrevColor("#98971A"),
            BrevColor("#D65D0E"),
            BrevColor("#7C6F64")
        ]
    )

    // MARK: - Gruvbox Dark

    /// Warm retro groove dark palette.
    static let gruvboxDark = BrevTheme(
        id: "gruvbox-dark",
        name: "Gruvbox Dark",
        mode: .dark,
        author: "morhetz",
        license: "MIT",
        bgPrimary: BrevColor("#282828"),
        bgSecondary: BrevColor("#3C3836"),
        bgTertiary: BrevColor("#504945"),
        textPrimary: BrevColor("#EBDBB2"),
        textSecondary: BrevColor("#D5C4A1"),
        textTertiary: BrevColor("#928374"),
        accent: BrevColor("#83A598"),
        accentMuted: BrevColor("#689D6A"),
        success: BrevColor("#B8BB26"),
        warning: BrevColor("#FABD2F"),
        danger: BrevColor("#FB4934"),
        info: BrevColor("#83A598"),
        border: BrevColor("#504945"),
        separator: BrevColor("#3C3836"),
        selection: BrevColor("#504945"),
        avatarPalette: [
            BrevColor("#83A598"),
            BrevColor("#FABD2F"),
            BrevColor("#B8BB26"),
            BrevColor("#D3869B"),
            BrevColor("#FB4934"),
            BrevColor("#8EC07C"),
            BrevColor("#FE8019"),
            BrevColor("#928374")
        ]
    )

    // MARK: - Solarized Light

    /// Precision light palette by Ethan Schoonover.
    static let solarizedLight = BrevTheme(
        id: "solarized-light",
        name: "Solarized Light",
        mode: .light,
        author: "Ethan Schoonover",
        license: "MIT",
        bgPrimary: BrevColor("#FDF6E3"),
        bgSecondary: BrevColor("#EEE8D5"),
        bgTertiary: BrevColor("#DDD6C1"),
        textPrimary: BrevColor("#586E75"),
        textSecondary: BrevColor("#657B83"),
        textTertiary: BrevColor("#93A1A1"),
        accent: BrevColor("#268BD2"),
        accentMuted: BrevColor("#2AA198"),
        success: BrevColor("#859900"),
        warning: BrevColor("#B58900"),
        danger: BrevColor("#DC322F"),
        info: BrevColor("#268BD2"),
        border: BrevColor("#D3CBB7"),
        separator: BrevColor("#EEE8D5"),
        selection: BrevColor("#EEE8D5"),
        avatarPalette: [
            BrevColor("#268BD2"),
            BrevColor("#B58900"),
            BrevColor("#859900"),
            BrevColor("#D33682"),
            BrevColor("#DC322F"),
            BrevColor("#2AA198"),
            BrevColor("#CB4B16"),
            BrevColor("#6C71C4")
        ]
    )

    // MARK: - Solarized Dark

    /// Precision dark palette by Ethan Schoonover.
    static let solarizedDark = BrevTheme(
        id: "solarized-dark",
        name: "Solarized Dark",
        mode: .dark,
        author: "Ethan Schoonover",
        license: "MIT",
        bgPrimary: BrevColor("#002B36"),
        bgSecondary: BrevColor("#073642"),
        bgTertiary: BrevColor("#0A4050"),
        textPrimary: BrevColor("#839496"),
        textSecondary: BrevColor("#93A1A1"),
        textTertiary: BrevColor("#586E75"),
        accent: BrevColor("#268BD2"),
        accentMuted: BrevColor("#2AA198"),
        success: BrevColor("#859900"),
        warning: BrevColor("#B58900"),
        danger: BrevColor("#DC322F"),
        info: BrevColor("#268BD2"),
        border: BrevColor("#073642"),
        separator: BrevColor("#073642"),
        selection: BrevColor("#073642"),
        avatarPalette: [
            BrevColor("#268BD2"),
            BrevColor("#B58900"),
            BrevColor("#859900"),
            BrevColor("#D33682"),
            BrevColor("#DC322F"),
            BrevColor("#2AA198"),
            BrevColor("#CB4B16"),
            BrevColor("#6C71C4")
        ]
    )

    // MARK: - Catppuccin Latte (light)

    /// Soothing pastel light palette from Catppuccin.
    static let catppuccinLatte = BrevTheme(
        id: "catppuccin-latte",
        name: "Catppuccin Latte",
        mode: .light,
        author: "Catppuccin",
        license: "MIT",
        bgPrimary: BrevColor("#EFF1F5"),
        bgSecondary: BrevColor("#E6E9EF"),
        bgTertiary: BrevColor("#DCE0E8"),
        textPrimary: BrevColor("#4C4F69"),
        textSecondary: BrevColor("#5C5F77"),
        textTertiary: BrevColor("#8C8FA1"),
        accent: BrevColor("#1E66F5"),
        accentMuted: BrevColor("#7287FD"),
        success: BrevColor("#40A02B"),
        warning: BrevColor("#DF8E1D"),
        danger: BrevColor("#D20F39"),
        info: BrevColor("#209FB5"),
        border: BrevColor("#CCD0DA"),
        separator: BrevColor("#DCE0E8"),
        selection: BrevColor("#DCE0E8"),
        avatarPalette: [
            BrevColor("#1E66F5"),
            BrevColor("#DF8E1D"),
            BrevColor("#40A02B"),
            BrevColor("#8839EF"),
            BrevColor("#D20F39"),
            BrevColor("#179299"),
            BrevColor("#FE640B"),
            BrevColor("#7287FD")
        ]
    )

    // MARK: - Catppuccin Mocha (dark)

    /// Soothing pastel dark palette from Catppuccin.
    static let catppuccinMocha = BrevTheme(
        id: "catppuccin-mocha",
        name: "Catppuccin Mocha",
        mode: .dark,
        author: "Catppuccin",
        license: "MIT",
        bgPrimary: BrevColor("#1E1E2E"),
        bgSecondary: BrevColor("#181825"),
        bgTertiary: BrevColor("#313244"),
        textPrimary: BrevColor("#CDD6F4"),
        textSecondary: BrevColor("#BAC2DE"),
        textTertiary: BrevColor("#6C7086"),
        accent: BrevColor("#89B4FA"),
        accentMuted: BrevColor("#74C7EC"),
        success: BrevColor("#A6E3A1"),
        warning: BrevColor("#F9E2AF"),
        danger: BrevColor("#F38BA8"),
        info: BrevColor("#89DCEB"),
        border: BrevColor("#313244"),
        separator: BrevColor("#313244"),
        selection: BrevColor("#45475A"),
        avatarPalette: [
            BrevColor("#89B4FA"),
            BrevColor("#F9E2AF"),
            BrevColor("#A6E3A1"),
            BrevColor("#CBA6F7"),
            BrevColor("#F38BA8"),
            BrevColor("#94E2D5"),
            BrevColor("#FAB387"),
            BrevColor("#74C7EC")
        ]
    )

    // MARK: - Tokyo Night (dark)

    /// Clean dark palette inspired by Tokyo city lights.
    static let tokyoNight = BrevTheme(
        id: "tokyo-night",
        name: "Tokyo Night",
        mode: .dark,
        author: "enkia",
        license: "MIT",
        bgPrimary: BrevColor("#1A1B26"),
        bgSecondary: BrevColor("#16161E"),
        bgTertiary: BrevColor("#292E42"),
        textPrimary: BrevColor("#C0CAF5"),
        textSecondary: BrevColor("#A9B1D6"),
        textTertiary: BrevColor("#565F89"),
        accent: BrevColor("#7AA2F7"),
        accentMuted: BrevColor("#7DCFFF"),
        success: BrevColor("#9ECE6A"),
        warning: BrevColor("#E0AF68"),
        danger: BrevColor("#F7768E"),
        info: BrevColor("#2AC3DE"),
        border: BrevColor("#292E42"),
        separator: BrevColor("#292E42"),
        selection: BrevColor("#33467C"),
        avatarPalette: [
            BrevColor("#7AA2F7"),
            BrevColor("#E0AF68"),
            BrevColor("#9ECE6A"),
            BrevColor("#BB9AF7"),
            BrevColor("#F7768E"),
            BrevColor("#73DACA"),
            BrevColor("#FF9E64"),
            BrevColor("#7DCFFF")
        ]
    )

    // MARK: - Rosé Pine (dark)

    /// All natural pine, faux fur, and a bit of soho vibes.
    static let rosePine = BrevTheme(
        id: "rose-pine",
        name: "Rosé Pine",
        mode: .dark,
        author: "Rosé Pine",
        license: "MIT",
        bgPrimary: BrevColor("#191724"),
        bgSecondary: BrevColor("#1F1D2E"),
        bgTertiary: BrevColor("#26233A"),
        textPrimary: BrevColor("#E0DEF4"),
        textSecondary: BrevColor("#908CAA"),
        textTertiary: BrevColor("#6E6A86"),
        accent: BrevColor("#C4A7E7"),
        accentMuted: BrevColor("#9CCFD8"),
        success: BrevColor("#9CCFD8"),
        warning: BrevColor("#F6C177"),
        danger: BrevColor("#EB6F92"),
        info: BrevColor("#31748F"),
        border: BrevColor("#26233A"),
        separator: BrevColor("#26233A"),
        selection: BrevColor("#2A283E"),
        avatarPalette: [
            BrevColor("#C4A7E7"),
            BrevColor("#F6C177"),
            BrevColor("#9CCFD8"),
            BrevColor("#EB6F92"),
            BrevColor("#31748F"),
            BrevColor("#EBBCBA"),
            BrevColor("#E0DEF4"),
            BrevColor("#908CAA")
        ]
    )

    // MARK: - Forge Light

    /// Clean forge-style light palette for issue, PR, and code review
    /// muscle memory without adopting a product-branded theme name.
    static let forgeLight = BrevTheme(
        id: "forge-light",
        name: "Forge Light",
        mode: .light,
        author: "Brev contributors",
        license: "MIT",
        bgPrimary: BrevColor("#FFFFFF"),
        bgSecondary: BrevColor("#F6F8FA"),
        bgTertiary: BrevColor("#EAEEF2"),
        textPrimary: BrevColor("#24292F"),
        textSecondary: BrevColor("#57606A"),
        textTertiary: BrevColor("#6E7781"),
        accent: BrevColor("#0969DA"),
        accentMuted: BrevColor("#54AEFF"),
        success: BrevColor("#1A7F37"),
        warning: BrevColor("#9A6700"),
        danger: BrevColor("#CF222E"),
        info: BrevColor("#0969DA"),
        border: BrevColor("#D0D7DE"),
        separator: BrevColor("#D8DEE4"),
        selection: BrevColor("#DDF4FF"),
        avatarPalette: [
            BrevColor("#0969DA"),
            BrevColor("#9A6700"),
            BrevColor("#1A7F37"),
            BrevColor("#8250DF"),
            BrevColor("#CF222E"),
            BrevColor("#0A758F"),
            BrevColor("#BC4C00"),
            BrevColor("#57606A")
        ]
    )

    // MARK: - Forge Dark

    /// Developer-forge dark palette with crisp blues, green status
    /// tones, and low-glare review surfaces.
    static let forgeDark = BrevTheme(
        id: "forge-dark",
        name: "Forge Dark",
        mode: .dark,
        author: "Brev contributors",
        license: "MIT",
        bgPrimary: BrevColor("#0D1117"),
        bgSecondary: BrevColor("#161B22"),
        bgTertiary: BrevColor("#21262D"),
        textPrimary: BrevColor("#E6EDF3"),
        textSecondary: BrevColor("#C9D1D9"),
        textTertiary: BrevColor("#8B949E"),
        accent: BrevColor("#58A6FF"),
        accentMuted: BrevColor("#1F6FEB"),
        success: BrevColor("#3FB950"),
        warning: BrevColor("#D29922"),
        danger: BrevColor("#F85149"),
        info: BrevColor("#58A6FF"),
        border: BrevColor("#30363D"),
        separator: BrevColor("#21262D"),
        selection: BrevColor("#1F2F46"),
        avatarPalette: [
            BrevColor("#58A6FF"),
            BrevColor("#D29922"),
            BrevColor("#3FB950"),
            BrevColor("#BC8CFF"),
            BrevColor("#F85149"),
            BrevColor("#39C5CF"),
            BrevColor("#DB6D28"),
            BrevColor("#8B949E")
        ]
    )

    // MARK: - One Dark Pro

    /// Atom-family editor dark palette: graphite surfaces with clear
    /// blue, cyan, green, gold, rose, and purple syntax accents.
    static let oneDarkPro = BrevTheme(
        id: "one-dark-pro",
        name: "One Dark Pro",
        mode: .dark,
        author: "Brev contributors",
        license: "MIT",
        bgPrimary: BrevColor("#282C34"),
        bgSecondary: BrevColor("#21252B"),
        bgTertiary: BrevColor("#353B45"),
        textPrimary: BrevColor("#ABB2BF"),
        textSecondary: BrevColor("#828997"),
        textTertiary: BrevColor("#5C6370"),
        accent: BrevColor("#61AFEF"),
        accentMuted: BrevColor("#56B6C2"),
        success: BrevColor("#98C379"),
        warning: BrevColor("#E5C07B"),
        danger: BrevColor("#E06C75"),
        info: BrevColor("#61AFEF"),
        border: BrevColor("#3E4451"),
        separator: BrevColor("#2C313A"),
        selection: BrevColor("#3E4451"),
        avatarPalette: [
            BrevColor("#61AFEF"),
            BrevColor("#E5C07B"),
            BrevColor("#98C379"),
            BrevColor("#C678DD"),
            BrevColor("#E06C75"),
            BrevColor("#56B6C2"),
            BrevColor("#D19A66"),
            BrevColor("#ABB2BF")
        ]
    )

    // MARK: - Command Dark

    /// Minimal command-palette dark theme for modern AI/editor
    /// workflows: almost-black surfaces with electric violet focus.
    static let commandDark = BrevTheme(
        id: "command-dark",
        name: "Command Dark",
        mode: .dark,
        author: "Brev contributors",
        license: "MIT",
        bgPrimary: BrevColor("#0F1117"),
        bgSecondary: BrevColor("#171A21"),
        bgTertiary: BrevColor("#20242D"),
        textPrimary: BrevColor("#F4F4F5"),
        textSecondary: BrevColor("#C6CAD3"),
        textTertiary: BrevColor("#858B9A"),
        accent: BrevColor("#A78BFA"),
        accentMuted: BrevColor("#7C3AED"),
        success: BrevColor("#34D399"),
        warning: BrevColor("#FBBF24"),
        danger: BrevColor("#FB7185"),
        info: BrevColor("#60A5FA"),
        border: BrevColor("#2A2F3A"),
        separator: BrevColor("#20242D"),
        selection: BrevColor("#2D2448"),
        avatarPalette: [
            BrevColor("#A78BFA"),
            BrevColor("#FBBF24"),
            BrevColor("#34D399"),
            BrevColor("#60A5FA"),
            BrevColor("#FB7185"),
            BrevColor("#22D3EE"),
            BrevColor("#F97316"),
            BrevColor("#C6CAD3")
        ]
    )

    // MARK: - Blurple Night

    /// Social workspace dark palette with charcoal surfaces and a
    /// blue-violet accent tuned for sidebars and message lists.
    static let blurpleNight = BrevTheme(
        id: "blurple-night",
        name: "Blurple Night",
        mode: .dark,
        author: "Brev contributors",
        license: "MIT",
        bgPrimary: BrevColor("#1E1F22"),
        bgSecondary: BrevColor("#2B2D31"),
        bgTertiary: BrevColor("#313338"),
        textPrimary: BrevColor("#F2F3F5"),
        textSecondary: BrevColor("#B5BAC1"),
        textTertiary: BrevColor("#80848E"),
        accent: BrevColor("#5865F2"),
        accentMuted: BrevColor("#7983F5"),
        success: BrevColor("#23A55A"),
        warning: BrevColor("#F0B232"),
        danger: BrevColor("#F23F42"),
        info: BrevColor("#00A8FC"),
        border: BrevColor("#3F4147"),
        separator: BrevColor("#2B2D31"),
        selection: BrevColor("#404249"),
        avatarPalette: [
            BrevColor("#5865F2"),
            BrevColor("#F0B232"),
            BrevColor("#23A55A"),
            BrevColor("#EB459E"),
            BrevColor("#F23F42"),
            BrevColor("#00A8FC"),
            BrevColor("#F47FFF"),
            BrevColor("#B5BAC1")
        ]
    )

    // MARK: - Midnight Terminal

    /// Very dark terminal palette with green phosphor accents and
    /// amber warnings for a focused command-line mood.
    static let midnightTerminal = BrevTheme(
        id: "midnight-terminal",
        name: "Midnight Terminal",
        mode: .dark,
        author: "Brev contributors",
        license: "MIT",
        bgPrimary: BrevColor("#05070A"),
        bgSecondary: BrevColor("#0B0F14"),
        bgTertiary: BrevColor("#111827"),
        textPrimary: BrevColor("#D7FFE7"),
        textSecondary: BrevColor("#9DE7B3"),
        textTertiary: BrevColor("#5F8F70"),
        accent: BrevColor("#00E676"),
        accentMuted: BrevColor("#00B894"),
        success: BrevColor("#22C55E"),
        warning: BrevColor("#FACC15"),
        danger: BrevColor("#FF5C7A"),
        info: BrevColor("#38BDF8"),
        border: BrevColor("#173522"),
        separator: BrevColor("#102017"),
        selection: BrevColor("#11351F"),
        avatarPalette: [
            BrevColor("#00E676"),
            BrevColor("#FACC15"),
            BrevColor("#22C55E"),
            BrevColor("#A78BFA"),
            BrevColor("#FF5C7A"),
            BrevColor("#38BDF8"),
            BrevColor("#FB923C"),
            BrevColor("#9DE7B3")
        ]
    )

    // MARK: - Cobalt Night

    /// Saturated blue IDE theme with bright cyan highlights and a
    /// crisp, cool reading surface.
    static let cobaltNight = BrevTheme(
        id: "cobalt-night",
        name: "Cobalt Night",
        mode: .dark,
        author: "Brev contributors",
        license: "MIT",
        bgPrimary: BrevColor("#071426"),
        bgSecondary: BrevColor("#0B1E36"),
        bgTertiary: BrevColor("#123052"),
        textPrimary: BrevColor("#E8F1FF"),
        textSecondary: BrevColor("#B7C7E6"),
        textTertiary: BrevColor("#6F86B3"),
        accent: BrevColor("#4DA3FF"),
        accentMuted: BrevColor("#22D3EE"),
        success: BrevColor("#2DD4BF"),
        warning: BrevColor("#FBBF24"),
        danger: BrevColor("#F87171"),
        info: BrevColor("#38BDF8"),
        border: BrevColor("#1C426B"),
        separator: BrevColor("#123052"),
        selection: BrevColor("#173E73"),
        avatarPalette: [
            BrevColor("#4DA3FF"),
            BrevColor("#FBBF24"),
            BrevColor("#2DD4BF"),
            BrevColor("#A78BFA"),
            BrevColor("#F87171"),
            BrevColor("#38BDF8"),
            BrevColor("#FB923C"),
            BrevColor("#B7C7E6")
        ]
    )

    // MARK: - Code Candy Dark

    /// High-energy syntax-inspired palette with neon pink, violet,
    /// mint, and cyan accents over plum-black surfaces.
    static let codeCandyDark = BrevTheme(
        id: "code-candy-dark",
        name: "Code Candy Dark",
        mode: .dark,
        author: "Brev contributors",
        license: "MIT",
        bgPrimary: BrevColor("#17151F"),
        bgSecondary: BrevColor("#211D2B"),
        bgTertiary: BrevColor("#2B2538"),
        textPrimary: BrevColor("#F6F3FF"),
        textSecondary: BrevColor("#D5CCEA"),
        textTertiary: BrevColor("#8F82A8"),
        accent: BrevColor("#FF79C6"),
        accentMuted: BrevColor("#BD93F9"),
        success: BrevColor("#50FA7B"),
        warning: BrevColor("#F1FA8C"),
        danger: BrevColor("#FF5555"),
        info: BrevColor("#8BE9FD"),
        border: BrevColor("#3A3150"),
        separator: BrevColor("#2B2538"),
        selection: BrevColor("#3D2F57"),
        avatarPalette: [
            BrevColor("#FF79C6"),
            BrevColor("#F1FA8C"),
            BrevColor("#50FA7B"),
            BrevColor("#BD93F9"),
            BrevColor("#FF5555"),
            BrevColor("#8BE9FD"),
            BrevColor("#FFB86C"),
            BrevColor("#D5CCEA")
        ]
    )

    // MARK: - Pearl Light

    /// Cool, low-glare light editor palette with blue-violet focus and
    /// enough warmth to keep long reading sessions from feeling sterile.
    static let pearlLight = BrevTheme(
        id: "pearl-light",
        name: "Pearl Light",
        mode: .light,
        author: "Brev contributors",
        license: "MIT",
        bgPrimary: BrevColor("#F8FAFF"),
        bgSecondary: BrevColor("#EEF3FB"),
        bgTertiary: BrevColor("#E1E8F2"),
        textPrimary: BrevColor("#202635"),
        textSecondary: BrevColor("#536078"),
        textTertiary: BrevColor("#8490A6"),
        accent: BrevColor("#4F6BED"),
        accentMuted: BrevColor("#7C8FF4"),
        success: BrevColor("#2E7D59"),
        warning: BrevColor("#A96A00"),
        danger: BrevColor("#C43E5A"),
        info: BrevColor("#3276C8"),
        border: BrevColor("#CDD6E4"),
        separator: BrevColor("#DDE5F0"),
        selection: BrevColor("#DCE6FF"),
        avatarPalette: [
            BrevColor("#4F6BED"),
            BrevColor("#A96A00"),
            BrevColor("#2E7D59"),
            BrevColor("#8B5CF6"),
            BrevColor("#C43E5A"),
            BrevColor("#0E7490"),
            BrevColor("#C2410C"),
            BrevColor("#536078")
        ]
    )

    // MARK: - Evergreen Night

    /// Deep green IDE palette with softened contrast, moss accents, and
    /// tea-warm warnings for a calmer dark reading surface.
    static let evergreenNight = BrevTheme(
        id: "evergreen-night",
        name: "Evergreen Night",
        mode: .dark,
        author: "Brev contributors",
        license: "MIT",
        bgPrimary: BrevColor("#1E2326"),
        bgSecondary: BrevColor("#252B2E"),
        bgTertiary: BrevColor("#2D3538"),
        textPrimary: BrevColor("#D3C6AA"),
        textSecondary: BrevColor("#A7C080"),
        textTertiary: BrevColor("#7A8478"),
        accent: BrevColor("#7FBBB3"),
        accentMuted: BrevColor("#83C092"),
        success: BrevColor("#A7C080"),
        warning: BrevColor("#DBBC7F"),
        danger: BrevColor("#E67E80"),
        info: BrevColor("#7FBBB3"),
        border: BrevColor("#3A4447"),
        separator: BrevColor("#2D3538"),
        selection: BrevColor("#343F3D"),
        avatarPalette: [
            BrevColor("#7FBBB3"),
            BrevColor("#DBBC7F"),
            BrevColor("#A7C080"),
            BrevColor("#D699B6"),
            BrevColor("#E67E80"),
            BrevColor("#83C092"),
            BrevColor("#E69875"),
            BrevColor("#D3C6AA")
        ]
    )

    // MARK: - Ink Wave

    /// Japanese ink-and-wave inspired dark palette with indigo surfaces,
    /// muted parchment text, and balanced cyan and peach accents.
    static let inkWave = BrevTheme(
        id: "ink-wave",
        name: "Ink Wave",
        mode: .dark,
        author: "Brev contributors",
        license: "MIT",
        bgPrimary: BrevColor("#1F1F28"),
        bgSecondary: BrevColor("#252535"),
        bgTertiary: BrevColor("#2A2A3D"),
        textPrimary: BrevColor("#DCD7BA"),
        textSecondary: BrevColor("#C8C093"),
        textTertiary: BrevColor("#727169"),
        accent: BrevColor("#7E9CD8"),
        accentMuted: BrevColor("#7AA89F"),
        success: BrevColor("#98BB6C"),
        warning: BrevColor("#E6C384"),
        danger: BrevColor("#E46876"),
        info: BrevColor("#7FB4CA"),
        border: BrevColor("#363646"),
        separator: BrevColor("#2A2A3D"),
        selection: BrevColor("#2D4F67"),
        avatarPalette: [
            BrevColor("#7E9CD8"),
            BrevColor("#E6C384"),
            BrevColor("#98BB6C"),
            BrevColor("#957FB8"),
            BrevColor("#E46876"),
            BrevColor("#7AA89F"),
            BrevColor("#FFA066"),
            BrevColor("#DCD7BA")
        ]
    )

    // MARK: - Mirage Ember

    /// Warm mirage palette with smoky navy surfaces and ember-orange
    /// highlights that still preserves quiet mail readability.
    static let mirageEmber = BrevTheme(
        id: "mirage-ember",
        name: "Mirage Ember",
        mode: .dark,
        author: "Brev contributors",
        license: "MIT",
        bgPrimary: BrevColor("#1F2430"),
        bgSecondary: BrevColor("#242B38"),
        bgTertiary: BrevColor("#2E3746"),
        textPrimary: BrevColor("#D9D7CE"),
        textSecondary: BrevColor("#B8C0CC"),
        textTertiary: BrevColor("#707A8C"),
        accent: BrevColor("#FFCC66"),
        accentMuted: BrevColor("#FFA759"),
        success: BrevColor("#BAE67E"),
        warning: BrevColor("#FFD580"),
        danger: BrevColor("#F28779"),
        info: BrevColor("#5CCFE6"),
        border: BrevColor("#384253"),
        separator: BrevColor("#2E3746"),
        selection: BrevColor("#333C4F"),
        avatarPalette: [
            BrevColor("#FFCC66"),
            BrevColor("#FFA759"),
            BrevColor("#BAE67E"),
            BrevColor("#D4BFFF"),
            BrevColor("#F28779"),
            BrevColor("#5CCFE6"),
            BrevColor("#FFAD66"),
            BrevColor("#B8C0CC")
        ]
    )

    // MARK: - Oceanic Dark

    /// Blue-green material-style dark palette with ocean surfaces,
    /// turquoise focus, and clean high-contrast message text.
    static let oceanicDark = BrevTheme(
        id: "oceanic-dark",
        name: "Oceanic Dark",
        mode: .dark,
        author: "Brev contributors",
        license: "MIT",
        bgPrimary: BrevColor("#0F171F"),
        bgSecondary: BrevColor("#16232D"),
        bgTertiary: BrevColor("#1E303D"),
        textPrimary: BrevColor("#D8DEE9"),
        textSecondary: BrevColor("#A7B4C2"),
        textTertiary: BrevColor("#6F8090"),
        accent: BrevColor("#26C6DA"),
        accentMuted: BrevColor("#00ACC1"),
        success: BrevColor("#80CBC4"),
        warning: BrevColor("#FFCB6B"),
        danger: BrevColor("#FF5370"),
        info: BrevColor("#82AAFF"),
        border: BrevColor("#294556"),
        separator: BrevColor("#1E303D"),
        selection: BrevColor("#193C46"),
        avatarPalette: [
            BrevColor("#26C6DA"),
            BrevColor("#FFCB6B"),
            BrevColor("#80CBC4"),
            BrevColor("#C792EA"),
            BrevColor("#FF5370"),
            BrevColor("#82AAFF"),
            BrevColor("#F78C6C"),
            BrevColor("#A7B4C2")
        ]
    )

    // MARK: - Amber Terminal

    /// Vintage amber terminal palette for people who want the terminal
    /// vibe without the eye-searing pure black of old phosphor screens.
    static let amberTerminal = BrevTheme(
        id: "amber-terminal",
        name: "Amber Terminal",
        mode: .dark,
        author: "Brev contributors",
        license: "MIT",
        bgPrimary: BrevColor("#120E08"),
        bgSecondary: BrevColor("#1C160D"),
        bgTertiary: BrevColor("#2A2113"),
        textPrimary: BrevColor("#FFE8B6"),
        textSecondary: BrevColor("#E8BE72"),
        textTertiary: BrevColor("#9A7440"),
        accent: BrevColor("#FFB020"),
        accentMuted: BrevColor("#D98A00"),
        success: BrevColor("#8BC34A"),
        warning: BrevColor("#FFC857"),
        danger: BrevColor("#FF6B6B"),
        info: BrevColor("#5DADE2"),
        border: BrevColor("#3A2C17"),
        separator: BrevColor("#2A2113"),
        selection: BrevColor("#3D2A0F"),
        avatarPalette: [
            BrevColor("#FFB020"),
            BrevColor("#FFC857"),
            BrevColor("#8BC34A"),
            BrevColor("#B084F5"),
            BrevColor("#FF6B6B"),
            BrevColor("#5DADE2"),
            BrevColor("#E67E22"),
            BrevColor("#E8BE72")
        ]
    )

    // MARK: - Owl Blue

    /// Late-night blue editor palette with bright cyan focus, violet
    /// flourishes, and high clarity for message bodies.
    static let owlBlue = BrevTheme(
        id: "owl-blue",
        name: "Owl Blue",
        mode: .dark,
        author: "Brev contributors",
        license: "MIT",
        bgPrimary: BrevColor("#011627"),
        bgSecondary: BrevColor("#071D31"),
        bgTertiary: BrevColor("#0D2B45"),
        textPrimary: BrevColor("#D6DEEB"),
        textSecondary: BrevColor("#B4C6D9"),
        textTertiary: BrevColor("#637777"),
        accent: BrevColor("#82AAFF"),
        accentMuted: BrevColor("#7FDBCA"),
        success: BrevColor("#ADDB67"),
        warning: BrevColor("#ECC48D"),
        danger: BrevColor("#EF5350"),
        info: BrevColor("#21C7A8"),
        border: BrevColor("#174466"),
        separator: BrevColor("#0D2B45"),
        selection: BrevColor("#1D3B53"),
        avatarPalette: [
            BrevColor("#82AAFF"),
            BrevColor("#ECC48D"),
            BrevColor("#ADDB67"),
            BrevColor("#C792EA"),
            BrevColor("#EF5350"),
            BrevColor("#7FDBCA"),
            BrevColor("#F78C6C"),
            BrevColor("#D6DEEB")
        ]
    )

    // MARK: - Synthwave Dusk

    /// Retro-future purple night palette with restrained neon accents
    /// tuned down for a mail client rather than a poster.
    static let synthwaveDusk = BrevTheme(
        id: "synthwave-dusk",
        name: "Synthwave Dusk",
        mode: .dark,
        author: "Brev contributors",
        license: "MIT",
        bgPrimary: BrevColor("#1A1028"),
        bgSecondary: BrevColor("#241638"),
        bgTertiary: BrevColor("#33204D"),
        textPrimary: BrevColor("#F7E9FF"),
        textSecondary: BrevColor("#D8B4FE"),
        textTertiary: BrevColor("#9B7BB8"),
        accent: BrevColor("#FF6AD5"),
        accentMuted: BrevColor("#C084FC"),
        success: BrevColor("#72F1B8"),
        warning: BrevColor("#F9F871"),
        danger: BrevColor("#FF5370"),
        info: BrevColor("#36F9F6"),
        border: BrevColor("#463063"),
        separator: BrevColor("#33204D"),
        selection: BrevColor("#43275E"),
        avatarPalette: [
            BrevColor("#FF6AD5"),
            BrevColor("#F9F871"),
            BrevColor("#72F1B8"),
            BrevColor("#C084FC"),
            BrevColor("#FF5370"),
            BrevColor("#36F9F6"),
            BrevColor("#FF9E64"),
            BrevColor("#D8B4FE")
        ]
    )

    // MARK: - Zenwritten Light

    /// Minimal bone-gray light palette from the Zenbones family, mapped
    /// to Brev's semantic mail tokens with restrained chroma.
    static let zenwrittenLight = BrevTheme(
        id: "zenwritten-light",
        name: "Zenwritten Light",
        mode: .light,
        author: "Zenbones",
        license: "MIT",
        bgPrimary: BrevColor("#EEEEEE"),
        bgSecondary: BrevColor("#E3E1E1"),
        bgTertiary: BrevColor("#D7D7D7"),
        textPrimary: BrevColor("#353535"),
        textSecondary: BrevColor("#5C5C5C"),
        textTertiary: BrevColor("#8A8585"),
        accent: BrevColor("#286486"),
        accentMuted: BrevColor("#3B8992"),
        success: BrevColor("#4F6C31"),
        warning: BrevColor("#944927"),
        danger: BrevColor("#A8334C"),
        info: BrevColor("#286486"),
        border: BrevColor("#C6C3C3"),
        separator: BrevColor("#D7D7D7"),
        selection: BrevColor("#D7D7D7"),
        avatarPalette: [
            BrevColor("#286486"),
            BrevColor("#944927"),
            BrevColor("#4F6C31"),
            BrevColor("#88507D"),
            BrevColor("#A8334C"),
            BrevColor("#3B8992"),
            BrevColor("#803D1C"),
            BrevColor("#5C5C5C")
        ]
    )

    // MARK: - Zenwritten Dark

    /// Minimal bone-gray dark palette from the Zenbones family: low hue,
    /// high calm, and just enough color for state and selection.
    static let zenwrittenDark = BrevTheme(
        id: "zenwritten-dark",
        name: "Zenwritten Dark",
        mode: .dark,
        author: "Zenbones",
        license: "MIT",
        bgPrimary: BrevColor("#191919"),
        bgSecondary: BrevColor("#222020"),
        bgTertiary: BrevColor("#3D3839"),
        textPrimary: BrevColor("#BBBBBB"),
        textSecondary: BrevColor("#A8A8A8"),
        textTertiary: BrevColor("#8E8E8E"),
        accent: BrevColor("#6099C0"),
        accentMuted: BrevColor("#66A5AD"),
        success: BrevColor("#819B69"),
        warning: BrevColor("#B77E64"),
        danger: BrevColor("#DE6E7C"),
        info: BrevColor("#61ABDA"),
        border: BrevColor("#403D3D"),
        separator: BrevColor("#3D3839"),
        selection: BrevColor("#404040"),
        avatarPalette: [
            BrevColor("#6099C0"),
            BrevColor("#B77E64"),
            BrevColor("#819B69"),
            BrevColor("#B279A7"),
            BrevColor("#DE6E7C"),
            BrevColor("#66A5AD"),
            BrevColor("#D68C67"),
            BrevColor("#BBBBBB")
        ]
    )

    // MARK: - Tender

    /// Tender's warm graphite terminal palette: soft text, sharp
    /// lemon/cyan highlights, and a cozy dark mail surface.
    static let tender = BrevTheme(
        id: "tender",
        name: "Tender",
        mode: .dark,
        author: "Jacobo Tabernero",
        license: "MIT",
        bgPrimary: BrevColor("#282828"),
        bgSecondary: BrevColor("#222222"),
        bgTertiary: BrevColor("#293B44"),
        textPrimary: BrevColor("#EEEEEE"),
        textSecondary: BrevColor("#D8D8D8"),
        textTertiary: BrevColor("#9EA4A6"),
        accent: BrevColor("#73CEF4"),
        accentMuted: BrevColor("#B3DEEF"),
        success: BrevColor("#C9D05C"),
        warning: BrevColor("#FFC24B"),
        danger: BrevColor("#F43753"),
        info: BrevColor("#B3DEEF"),
        border: BrevColor("#3A4B52"),
        separator: BrevColor("#293B44"),
        selection: BrevColor("#293B44"),
        avatarPalette: [
            BrevColor("#73CEF4"),
            BrevColor("#FFC24B"),
            BrevColor("#C9D05C"),
            BrevColor("#D3B987"),
            BrevColor("#F43753"),
            BrevColor("#B3DEEF"),
            BrevColor("#F5A742"),
            BrevColor("#EEEEEE")
        ]
    )

    // MARK: - Tomorrow Day

    /// Clean classic Tomorrow light palette with low-noise surfaces and
    /// familiar syntax-inspired accents.
    static let tomorrowDay = BrevTheme(
        id: "tomorrow-day",
        name: "Tomorrow Day",
        mode: .light,
        author: "Chris Kempson",
        license: "MIT",
        bgPrimary: BrevColor("#FFFFFF"),
        bgSecondary: BrevColor("#F4F4F4"),
        bgTertiary: BrevColor("#E6E6E6"),
        textPrimary: BrevColor("#4D4D4C"),
        textSecondary: BrevColor("#666665"),
        textTertiary: BrevColor("#8E908C"),
        accent: BrevColor("#4271AE"),
        accentMuted: BrevColor("#3E999F"),
        success: BrevColor("#718C00"),
        warning: BrevColor("#EAB700"),
        danger: BrevColor("#C82829"),
        info: BrevColor("#4271AE"),
        border: BrevColor("#D6D6D6"),
        separator: BrevColor("#E6E6E6"),
        selection: BrevColor("#D6D6D6"),
        avatarPalette: [
            BrevColor("#4271AE"),
            BrevColor("#EAB700"),
            BrevColor("#718C00"),
            BrevColor("#8959A8"),
            BrevColor("#C82829"),
            BrevColor("#3E999F"),
            BrevColor("#F5871F"),
            BrevColor("#4D4D4C")
        ]
    )

    // MARK: - Tomorrow Night

    /// Classic Tomorrow Night palette: muted charcoal, measured text,
    /// and durable syntax colors that translate well to mail UI.
    static let tomorrowNight = BrevTheme(
        id: "tomorrow-night",
        name: "Tomorrow Night",
        mode: .dark,
        author: "Chris Kempson",
        license: "MIT",
        bgPrimary: BrevColor("#1D1F21"),
        bgSecondary: BrevColor("#282A2E"),
        bgTertiary: BrevColor("#373B41"),
        textPrimary: BrevColor("#C5C8C6"),
        textSecondary: BrevColor("#AEB2B0"),
        textTertiary: BrevColor("#969896"),
        accent: BrevColor("#81A2BE"),
        accentMuted: BrevColor("#8ABEB7"),
        success: BrevColor("#B5BD68"),
        warning: BrevColor("#F0C674"),
        danger: BrevColor("#CC6666"),
        info: BrevColor("#81A2BE"),
        border: BrevColor("#373B41"),
        separator: BrevColor("#282A2E"),
        selection: BrevColor("#373B41"),
        avatarPalette: [
            BrevColor("#81A2BE"),
            BrevColor("#F0C674"),
            BrevColor("#B5BD68"),
            BrevColor("#B294BB"),
            BrevColor("#CC6666"),
            BrevColor("#8ABEB7"),
            BrevColor("#DE935F"),
            BrevColor("#C5C8C6")
        ]
    )
}
