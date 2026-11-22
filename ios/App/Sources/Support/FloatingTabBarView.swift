// The floating tab bar from TKL-885's approved prototype: 64pt tall, 16pt in
// from the sides and 24pt up from the screen's bottom edge, on 88% surface
// over blur. The selected tab is marked by chapel green alone. It places
// itself from the screen's edge, under the keyboard like a system tab bar, so
// overlay it on a whole screen; the space around the bar passes taps through.
import SwiftUI

struct FloatingTabBarView: View {
    @Binding var selected: RootTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(RootTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .chapelTabBar()
        .padding(.horizontal, ChapelSpace.l)
        .padding(.bottom, ChapelSize.tabBarBottom)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea(edges: .bottom)
    }

    private func tabButton(_ tab: RootTab) -> some View {
        let isActive = tab == selected
        let color: Color = isActive ? .ccChapel : .ccInk3

        return Button {
            selected = tab
        } label: {
            VStack(spacing: 3) {
                TabIcon(tab: tab, color: color)
                    .frame(width: 22, height: 22)
                // Not uppercased: Cinzel draws lowercase as small capitals.
                Text(tab.label)
                    .font(.ccTabLabel)
                    .tracking(10.5 * 0.06)
                    .foregroundStyle(color)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
