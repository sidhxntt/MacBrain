import SwiftUI

struct SidebarView: View {
    let presentation: SidebarPresentation
    let onTogglePresentation: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.black.opacity(0.14))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(hue: 0.74, saturation: 0.32, brightness: 0.25).opacity(0.28))
                }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Label("Notch Brain", systemImage: "brain.head.profile")
                        .font(.headline)
                    Spacer()
                    Button(action: onTogglePresentation) {
                        Image(systemName: presentation == .compact
                              ? "arrow.up.left.and.arrow.down.right"
                              : "arrow.down.right.and.arrow.up.left")
                    }
                    .help(presentation == .compact ? "Expand sidebar" : "Compact sidebar")
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                    .help("Close sidebar")
                }
                .buttonStyle(.borderless)
                .padding(16)

                Divider()
                    .overlay(.white.opacity(0.15))

                ContentUnavailableView(
                    "Your local work memory",
                    systemImage: "sparkles",
                    description: Text("Index sources and ask questions from any app.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: SidebarGeometry.minimumWidth, minHeight: SidebarGeometry.minimumHeight)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.24), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.38), radius: 24, y: 12)
    }
}
