// Mirrors src/app/(column)/programs/[slug]/session/QuestionCard.tsx: the
// catechism answer with every clause cited in-line, one clause's proof
// text shown at a time, and a "Pray About This" entry point one tap away.
//
// Note: unlike the web version, this does not live-fetch ESV passage text
// (that would need the /api/esv proxy — deferred per the implementation
// plan's Phase 1 scope, which keeps the core session flow fully offline).
// Where the web shows the fetched verse text, this shows the citation
// itself — the one honest thing we actually have bundled.
import SwiftUI
import DomainKit

private let maxClauseLabelLength = 26

private func truncateClause(_ text: String) -> String {
    var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    while let last = trimmed.last, ".,;:".contains(last) {
        trimmed.removeLast()
    }
    if trimmed.count <= maxClauseLabelLength { return trimmed }
    let cut = String(trimmed.prefix(maxClauseLabelLength))
    if let lastSpace = cut.range(of: " ", options: .backwards) {
        return String(cut[..<lastSpace.lowerBound]) + "\u{2026}"
    }
    return cut + "\u{2026}"
}

struct QuestionCardView: View {
    let program: ProgramDefinition
    let question: ProgramQuestion

    @State private var activeMarker: String?

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

                VStack(spacing: 12) {
                    ForEach(activeGroup?.refs ?? [], id: \.osis) { ref in
                        Text(ref.citation)
                            .font(.ccBody(15))
                            .italic()
                            .foregroundStyle(.ccInk)
                            .multilineTextAlignment(.center)
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
