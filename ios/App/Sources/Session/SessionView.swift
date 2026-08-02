// Mirrors src/app/(column)/programs/[slug]/session/SessionClient.tsx: the
// question header ("Question N of Total ▾" opens Jump), the QuestionCard
// centered in the frame, and a hairline-topped footer with Prev/Next plus
// a "See Milestones →" link. Local progress via LocalProgressStore mirrors
// useSessionTrack.ts's resume/advance/jump semantics.
import SwiftUI
import SwiftData
import DomainKit

struct SessionView: View {
    let program: ProgramDefinition

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var track: LocalCatechismTrack?
    @State private var showJump = false
    @State private var showMilestones = false
    @State private var notificationsOffered = false

    private var store: LocalProgressStore { LocalProgressStore(context: modelContext) }

    private var questionNumber: Int? {
        guard let track else { return nil }
        return min(track.currentQuestion, program.totalQuestions)
    }

    private var isComplete: Bool {
        guard let track else { return false }
        return track.currentQuestion > program.totalQuestions
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.ccCard.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    Group {
                        if track == nil {
                            Color.clear.frame(height: 1)
                        } else if isComplete {
                            CompletionView(program: program)
                        } else if let questionNumber, let question = getQuestion(program, questionNumber) {
                            QuestionCardView(program: program, question: question)
                        } else {
                            CompletionView(program: program)
                        }
                    }
                    .padding(.horizontal, 34)
                    .padding(.vertical, 24)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }

                if !isComplete, track != nil {
                    footer
                }
            }

            Button {
                dismiss()
            } label: {
                Text("\u{2039}")
                    .font(.ccDisplay(20))
                    .foregroundStyle(.ccInk)
                    .frame(width: 44, height: 44, alignment: .center)
            }
            .padding(.leading, 6)
            .padding(.top, 6)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showJump) {
            JumpToQuestionView(program: program, currentQuestion: track?.currentQuestion ?? 1) { number in
                jump(to: number)
            }
        }
        .sheet(isPresented: $showMilestones) {
            MilestonesView(program: program, currentQuestion: track?.currentQuestion ?? 1)
        }
        .task {
            load()
            await offerNotificationsIfNeeded()
        }
    }

    private var header: some View {
        VStack(spacing: 5) {
            Text(program.title)
                .labelCaps(size: 9.5)
            Button {
                showJump = true
            } label: {
                Text("Question \(track?.currentQuestion ?? 1) of \(program.totalQuestions) \u{25BE}")
                    .labelCaps(size: 9.5, color: .ccOchre)
                    .dottedUnderline(.ccOchre)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 22)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 14) {
            HStack {
                if (track?.currentQuestion ?? 1) > 1 {
                    Button {
                        jump(to: (track?.currentQuestion ?? 1) - 1)
                    } label: {
                        Text("\u{2190} Prev").labelCaps(size: 11, tracking: 0.1, color: .ccInk3)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 1)
                }
                Spacer()
                Button {
                    advance()
                } label: {
                    Text("Next \u{2192}")
                        .labelCaps(size: 11, tracking: 0.1, color: .ccInk)
                        .dottedUnderline(.ccInk)
                }
                .buttonStyle(.plain)
            }

            Button {
                showMilestones = true
            } label: {
                Text("See Milestones \u{2192}")
                    .font(.ccBody(11.5))
                    .italic()
                    .foregroundStyle(.ccInk3)
                    .dottedUnderline(.ccInk3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 40)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.ccHairline).frame(height: 1)
        }
    }

    private func load() {
        track = store.resumeOrStartTrack(catechismId: program.contentId.rawValue)
    }

    private func advance() {
        track = store.advanceQuestion(catechismId: program.contentId.rawValue, totalQuestions: program.totalQuestions)
    }

    private func jump(to number: Int) {
        track = store.jumpToQuestion(
            catechismId: program.contentId.rawValue, questionNumber: number, totalQuestions: program.totalQuestions
        )
    }

    // Offered once per session view, not gated behind a settings screen —
    // v1 keeps this to the single most valuable native touch point (daily
    // practice reminder) rather than building out a full notifications UI.
    private func offerNotificationsIfNeeded() async {
        guard !notificationsOffered else { return }
        notificationsOffered = true
        guard await PracticeReminderScheduler.requestAuthorizationIfNeeded() else { return }
        PracticeReminderScheduler.scheduleDaily(hour: 17, minute: 0, programTitle: program.shortTitle)
    }
}
