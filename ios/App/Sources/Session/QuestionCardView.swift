// Mirrors src/app/(column)/programs/[slug]/session/QuestionCard.tsx: the
// catechism answer with every clause cited in-line, one clause's proof
// text shown at a time (live ESV text fetched through EsvClient, same
// /api/esv proxy the web app uses), and a "Pray About This" entry point one
// tap away. Each citation links out to its scripture cross-reference page
// (ScriptureView), same as Library's proof-texts panel.
import SwiftUI
import DomainKit

struct QuestionCardView: View {
    let program: ProgramDefinition
    let question: ProgramQuestion
    @Binding var path: NavigationPath

    @State private var activeMarker: String?
    @State private var verseTexts: [String: String?] = [:]

    private var citations: (answerSegments: [TextSegment], groups: [ProofTextGroup])? {
        getQuestionCitations(program, question.number)
    }

    private var activeGroup: ProofTextGroup? {
        citations?.groups.first { $0.marker == activeMarker }
    }

    private var activeSegmentLabel: String? {
        guard let segment = citations?.answerSegments.first(where: { $0.marker == activeMarker }) else { return nil }
        return truncateClause(segment.text)
    }

    private func resolvedVerseText(_ ref: ProofTextRef) -> String {
        guard let stored = verseTexts[ref.osis] else { return "\u{2026}" }
        return stored ?? ref.citation
    }

    private func loadVerseTexts() async {
        guard let group = activeGroup else { return }
        await withTaskGroup(of: (String, String?).self) { taskGroup in
            for ref in group.refs where verseTexts[ref.osis] == nil {
                taskGroup.addTask { (ref.osis, await EsvClient.shared.text(for: ref.osis)) }
            }
            for await (osis, text) in taskGroup {
                verseTexts.updateValue(text, forKey: osis)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            (Text("Q. ") + Text(question.question))
                .font(.ccBody(18))
                .italic()
                .foregroundStyle(.ccInk)

            Spacer().frame(height: 18)

            answerFlow

            if let groups = citations?.groups, !groups.isEmpty {
                Spacer().frame(height: 28)

                Text("The Scripture Behind It")
                    .labelCaps(size: 9)
                    .frame(maxWidth: .infinity)

                if groups.count > 1, let label = activeSegmentLabel {
                    HStack(spacing: 6) {
                        Circle().fill(Color.ccOchre).frame(width: 6, height: 6)
                        Text("Now Showing \u{2014} \u{201C}\(label)\u{201D}")
                            .labelCaps(size: 9, tracking: 0.1, color: .ccOchre)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.ccOchre.opacity(0.1)))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
                }

                VStack(spacing: 14) {
                    ForEach(activeGroup?.refs ?? [], id: \.osis) { ref in
                        VStack(spacing: 4) {
                            Text(resolvedVerseText(ref))
                                .font(.ccBody(15))
                                .italic()
                                .foregroundStyle(.ccInk)
                                .multilineTextAlignment(.center)
                            Button {
                                path.append(ScriptureRoute.detail(osis: ref.osis))
                            } label: {
                                Text(ref.citation)
                                    .labelCaps(size: 9, tracking: 0.1, color: .ccInk3)
                                    .dottedUnderline(.ccInk3)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(minHeight: 70)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)

                if groups.count > 1 {
                    Text("Tap the other phrase above to see its verse")
                        .font(.ccBody(11))
                        .italic()
                        .foregroundStyle(.ccMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
            }

            Spacer().frame(height: 28)

            NavigationLink {
                PrayerView(program: program, questionNumber: question.number)
            } label: {
                ActionRow(
                    title: "Pray About This",
                    subtitle: "A short prayer for your child, on this question"
                )
            }
            .buttonStyle(.plain)
        }
        .onAppear { activeMarker = citations?.groups.first?.marker }
        .onChange(of: question.number) { _, _ in
            activeMarker = citations?.groups.first?.marker
        }
        .task(id: "\(question.number)|\(activeMarker ?? "")") {
            await loadVerseTexts()
        }
    }

    @ViewBuilder
    private var answerFlow: some View {
        if let segments = citations?.answerSegments, !segments.isEmpty {
            FlowText(prefix: "A. ", segments: segments, activeMarker: activeMarker) { marker in
                withAnimation(.easeOut(duration: 0.15)) { activeMarker = marker }
            }
        } else {
            (Text("A. ") + Text(question.answer))
                .font(.ccBody(18))
                .italic()
                .foregroundStyle(.ccInk)
        }
    }
}

private struct ActionRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ccDisplay(12.5, semibold: true)).foregroundStyle(.ccInk)
                Text(subtitle).font(.ccBody(11.5)).italic().foregroundStyle(.ccInk3)
            }
            Spacer(minLength: 8)
            Text("\u{203A}").font(.ccDisplay(13)).foregroundStyle(.ccInk3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.ccFill)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct CompletionView: View {
    let program: ProgramDefinition

    var body: some View {
        VStack(spacing: 10) {
            Text("Catechism Complete")
                .headingPage()
            Text("Every question has been seen. Back to the catechism to begin again, or browse another catechism.")
                .font(.ccBody(13))
                .italic()
                .foregroundStyle(.ccInk2)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(.horizontal, 36)
        .padding(.top, 56)
    }
}
