// Mirrors src/components/WorshipShell.tsx fed a devotion's fixed steps
// (src/app/(column)/devotions/[slug]/worship/DevotionWorshipClient.tsx):
// one step per screen, a dot progress indicator, and the typed-element
// renderer every service shares. Step 5 (Professing Faith) hands off to
// the shared SessionView, which returns here at the following step once
// the household has answered — DevotionRoute.catechismHandoff carries that
// return address since this app has no URL layer to carry a query param.
import SwiftUI
import SwiftData
import DomainKit

struct DevotionWorshipView: View {
    let devotion: Devotion
    let startStep: Int
    @Binding var path: NavigationPath

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var stepNumber: Int
    @State private var handoffProgram: ProgramDefinition?
    @State private var handoffQuestionNumber: Int = 1
    /// Which edge the next step enters from — mirrors SessionView's paging
    /// direction so a step advance and a step back read as opposite swipes,
    /// not the same generic transition.
    @State private var navDirection: Edge = .trailing

    init(devotion: Devotion, startStep: Int, path: Binding<NavigationPath>) {
        self.devotion = devotion
        self.startStep = startStep
        self._path = path
        self._stepNumber = State(initialValue: min(max(startStep, 1), devotion.steps.count))
    }

    private var membership: SeriesMembership? { seriesMembership(devotion) }
    private var totalSteps: Int { devotion.steps.count }
    private var step: WorshipStep { devotion.steps[stepNumber - 1] }
    private var isCatechismStep: Bool { step.elements.contains { $0.typeName == "catechism" } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    goBack()
                } label: {
                    Text(stepNumber > 1 ? "\u{2190}" : "\u{2715}")
                        .font(.ccDisplay(15))
                        .foregroundStyle(.ccInk)
                }
                .buttonStyle(.plain)
                Spacer()
                HStack(spacing: 5) {
                    ForEach(0..<totalSteps, id: \.self) { i in
                        Circle()
                            .fill(i < stepNumber - 1 ? Color.ccInk : (i == stepNumber - 1 ? Color.ccOchre : Color.clear))
                            .overlay {
                                if i > stepNumber - 1 { Circle().strokeBorder(Color.ccHairline, lineWidth: 1) }
                            }
                            .frame(width: 6, height: 6)
                    }
                }
                Spacer()
                Button {
                    path.removeLast(path.count)
                } label: {
                    Image(systemName: "house")
                        .font(.system(size: 15))
                        .foregroundStyle(.ccInk)
                        .frame(width: 15, height: 15)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            // Mirrors the web shell's `justify-center`: a step's content sits
            // centered in the space between header and footer regardless of
            // how short it is (a one-line "Confessing Sin" prompt shouldn't
            // leave a dead gap up top) — but still scrolls normally once
            // content is taller than the available height.
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 18) {
                        Spacer(minLength: 0)

                        Text("Step \(stepNumber) \u{00B7} \(step.role)")
                            .labelCaps(size: 9, tracking: 0.14, color: .ccOchre)

                        ForEach(Array(step.elements.enumerated()), id: \.offset) { _, element in
                            ElementView(element: element, handoffProgram: handoffProgram, handoffQuestionNumber: handoffQuestionNumber) {
                                path.append(DevotionRoute.catechismHandoff(
                                    programSlug: (handoffProgram ?? PROGRAMS[0]).slug,
                                    devotionSlug: devotion.slug,
                                    returnStep: stepNumber + 1
                                ))
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 28)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
                    .id(stepNumber)
                    .transition(.asymmetric(
                        insertion: .move(edge: navDirection).combined(with: .opacity),
                        removal: .move(edge: navDirection == .trailing ? .leading : .trailing).combined(with: .opacity)
                    ))
                }
            }

            VStack {
                if isCatechismStep {
                    Text("The question returns to this devotion at step \(stepNumber + 1) when you\u{2019}ve finished")
                        .font(.ccBody(11.5))
                        .italic()
                        .foregroundStyle(.ccMuted)
                        .multilineTextAlignment(.center)
                } else if stepNumber < totalSteps {
                    Button {
                        advance()
                    } label: {
                        Text("Continue \u{2192}")
                            .labelCaps(size: 11, tracking: 0.08, color: .ccInk)
                            .dottedUnderline(.ccInk)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        finish()
                    } label: {
                        Text("Finish")
                            .labelCaps(size: 11, tracking: 0.1, color: .ccCard)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .background(Color.ccInk)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 32)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.ccHairline).frame(height: 1)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .background(Color.ccCard.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .hidesFloatingTabBar()
        .contentShape(Rectangle())
        .simultaneousGesture(
            // Only a clearly-horizontal drag counts, so it doesn't fight the
            // step content's own vertical ScrollView.
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    guard abs(horizontal) > abs(vertical), abs(horizontal) > 60 else { return }
                    if horizontal < 0 {
                        advance()
                    } else {
                        goBack()
                    }
                }
        )
        .task {
            loadHandoff()
        }
    }

    private func goBack() {
        guard stepNumber > 1 else {
            dismiss()
            return
        }
        navDirection = .leading
        withAnimation(.easeInOut(duration: 0.28)) { stepNumber -= 1 }
    }

    private func advance() {
        guard !isCatechismStep else { return }
        guard stepNumber < totalSteps else {
            finish()
            return
        }
        navDirection = .trailing
        withAnimation(.easeInOut(duration: 0.28)) { stepNumber += 1 }
    }

    private func loadHandoff() {
        let store = LocalProgressStore(context: modelContext)
        let track = store.activeTrack()
        let program = track.flatMap { t in PROGRAMS.first { $0.contentId.rawValue == t.catechismId } } ?? PROGRAMS[0]
        handoffProgram = program
        handoffQuestionNumber = track.map { min($0.currentQuestion, program.totalQuestions) } ?? 1
    }

    private func finish() {
        if let membership {
            LocalSeriesProgressStore(context: modelContext).recordCompletion(
                seriesSlug: membership.series.slug, day: membership.part.day
            )
            path.append(DevotionRoute.series(membership.series.slug))
        } else {
            path.append(DevotionRoute.devotion(devotion.slug))
        }
    }
}

private struct SourceLine: View {
    let source: ElementSource

    private var label: some View {
        Text(source.label + ((source.external ?? false) ? " \u{2197}" : " \u{203A}"))
            .font(.ccBody(11.5))
            .italic()
            .foregroundStyle(.ccMuted)
            .dottedUnderline(.ccMuted)
            .padding(.top, 4)
    }

    var body: some View {
        if let url = URL(string: source.href) {
            Link(destination: url) { label }
        } else {
            label
        }
    }
}

private struct Lede: View {
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Text(text)
                .font(.ccBody(13.5))
                .italic()
                .foregroundStyle(.ccInk2)
                .lineSpacing(4)
            Rectangle().fill(Color.ccHairline).frame(width: 36, height: 1)
        }
    }
}

private struct ElementView: View {
    let element: WorshipElement
    let handoffProgram: ProgramDefinition?
    let handoffQuestionNumber: Int
    let onTapCatechism: () -> Void

    var body: some View {
        switch element {
        case .scripture(let lede, let citation, _, let text, let source):
            VStack(spacing: 10) {
                if let lede { Lede(text: lede) }
                Text(citation)
                    .font(.ccDisplay(12.5))
                    .italic()
                    .foregroundStyle(.ccInk3)
                Text("\u{201C}\(text)\u{201D}")
                    .font(.ccBody(17))
                    .italic()
                    .foregroundStyle(.ccInk)
                    .lineSpacing(6)
                if let source { SourceLine(source: source) }
            }
        case .prayer(let lede, let text, let amen, let source):
            VStack(spacing: 10) {
                if let lede { Lede(text: lede) }
                Text(text)
                    .font(.ccBody(14.5))
                    .foregroundStyle(.ccInk)
                    .lineSpacing(7)
                if amen {
                    Text("Amen").labelCaps(size: 11, tracking: 0.1, color: .ccOchre)
                }
                if let source { SourceLine(source: source) }
            }
        case .song(let lede, let title, let lyrics, let source):
            VStack(spacing: 12) {
                if let lede { Lede(text: lede) }
                Text(title).font(.ccDisplay(15, semibold: true)).foregroundStyle(.ccInk)
                Text(lyrics)
                    .font(.ccBody(17))
                    .italic()
                    .foregroundStyle(.ccInk)
                    .lineSpacing(9)
                if let source { SourceLine(source: source) }
            }
        case .creed(let lede, let title, let text, let source):
            VStack(spacing: 12) {
                if let lede { Lede(text: lede) }
                Text(title).font(.ccDisplay(15, semibold: true)).foregroundStyle(.ccInk)
                Text(text)
                    .font(.ccBody(17))
                    .italic()
                    .foregroundStyle(.ccInk)
                    .lineSpacing(9)
                if let source { SourceLine(source: source) }
            }
        case .instruction(let text):
            VStack(spacing: 14) {
                Rectangle().fill(Color.ccHairline).frame(width: 36, height: 1)
                Text(text)
                    .font(.ccBody(12.5))
                    .italic()
                    .foregroundStyle(.ccInk2)
                    .lineSpacing(4)
            }
        case .prompts(let lede, let items):
            VStack(alignment: .leading, spacing: 10) {
                if let lede {
                    Text(lede)
                        .font(.ccBody(12.5))
                        .italic()
                        .foregroundStyle(.ccInk2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                ForEach(items, id: \.label) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.label).labelCaps(size: 9, tracking: 0.1, color: .ccOchre)
                        Text(item.text)
                            .font(.ccBody(12.5))
                            .italic()
                            .foregroundStyle(.ccInk)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.ccFill)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .catechism(let lede):
            VStack(spacing: 12) {
                if let lede { Lede(text: lede) }
                if let handoffProgram {
                    Button {
                        onTapCatechism()
                    } label: {
                        VStack(spacing: 8) {
                            Text("Question \(handoffQuestionNumber) of \(handoffProgram.totalQuestions)")
                                .labelCaps(size: 9, tracking: 0.1, color: .ccOchre)
                            Text(getQuestion(handoffProgram, handoffQuestionNumber)?.question ?? "")
                                .font(.ccBody(15))
                                .italic()
                                .foregroundStyle(.ccInk)
                                .multilineTextAlignment(.center)
                            Text("Answer Together \u{2192}")
                                .labelCaps(size: 10, tracking: 0.08, color: .ccOchre)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity)
                        .background(Color.ccOchre.opacity(0.1))
                        .overlay {
                            RoundedRectangle(cornerRadius: 3).strokeBorder(Color.ccOchre, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
