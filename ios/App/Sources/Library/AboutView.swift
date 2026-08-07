// Credits screen, reachable from the bottom of the Library tab. Exists
// mainly to carry the copyright notice Crossway's ESV API terms require
// somewhere in the app — the "ESV" version label next to proof texts
// (QuestionCardView, ScriptureView) isn't itself that notice. See
// EsvClient's header comment for the fetch side of this.
import SwiftUI

struct AboutView: View {
    @Binding var path: NavigationPath

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                backBar

                VStack(alignment: .leading, spacing: 24) {
                    Text("About").headingPage()

                    section(
                        title: "The Texts",
                        body: "The confessions, catechisms, and creeds in this app — the Westminster Confession and Shorter/Larger Catechisms, the Heidelberg Catechism, the Belgic Confession, the Canons of Dort, the 39 Articles, and the 95 Theses — are historic public-domain documents."
                    )

                    section(
                        title: "Scripture",
                        body: "Scripture quotations are from the ESV® Bible (The Holy Bible, English Standard Version®), copyright \u{00A9} 2001 by Crossway, a publishing ministry of Good News Publishers. Used by permission. All rights reserved."
                    )

                    section(
                        title: "Search",
                        body: "Search is powered by Algolia."
                    )
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 100)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .background(Color.ccCard)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var backBar: some View {
        HStack {
            Button {
                if !path.isEmpty { path.removeLast() }
            } label: {
                Text("\u{2039} Back").labelCaps(size: 9.5, tracking: 0.1, color: .ccInk3).dottedUnderline(.ccInk3)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    @ViewBuilder
    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).labelCaps(size: 9.5, tracking: 0.14)
            Text(body)
                .font(.ccBody(13.5))
                .foregroundStyle(.ccInk2)
        }
    }
}
