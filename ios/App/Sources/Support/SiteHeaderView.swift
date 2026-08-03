// Mirrors src/components/SiteHeader.tsx's wordmark row: a centered,
// small-caps "Confessional Christianity" mark over a hairline bottom
// border, balanced by a search icon (SearchIcon.tsx) at the trailing edge.
// The nav row it sits above on web (Catechisms/Devotions/Resources/
// Library) isn't ported — those destinations beyond what's already
// reachable from Home aren't built yet, and a bar of dead-end taps would be
// worse than no bar at all.
import SwiftUI

struct SiteHeaderView: View {
    @Binding var path: NavigationPath

    var body: some View {
        ZStack {
            Text("Confessional Christianity")
                .font(.ccDisplay(16, semibold: true))
                .tracking(16 * 0.08)
                .textCase(.uppercase)
                .foregroundStyle(.ccInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            HStack {
                Spacer()
                Button {
                    path.append(SearchRoute.results)
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundStyle(.ccInk)
                        .frame(width: 32, height: 32, alignment: .trailing)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .background(Color.ccCard)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.ccHairline).frame(height: 1)
        }
    }
}
