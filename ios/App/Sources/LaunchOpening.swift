import SwiftUI
import UIKit

struct LaunchOpening: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showing: Bool
    @State private var animatingRules = false
    @State private var ruleWidth: CGFloat = 56
    @State private var markOpacity = 1.0
    @State private var ruleOpacity = 1.0
    @State private var paperOpacity = 1.0
    @State private var contentSettled = false

    init(showing: Bool) {
        _showing = State(initialValue: showing)
    }

    func body(content: Content) -> some View {
        content
            .offset(y: showing && !reduceMotion && !contentSettled ? 8 : 0)
            .allowsHitTesting(!showing)
            .accessibilityHidden(showing)
            .background(LaunchWindowBackground())
            .overlay {
                if showing {
                    ZStack {
                        Color("LaunchBackground").opacity(reduceMotion ? 1 : paperOpacity)
                        Image("LaunchLogo").opacity(animatingRules ? 0 : 1)
                        if !reduceMotion {
                            ZStack {
                                Image("LaunchWordmark").opacity(markOpacity)
                                rule.offset(y: -17.5)
                                rule.offset(y: 54.5)
                            }
                            .opacity(animatingRules ? 1 : 0)
                        }
                    }
                    .ignoresSafeArea()
                    .opacity(reduceMotion ? paperOpacity : 1)
                    .accessibilityHidden(true)
                    .task { await play() }
                }
            }
    }

    private var rule: some View {
        Rectangle()
            .fill(Color("LaunchGilt"))
            .frame(width: ruleWidth, height: 1)
            .opacity(ruleOpacity)
    }

    private func play() async {
        // Keep the shared launch asset in place for the first rendered frame.
        do {
            try await Task.sleep(for: .milliseconds(reduceMotion ? 32 : 80))
            if reduceMotion {
                // Fade the entire title page in one pass.
                withAnimation(.linear(duration: 0.2)) { paperOpacity = 0 }
                try await Task.sleep(for: .milliseconds(200))
            } else {
                animatingRules = true
                withAnimation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.36)) { ruleWidth = 240 }
                withAnimation(.easeInOut(duration: 0.25).delay(0.34)) { markOpacity = 0 }
                withAnimation(.easeInOut(duration: 0.25).delay(0.37)) { ruleOpacity = 0 }
                withAnimation(.easeInOut(duration: 0.42).delay(0.44)) {
                    paperOpacity = 0
                    contentSettled = true
                }
                try await Task.sleep(for: .milliseconds(860))
            }
            showing = false
        } catch {
            // The overlay can be torn down while the opening is running.
        }
    }
}

private struct LaunchWindowBackground: UIViewRepresentable {
    func makeUIView(context: Context) -> WindowProbe { WindowProbe() }
    func updateUIView(_ uiView: WindowProbe, context: Context) {}

    final class WindowProbe: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            window?.backgroundColor = UIColor(named: "LaunchBackground")
        }
    }
}
