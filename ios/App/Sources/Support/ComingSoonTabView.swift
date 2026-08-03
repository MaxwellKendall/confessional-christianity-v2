// Honest empty-state root for a tab whose surface isn't built yet —
// reachable from the floating tab bar so every section resolves somewhere,
// rather than omitting the tab and reintroducing dead taps. Reflections
// graduated from this stub to a real ReflectionsTabView; kept around for any
// future section still in preparation.
import SwiftUI

struct ComingSoonTabView: View {
    let title: String
    let message: String

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SiteHeaderView()
                Spacer()
                VStack(spacing: 10) {
                    Text(title).headingPage()
                    Text(message)
                        .font(.ccBody(13.5))
                        .italic()
                        .foregroundStyle(.ccInk2)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 40)
                }
                Spacer()
                Spacer()
            }
            .background(Color.ccCanvas)
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(.ccInk)
    }
}
