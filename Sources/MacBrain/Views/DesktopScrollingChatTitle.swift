import AppKit
import SwiftUI

/// A compact title that continuously reveals long names while its chat row is hovered.
struct DesktopScrollingChatTitle: View {
    let title: String
    let isHovering: Bool

    @State private var marqueeOffset: CGFloat = 0

    private let interTitleGap: CGFloat = 34

    private var shouldMarquee: Bool {
        isHovering && ChatHoverPreviewPolicy.shouldAutoScrollTitle(for: title)
    }

    private var titleWidth: CGFloat {
        (title as NSString).size(
            withAttributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]
        ).width
    }

    private var cycleDistance: CGFloat {
        titleWidth + interTitleGap
    }

    private var cycleDuration: Double {
        max(5.5, Double(cycleDistance / 24))
    }

    var body: some View {
        GeometryReader { _ in
            HStack(spacing: interTitleGap) {
                titleText
                if shouldMarquee {
                    titleText
                }
            }
            .offset(x: marqueeOffset)
            .onAppear(perform: updateMarquee)
            .onChange(of: isHovering) { _, _ in updateMarquee() }
            .onChange(of: title) { _, _ in updateMarquee() }
        }
        .frame(height: 22, alignment: .leading)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityLabel(title)
    }

    private var titleText: some View {
        Text(title)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func updateMarquee() {
        guard shouldMarquee else {
            withAnimation(.easeOut(duration: 0.20)) {
                marqueeOffset = 0
            }
            return
        }

        marqueeOffset = 0
        withAnimation(.linear(duration: cycleDuration).repeatForever(autoreverses: false)) {
            marqueeOffset = -cycleDistance
        }
    }
}
