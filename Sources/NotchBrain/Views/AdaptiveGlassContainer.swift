import SwiftUI

struct AdaptiveGlassContainer<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    init(
        spacing: CGFloat = 8,
        @ViewBuilder content: () -> Content
    ) {
        self.spacing = spacing
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}
