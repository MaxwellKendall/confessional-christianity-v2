import SwiftUI
import DomainKit

private struct PromisePreface: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.ccDisplay(10.5)).tracking(1.68)
                .foregroundStyle(.ccGilt)
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .font(.ccBody(13.5)).lineSpacing(3)
                .foregroundStyle(.ccInk2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 6)
    }
}

struct OnboardingCatechismDemo: View {
    private enum Clause: String, CaseIterable {
        case glory = "glorify God"
        case enjoyment = "enjoy him for ever"

        var passages: [(reference: String, text: String)] {
            switch self {
            case .glory:
                [
                    ("1 Corinthians 10:31", "So, whether you eat or drink, or whatever you do, do all to the glory of God."),
                    ("Romans 11:36", "For from him and through him and to him are all things. To him be glory forever. Amen.")
                ]
            case .enjoyment:
                [("Psalm 73:25–26", "Whom have I in heaven but you? And there is nothing on earth that I desire besides you. My flesh and my heart may fail, but God is the strength of my heart and my portion forever.")]
            }
        }
    }

    @State private var clause = Clause.glory
    @State private var showsPrayer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PromisePreface(
                title: "Our first promise",
                text: "Question and answer together, at a pace you can see — never one you’re behind on."
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("SAMUEL · Q. 1")
                        .font(.ccDisplay(10.5)).tracking(1.68).foregroundStyle(.ccInk3)
                    Text("Q.  ").font(.ccDisplay(11, semibold: true)).foregroundStyle(.ccInk3)
                    + Text("What is the chief end of man?").font(.ccBody(17))
                    answer
                    Label("The scripture behind “\(clause.rawValue)”", systemImage: "circle.fill")
                        .font(.ccDisplay(10.5)).foregroundStyle(.ccGilt)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.ccGilt.opacity(0.12), in: Capsule())
                    ForEach(clause.passages, id: \.reference) { passage in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(passage.text).font(.ccBody(14)).lineSpacing(4)
                            Text(passage.reference.uppercased())
                                .font(.ccDisplay(9.5)).tracking(0.95).foregroundStyle(.ccInk3)
                        }
                    }
                    prayer
                    HStack(spacing: 12) {
                        Circle().strokeBorder(.ccGilt, lineWidth: 1.5).frame(width: 22, height: 22)
                            .overlay { Circle().fill(.ccGilt).frame(width: 9, height: 9) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scripture").font(.ccDisplay(12.5, semibold: true))
                            Text("1 of 3, after today — next stop: God")
                                .font(.ccBody(11.5)).foregroundStyle(.ccInk2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.ccGilt.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.vertical, 18)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(.ccSurface, in: RoundedRectangle(cornerRadius: 14))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.ccLine).allowsHitTesting(false) }
        }
    }

    // Clause markers are links inside one Text, so they wrap like the
    // prototype's inline spans: the chosen clause is ink on a gilt wash, the
    // other is muted with a dotted underline.
    private var answer: some View {
        Text(answerText)
            .lineSpacing(5)
            .tint(.ccInk)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "onboarding-proof" else { return .systemAction }
                clause = url.absoluteString.hasSuffix(":enjoyment") ? .enjoyment : .glory
                return .handled
            })
    }

    private var answerText: AttributedString {
        var lead = AttributedString("A. ")
        lead.font = .ccDisplay(11, semibold: true)
        lead.foregroundColor = .ccInk3
        var text = lead
        text += marker("Man’s chief end is to glorify God", clause: .glory, link: "glory")
        text += superscript("a")
        text += plain(", and ")
        text += marker("to enjoy him for ever", clause: .enjoyment, link: "enjoyment")
        text += superscript("b")
        text += plain(".")
        return text
    }

    private func plain(_ string: String) -> AttributedString {
        var run = AttributedString(string)
        run.font = .ccBody(17)
        run.foregroundColor = .ccInk
        return run
    }

    private func marker(_ string: String, clause marked: Clause, link: String) -> AttributedString {
        var run = AttributedString(string)
        run.font = .ccBody(17)
        run.link = URL(string: "onboarding-proof:\(link)")
        if marked == clause {
            run.foregroundColor = .ccInk
            run.backgroundColor = Color.ccGilt.opacity(0.12)
            run.underlineStyle = Text.LineStyle(pattern: .solid, color: .ccGilt)
        } else {
            run.foregroundColor = .ccInk3
            run.underlineStyle = Text.LineStyle(pattern: .dot, color: .ccInk3)
        }
        return run
    }

    private func superscript(_ letter: String) -> AttributedString {
        var run = AttributedString(letter)
        run.font = .ccDisplay(11)
        run.foregroundColor = .ccGilt
        run.baselineOffset = 7
        return run
    }

    private var prayer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                showsPrayer.toggle()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pray about this").font(.ccDisplay(12, semibold: true))
                        Text("A short prayer for Samuel, on this question")
                            .font(.ccBody(11.5)).foregroundStyle(.ccInk3)
                    }
                    Spacer()
                    Image(systemName: showsPrayer ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11)).foregroundStyle(.ccInk3)
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(.ccFill, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            if showsPrayer {
                Text("Lord, you made Samuel to know you and to enjoy you forever. Let every good thing today point him back to you. Amen.")
                    .font(.ccBody(14)).lineSpacing(4).foregroundStyle(.ccInk2)
            }
        }
    }
}

struct OnboardingSermonDemo: View {
    private struct Example {
        let kind: String
        let palette: QuoteCardPalette
        let text: String
        let attribution: String
    }

    private static let examples = [
        Example(kind: "Key point", palette: .vellum, text: "God does not promise that all things are good, but that he works all things together for good.", attribution: "From my notes"),
        Example(kind: "Verse", palette: .cloister, text: "And we know that for those who love God all things work together for good, for those who are called according to his purpose.", attribution: "Romans 8:28 · ESV"),
        Example(kind: "Quote", palette: .vespers, text: "“The chain of verse 30 has no weak link. Not one whom he called is missing at the end.”", attribution: "From your notes"),
        Example(kind: "Key point", palette: .ironstone, text: "“Who shall separate us?” is a question Paul asks so that you will answer it out loud: nothing.", attribution: "From my notes"),
        Example(kind: "Verse", palette: .hymnal, text: "No, in all these things we are more than conquerors through him who loved us.", attribution: "Romans 8:37 · ESV")
    ]

    @State private var current: Int? = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PromisePreface(
                title: "Our second promise",
                text: "Photograph Sunday’s notes, and let the word dwell in you richly — one sermon, many cards, open whenever you like."
            )
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Self.examples.indices, id: \.self) { index in
                        card(Self.examples[index])
                            .containerRelativeFrame(.vertical)
                            .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $current)
            .overlay(alignment: .trailing) {
                VStack(spacing: 7) {
                    ForEach(Self.examples.indices, id: \.self) { index in
                        Circle()
                            .fill(index == current
                                  ? Color(hex: Self.examples[index].palette.ink)
                                  : Color.gray.opacity(0.4))
                            .frame(width: 5, height: 5)
                    }
                }
                .padding(.trailing, 8)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            Text("Nothing here is Monday’s or Tuesday’s — open any card, any day.")
                .font(.ccBody(12)).foregroundStyle(.ccInk2)
        }
    }

    private func card(_ example: Example) -> some View {
        let palette = example.palette
        return VStack(alignment: .leading, spacing: 14) {
            Text(example.kind.uppercased())
                .font(.ccDisplay(10.5)).tracking(1.68).foregroundStyle(Color(hex: palette.accent))
            Text(example.text)
                .font(.ccBody(19)).lineSpacing(5)
            Text(example.attribution.uppercased())
                .font(.ccDisplay(9.5)).tracking(1.14).foregroundStyle(Color(hex: palette.muted))
            ShareLink(item: "\(example.text)\n\n\(example.attribution)") {
                Text("Share")
                    .font(.ccBody(12.5).weight(.semibold))
                    .padding(.horizontal, 12).frame(height: 32)
                    .foregroundStyle(Color(hex: palette.field))
                    .background(Color(hex: palette.ink), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .foregroundStyle(Color(hex: palette.ink))
        .background(Color(hex: palette.field))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(hex: palette.frame).opacity(0.5))
                .padding(14)
                .allowsHitTesting(false)
        }
    }
}
