// Mirrors src/components/SiteHeader.tsx's wordmark row: a centered,
// small-caps "Confessional Christianity" mark over a hairline bottom
// border. The nav row it sits above on web (Catechisms/Devotions/
// Resources/Library/Search) isn't ported — those destinations beyond
// what's already reachable from Home aren't built yet, and a bar of
// dead-end taps would be worse than no bar at all.
import SwiftUI

struct SiteHeaderView: View {
    var body: some View {
        Text("Confessional Christianity")
            .font(.ccDisplay(16, semibold: true))
            .tracking(16 * 0.08)
            .textCase(.uppercase)
            .foregroundStyle(.ccInk)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 14)
            .background(Color.ccCard)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.ccHairline).frame(height: 1)
            }
    }
}
