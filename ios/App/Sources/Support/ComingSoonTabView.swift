// Honest empty-state root for tabs whose surface isn't built yet
// (Reflections mirrors web's /reflections, Library mirrors /library) —
// reachable from the floating tab bar so all four sections resolve
// somewhere, rather than omitting the tab and reintroducing dead taps.
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

struct ReflectionsTabView: View {
    var body: some View {
        ComingSoonTabView(
            title: "Reflections",
            message: "Commentary and reflections on the confessions are still being prepared."
        )
    }
}

struct LibraryTabView: View {
    var body: some View {
        ComingSoonTabView(
            title: "Library",
            message: "The full library of confessions and catechisms is still being prepared."
        )
    }
}
