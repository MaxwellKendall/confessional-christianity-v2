// Mirrors src/app/(column)/programs/[slug]/prayer/[questionNumber]/PrayerClient.tsx:
// "Pray About This" as its own screen — a back arrow, the ochre question
// counter, a hairline rule, the prayer itself in serif italic, and an
// "Amen" label. Falls back to an honest not-yet-written state.
import SwiftUI
import DomainKit

struct PrayerView: View {
    let program: ProgramDefinition
    let questionNumber: Int
    /// Guest sessions have no captured child name yet (no account in v1);
    /// the prayer's {name} substitution uses a generic placeholder until
    /// account/child profiles ship.
    var childName: String = "your child"

    @Environment(\.dismiss) private var dismiss

    private var question: ProgramQuestion? { getQuestion(program, questionNumber) }
    private var prayer: String? { getPrayer(program, questionNumber, childName: childName) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Text("\u{2190}")
                        .font(.ccDisplay(15))
                        .foregroundStyle(.ccInk)
                }
                .buttonStyle(.plain)
                Spacer()
                if let question {
                    Text("Question \(questionNumber) of \(program.totalQuestions)")
                        .labelCaps(size: 9.5, color: .ccOchre)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            Spacer(minLength: 0)

            VStack(spacing: 0) {
                if let question {
                    Text("A Prayer on \u{201C}\(question.question.trimmingSuffix("?"))\u{201D}")
                        .labelCaps(size: 9, tracking: 0.14)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 20)
                }

                Rectangle().fill(Color.ccHairline).frame(width: 36, height: 1)
                    .padding(.bottom, 24)

                if let prayer {
                    Text(prayer)
                        .font(.ccBody(15.5))
                        .italic()
                        .foregroundStyle(.ccInk)
                        .multilineTextAlignment(.center)
                        .lineSpacing(9)
                    Text("Amen")
                        .labelCaps(size: 11, tracking: 0.1, color: .ccOchre)
                        .padding(.top, 22)
                } else {
                    Text("The prayer for this question isn\u{2019}t written yet \u{2014} close in your own words.")
                        .font(.ccBody(13))
                        .italic()
                        .foregroundStyle(.ccHeartReviewing)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 36)

            Spacer(minLength: 0)

            VStack {
                Button {
                    dismiss()
                } label: {
                    Text("Back to the Question")
                        .labelCaps(size: 11, tracking: 0.1, color: .ccInk)
                        .dottedUnderline(.ccInk)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 18)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.ccHairline).frame(height: 1)
            }
        }
        .background(Color.ccCard.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .hidesFloatingTabBar()
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
