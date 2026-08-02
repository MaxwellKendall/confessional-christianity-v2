// Mirrors src/app/(column)/programs/[slug]/session/milestones/MilestonesClient.tsx:
// a back arrow, "Milestones" heading, and rows with a circular state glyph
// (filled ochre check / ochre ring-with-dot / dashed muted ring) + title +
// caption. Programs without authored milestones render the honest
// "not yet mapped" empty state.
import SwiftUI
import DomainKit

struct MilestonesView: View {
    let program: ProgramDefinition
    let currentQuestion: Int

    @Environment(\.dismiss) private var dismiss

    private var definitions: [MilestoneDefinition] { milestonesFor(program.slug) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Text("\u{2190}").font(.ccDisplay(15)).foregroundStyle(.ccInk)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)

            Text("Milestones")
                .headingPage()
                .padding(.bottom, 8)

            if definitions.isEmpty {
                Text("Milestones haven\u{2019}t been mapped for this catechism yet.")
                    .font(.ccBody(13))
                    .italic()
                    .foregroundStyle(.ccInk2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                    .padding(.top, 32)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(milestoneProgress(definitions, currentQuestion: currentQuestion), id: \.definition.id) { progress in
                            MilestoneRow(progress: progress)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                }
            }
        }
        .background(Color.ccCard.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct MilestoneRow: View {
    let progress: MilestoneProgress

    private var caption: String {
        switch progress.state {
        case .complete:
            return "Reached"
        case .in_progress:
            let base = "\(progress.seenCount) of \(progress.total) questions"
            if let age = progress.definition.typicalAge {
                return "\(base) \u{00B7} typical for age \(age.0)\u{2013}\(age.1)"
            }
            return base
        case .locked:
            if let age = progress.definition.typicalAge {
                return "Typical for age \(age.0)\u{2013}\(age.1)"
            }
            return "Not yet reached"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            MilestoneCircle(state: progress.state)
            VStack(alignment: .leading, spacing: 3) {
                Text(progress.definition.title)
                    .font(.ccDisplay(13.5, semibold: true))
                    .foregroundStyle(.ccInk)
                Text(caption)
                    .font(.ccBody(12.5))
                    .italic()
                    .foregroundStyle(.ccInk3)
            }
            Spacer()
        }
        .padding(16)
        .background(progress.state == .complete ? Color.ccOchre.opacity(0.1) : Color.ccFill)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .opacity(progress.state == .locked ? 0.55 : 1)
    }
}

private struct MilestoneCircle: View {
    let state: MilestoneProgress.State

    var body: some View {
        Group {
            switch state {
            case .complete:
                Circle()
                    .fill(Color.ccOchre)
                    .overlay {
                        Text("\u{2713}").font(.system(size: 11)).foregroundStyle(.ccCard)
                    }
            case .in_progress:
                Circle()
                    .strokeBorder(Color.ccOchre, lineWidth: 1.5)
                    .overlay {
                        Circle().fill(Color.ccOchre).frame(width: 9, height: 9)
                    }
            case .locked:
                Circle()
                    .strokeBorder(Color.ccMuted, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            }
        }
        .frame(width: 22, height: 22)
    }
}
