import SwiftUI

extension View {
    func adaptiveGlass<S: Shape>(
        role: AdaptiveGlassRole,
        in shape: S
    ) -> some View {
        modifier(AdaptiveGlassModifier(role: role, shape: shape))
    }
}

private struct AdaptiveGlassModifier<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let role: AdaptiveGlassRole
    let shape: S

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            nativeGlass(content)
        } else {
            fallbackGlass(content)
        }
    }

    @available(macOS 26.0, *)
    @ViewBuilder
    private func nativeGlass(_ content: Content) -> some View {
        switch role {
        case .shell:
            content.glassEffect(.regular, in: shape)
        case .composer:
            content.glassEffect(.regular.interactive(), in: shape)
        case .assistantMessage:
            content.glassEffect(.clear, in: shape)
        case .userMessage:
            content.glassEffect(.regular.tint(.accentColor.opacity(0.22)), in: shape)
        case .prominentAction:
            content.glassEffect(
                .regular.tint(Color(red: 27.0 / 255.0, green: 127.0 / 255.0, blue: 115.0 / 255.0)).interactive(),
                in: shape
            )
        }
    }

    private func fallbackGlass(_ content: Content) -> some View {
        content
            .background {
                shape.fill(fallbackBackgroundStyle)
            }
            .overlay {
                shape.fill(fallbackTint.opacity(role.fallbackTintOpacity))
            }
            .overlay {
                if role == .shell {
                    shape
                        .stroke(.white.opacity(role.outlineOpacity), lineWidth: 1)
                        .mask(alignment: .leading) {
                            Rectangle().padding(.trailing, 1)
                        }
                } else {
                    shape.stroke(.white.opacity(role.outlineOpacity), lineWidth: 1)
                }
            }
            .shadow(
                color: .black.opacity(role == .shell ? 0.28 : 0.16),
                radius: role.shadowRadius,
                y: role == .shell ? 8 : 3
            )
    }

    private var fallbackBackgroundStyle: AnyShapeStyle {
        if reduceTransparency {
            AnyShapeStyle(Color.black.opacity(0.88))
        } else {
            AnyShapeStyle(fallbackMaterial)
        }
    }

    private var fallbackMaterial: Material {
        switch role {
        case .shell, .assistantMessage: .ultraThinMaterial
        case .composer, .userMessage: .thinMaterial
        case .prominentAction: .regularMaterial
        }
    }

    private var fallbackTint: Color {
        switch role {
        case .userMessage: .accentColor
        case .prominentAction:
            Color(red: 27.0 / 255.0, green: 127.0 / 255.0, blue: 115.0 / 255.0)
        default: .white
        }
    }
}
