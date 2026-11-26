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

import BrevThemes
import SwiftUI

/// Policy governing when Brev applies native OS 26+ Liquid Glass surfaces.
public enum BrevLiquidGlassPolicy: Sendable {
    /// Whether the current compiler and runtime OS support native Liquid Glass APIs.
    public static var isAvailableOnCurrentOS: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, iOS 26.0, *) {
            return true
        }
        #endif
        return false
    }

    /// Returns `true` when native Liquid Glass should be used instead of a fallback surface.
    /// - Parameters:
    ///   - reduceTransparency: Whether the user enabled Reduce Transparency.
    ///   - isAvailableOnOS: Whether the runtime OS provides native Liquid Glass APIs.
    public static func usesNativeLiquidGlass(
        reduceTransparency: Bool,
        isAvailableOnOS: Bool = isAvailableOnCurrentOS
    ) -> Bool {
        isAvailableOnOS && !reduceTransparency
    }
}

/// Groups sibling Liquid Glass controls so adjacent surfaces morph and share sampling on OS 26+.
public struct BrevGlassContainer<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let spacing: CGFloat?
    private let content: Content

    /// Creates a container that coordinates sibling Liquid Glass views.
    /// - Parameters:
    ///   - spacing: Optional merge distance between sibling glass shapes.
    ///   - content: Views presented inside the glass container.
    public init(
        spacing: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, iOS 26.0, *),
           BrevLiquidGlassPolicy.usesNativeLiquidGlass(
               reduceTransparency: reduceTransparency,
               isAvailableOnOS: true
           ) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

public extension View {
    /// Applies a native Liquid Glass capsule on OS 26+ with a material or solid fallback.
    /// - Parameters:
    ///   - interactive: Whether the capsule responds to pointer and touch interactions.
    ///   - tint: Optional semantic tint applied to the glass surface.
    func brevGlassCapsule(
        interactive: Bool = false,
        tint: Color? = nil
    ) -> some View {
        modifier(BrevGlassCapsuleModifier(interactive: interactive, tint: tint))
    }

    /// Applies a continuous-corner Liquid Glass surface on OS 26+ with a material or solid fallback.
    /// - Parameters:
    ///   - cornerRadius: Continuous corner radius of the glass shape.
    ///   - interactive: Whether the surface responds to pointer and touch interactions.
    ///   - tint: Optional theme surface tint; defaults to `theme.bgSecondary.color`.
    func brevGlassSurface(
        cornerRadius: CGFloat,
        interactive: Bool = false,
        tint: Color? = nil
    ) -> some View {
        modifier(BrevGlassRoundedSurfaceModifier(
            cornerRadius: cornerRadius,
            interactive: interactive,
            tint: tint
        ))
    }

    /// Applies native Liquid Glass button chrome on OS 26+ with a bordered or capsule fallback.
    /// - Parameters:
    ///   - prominent: Uses prominent tinted glass when `true`, neutral glass when `false`.
    ///   - tint: Optional accent tint; defaults to `theme.accent.color` for prominent buttons.
    func brevGlassButtonStyle(
        prominent: Bool = false,
        tint: Color? = nil
    ) -> some View {
        modifier(BrevGlassButtonStyleModifier(prominent: prominent, tint: tint))
    }
}

private struct BrevGlassCapsuleModifier: ViewModifier {
    @Environment(\.brevTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let interactive: Bool
    let tint: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, iOS 26.0, *),
           BrevLiquidGlassPolicy.usesNativeLiquidGlass(
               reduceTransparency: reduceTransparency,
               isAvailableOnOS: true
           ) {
            let baseGlass = tint.map { Glass.regular.tint($0.opacity(0.18)) } ?? Glass.regular
            content
                .glassEffect(
                    interactive ? baseGlass.interactive() : baseGlass,
                    in: Capsule()
                )
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    @ViewBuilder
    private func fallback(_ content: Content) -> some View {
        if reduceTransparency {
            content
                .background {
                    Capsule()
                        .fill(theme.bgSecondary.color)
                        .overlay {
                            if let tint {
                                Capsule().fill(tint.opacity(0.14))
                            }
                        }
                }
                .overlay {
                    Capsule()
                        .strokeBorder(theme.border.color, lineWidth: 0.5)
                }
                .clipShape(Capsule())
        } else {
            content
                .background(.regularMaterial, in: Capsule())
                .background {
                    Capsule()
                        .fill(theme.bgSecondary.color.opacity(0.45))
                        .overlay {
                            if let tint {
                                Capsule().fill(tint.opacity(0.14))
                            }
                        }
                }
                .overlay {
                    Capsule()
                        .strokeBorder(theme.border.color, lineWidth: 0.5)
                }
                .clipShape(Capsule())
        }
    }
}

private struct BrevGlassRoundedSurfaceModifier: ViewModifier {
    @Environment(\.brevTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let cornerRadius: CGFloat
    let interactive: Bool
    let tint: Color?

    private var surfaceTint: Color {
        tint ?? theme.bgSecondary.color
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        #if compiler(>=6.2)
        if #available(macOS 26.0, iOS 26.0, *),
           BrevLiquidGlassPolicy.usesNativeLiquidGlass(
               reduceTransparency: reduceTransparency,
               isAvailableOnOS: true
           ) {
            if let tint {
                // Tinted sheet surfaces (e.g. Command Palette) keep the glass
                // backing behind content with an 82% themed surface fill so
                // dense floating panels remain high-contrast over busy mail.
                let baseGlass = Glass.regular.tint(tint.opacity(0.18))
                content
                    .background {
                        Color.clear
                            .glassEffect(
                                interactive ? baseGlass.interactive() : baseGlass,
                                in: shape
                            )
                            .overlay {
                                shape.fill(tint.opacity(0.82))
                            }
                            .overlay {
                                shape.strokeBorder(theme.border.color.opacity(0.65), lineWidth: 0.5)
                            }
                    }
                    .clipShape(shape)
            } else {
                // Untinted glass surfaces inside GlassEffectContainer must apply
                // `.glassEffect` directly to `content`; wrapping `Color.clear`
                // in `.background` with an overlay fill veils foreground text.
                let baseGlass = Glass.regular
                content
                    .glassEffect(
                        interactive ? baseGlass.interactive() : baseGlass,
                        in: shape
                    )
            }
        } else {
            fallback(content, shape: shape)
        }
        #else
        fallback(content, shape: shape)
        #endif
    }

    @ViewBuilder
    private func fallback(
        _ content: Content,
        shape: RoundedRectangle
    ) -> some View {
        if reduceTransparency {
            content
                .background(surfaceTint, in: shape)
                .overlay {
                    shape.strokeBorder(theme.border.color, lineWidth: 0.5)
                }
                .clipShape(shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .background(surfaceTint.opacity(tint != nil ? 0.72 : 0.45), in: shape)
                .overlay {
                    shape.strokeBorder(theme.border.color, lineWidth: 0.5)
                }
                .clipShape(shape)
        }
    }
}

private struct BrevGlassButtonStyleModifier: ViewModifier {
    @Environment(\.brevTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let prominent: Bool
    let tint: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, iOS 26.0, *),
           BrevLiquidGlassPolicy.usesNativeLiquidGlass(
               reduceTransparency: reduceTransparency,
               isAvailableOnOS: true
           ) {
            if prominent {
                content
                    .buttonStyle(.glassProminent)
                    .tint(tint ?? theme.accent.color)
            } else if let tint {
                content
                    .buttonStyle(.glass)
                    .tint(tint)
            } else {
                content
                    .buttonStyle(.glass)
            }
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    @ViewBuilder
    private func fallback(_ content: Content) -> some View {
        if prominent {
            content
                .buttonStyle(.borderedProminent)
                .tint(tint ?? theme.accent.color)
        } else {
            content
                .buttonStyle(.plain)
                .brevGlassCapsule(interactive: true, tint: tint)
        }
    }
}
