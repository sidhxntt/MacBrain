import SwiftUI

struct MacBrainWelcomeView: View {
    let greeting: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPresented = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                BundleSVGImage(resourceName: "top")
                    .frame(width: 22, height: 22)

                Text("MacBrain")
                    .foregroundStyle(.white)
            }
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 26)

            Spacer(minLength: 24)

            VStack(spacing: 14) {
                BundleSVGImage(resourceName: "center")
                    .frame(width: 76, height: 76)

                Text(greeting)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)

                Text("Ask about anything MacBrain remembers from your work.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 24)
        }
        .padding(.horizontal, 24)
        .opacity(isPresented ? 1 : 0)
        .scaleEffect(reduceMotion || isPresented ? 1 : 0.97)
        .offset(y: reduceMotion || isPresented ? 0 : 14)
        .onAppear(perform: present)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("MacBrain. \(greeting). Ask about anything MacBrain remembers from your work.")
    }

    private func present() {
        guard !isPresented else { return }

        if reduceMotion {
            isPresented = true
        } else {
            withAnimation(.easeOut(duration: 0.56)) {
                isPresented = true
            }
        }
    }
}
