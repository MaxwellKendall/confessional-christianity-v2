// Ports design_handoff_confessional_christianity/18c-floating-tab-bar.dc.html
// pixel-for-pixel per that handoff's README: a frosted pill inset from the
// screen edges (18pt sides, 26pt up from bottom), not a flush system tab
// bar. Selected tab springs to scale 1 (from 0.92) with slight overshoot;
// background/label color crossfade on their own, slower, un-bounced timing —
// the handoff calls these out as two separate transitions, so they're kept
// as two separate `.animation` modifiers here rather than one shared one.
import SwiftUI

struct FloatingTabBarView: View {
    @Binding var selected: RootTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(RootTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.ccCard.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.ccHairline2.opacity(0.9), lineWidth: 1)
        )
        .shadow(color: Color.ccInk.opacity(0.16), radius: 14, x: 0, y: 10)
        .padding(.horizontal, 18)
        .padding(.bottom, 26)
    }

    @ViewBuilder
    private func tabButton(_ tab: RootTab) -> some View {
        let isActive = tab == selected

        Button {
            selected = tab
        } label: {
            VStack(spacing: 4) {
                TabIcon(tab: tab, color: isActive ? .ccOchre : .ccInk3)
                    .frame(width: 17, height: 17)
                Text(tab.label)
                    .font(.ccDisplay(8))
                    .tracking(8 * 0.04)
                    .textCase(.uppercase)
                    .foregroundStyle(isActive ? Color.ccInk : Color.ccInk3)
                    .animation(.easeInOut(duration: 0.32), value: isActive)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isActive ? Color.ccTabSelected : Color.clear)
                    .animation(.easeInOut(duration: 0.32), value: isActive)
            )
            .scaleEffect(isActive ? 1 : 0.92)
            .animation(.spring(response: 0.4, dampingFraction: 0.62), value: isActive)
        }
        .buttonStyle(.plain)
    }
}
