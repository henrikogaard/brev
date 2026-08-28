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
import Foundation
import SwiftUI

/// Shared typography and color tokens for HTML and native message bodies.
///
/// Reader WKWebView CSS, plain/attributed SwiftUI bodies, print wrappers,
/// and compose chrome should all resolve through this type so theme and
/// mailbox font prefs stay aligned (read/compose parity design).
struct MessageBodyStyle: Equatable, Sendable {
    let fontFamily: MailboxFontFamily
    let textSize: MailboxTextSize
    let textColorHex: String
    let linkColorHex: String
    /// `nil` means a transparent canvas (SwiftUI/WebKit host shows through).
    let backgroundColorHex: String?
    let mutedTextColorCSS: String
    let borderColorCSS: String
    let metadataBackgroundCSS: String
    let metadataTextColorCSS: String
    let codeBackgroundCSS: String
    let bodyInsetPoints: CGFloat
    let lineHeight: Double
    let renderingMode: HTMLBodyRenderingMode
    let colorSchemeMeta: String
    let forcesOriginalLightCanvas: Bool

    static let defaultLineHeight = 1.45

    static func resolve(
        theme: BrevTheme,
        fontFamily: MailboxFontFamily,
        textSize: MailboxTextSize,
        renderingMode: HTMLBodyRenderingMode,
        bodyInsetPoints: CGFloat
    ) -> MessageBodyStyle {
        let textHex = cssColor(theme.textPrimary.hex)
        let linkHex = cssColor(theme.accent.hex)
        let borderHex = cssColor(theme.border.hex)
        let mutedHex = cssColor(theme.textSecondary.hex)
        let metadataTextHex = cssColor(theme.textTertiary.hex)
        let metadataBackground = cssColor(theme.bgTertiary.hex)
        let codeBackground = cssColor(theme.bgSecondary.hex)

        switch renderingMode {
        case .dark:
            return MessageBodyStyle(
                fontFamily: fontFamily,
                textSize: textSize,
                textColorHex: textHex,
                linkColorHex: linkHex,
                backgroundColorHex: nil,
                mutedTextColorCSS: mutedHex,
                borderColorCSS: borderHex,
                metadataBackgroundCSS: metadataBackground,
                metadataTextColorCSS: metadataTextHex,
                codeBackgroundCSS: codeBackground,
                bodyInsetPoints: bodyInsetPoints,
                lineHeight: defaultLineHeight,
                renderingMode: renderingMode,
                colorSchemeMeta: "dark light",
                forcesOriginalLightCanvas: false
            )
        case .original:
            let forcesLightCanvas = isLightColor(textHex)
            return MessageBodyStyle(
                fontFamily: fontFamily,
                textSize: textSize,
                textColorHex: forcesLightCanvas ? cssColor(theme.textPrimary.hex) : textHex,
                linkColorHex: linkHex,
                backgroundColorHex: forcesLightCanvas ? "#FFFFFF" : nil,
                mutedTextColorCSS: mutedHex,
                borderColorCSS: borderHex,
                metadataBackgroundCSS: metadataBackground,
                metadataTextColorCSS: metadataTextHex,
                codeBackgroundCSS: "transparent",
                bodyInsetPoints: bodyInsetPoints,
                lineHeight: defaultLineHeight,
                renderingMode: renderingMode,
                colorSchemeMeta: "light",
                forcesOriginalLightCanvas: forcesLightCanvas
            )
        }
    }

    /// CSS rules injected into `HTMLBodyDocument` (colors from theme tokens).
    var documentCSS: String {
        let inset = max(0, Int(bodyInsetPoints.rounded()))
        let baseBackground = backgroundColorHex ?? "transparent"
        let bodyTextColor: String
        if forcesOriginalLightCanvas {
            bodyTextColor = "#111827"
        } else {
            bodyTextColor = textColorHex
        }
        let darkOverrides: String
        if renderingMode == .dark {
            darkOverrides = """
            html,body{background:\(baseBackground)!important;\
            color:\(bodyTextColor)!important;}\
            body *:not(img):not(video):not(canvas):not(iframe):not(object):not(embed):not(svg){\
            background-color:transparent!important;\
            color:inherit!important;\
            border-color:\(borderColorCSS)!important;}\
            a{color:\(linkColorHex)!important}\
            blockquote{border-left:3px solid \(borderColorCSS)!important;\
            color:\(mutedTextColorCSS)!important}\
            pre,code{background:\(codeBackgroundCSS)!important;\
            color:inherit!important}\
            hr{border-color:\(borderColorCSS)!important}\
            .brev-mail-metadata{background:\(metadataBackgroundCSS)!important;\
            color:\(metadataTextColorCSS)!important;\
            border-color:\(borderColorCSS)!important}\
            .brev-mail-metadata *{color:inherit!important}
            """
        } else {
            darkOverrides = ""
        }

        return """
        html,body{margin:0;padding:0;background:\(baseBackground);\
        color:\(bodyTextColor);\
        font:\(textSize.htmlPointSize)px \(fontFamily.cssFamily);\
        line-height:\(lineHeight);-webkit-text-size-adjust:100%;}\
        body{box-sizing:border-box;padding:\(inset)px;}\
        img,video{max-width:100%;height:auto}\
        p{margin:0 0 .85em}p:last-child{margin-bottom:0}\
        blockquote{border-left:3px solid \(borderColorCSS);\
        margin:0 0 0 4px;padding-left:10px;color:\(mutedTextColorCSS)}\
        a{color:\(linkColorHex)}\
        hr{border:0;border-top:1px solid \(borderColorCSS);\
        margin:16px 0 12px}\
        .brev-mail-metadata{box-sizing:border-box;margin:0 0 14px;\
        padding:8px 10px;border-left:3px solid \(borderColorCSS);\
        background:\(metadataBackgroundCSS);color:\(metadataTextColorCSS);\
        font-size:.92em;line-height:1.4}\
        .brev-mail-metadata b,.brev-mail-metadata strong{font-weight:600;\
        color:inherit}\
        pre,code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;\
        white-space:pre-wrap;word-break:break-word;\
        background:\(codeBackgroundCSS)}\
        \(darkOverrides)
        """
    }

    var swiftUIBodyFont: Font {
        fontFamily.font(size: textSize.bodyPointSize)
    }

    static func cssColor(_ hex: String) -> String {
        var stripped = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.hasPrefix("#") { stripped.removeFirst() }

        guard [6, 8].contains(stripped.count),
              stripped.allSatisfy(\.isHexDigit) else {
            return "currentColor"
        }

        return "#\(stripped)"
    }

    static func isLightColor(_ hex: String) -> Bool {
        var stripped = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.hasPrefix("#") { stripped.removeFirst() }
        if stripped.count == 8 {
            stripped = String(stripped.prefix(6))
        }
        guard stripped.count == 6,
              let red = Int(stripped.prefix(2), radix: 16),
              let green = Int(stripped.dropFirst(2).prefix(2), radix: 16),
              let blue = Int(stripped.dropFirst(4).prefix(2), radix: 16)
        else {
            return false
        }
        let luminance = (0.2126 * Double(red) + 0.7152 * Double(green) + 0.0722 * Double(blue)) / 255
        return luminance > 0.6
    }
}
