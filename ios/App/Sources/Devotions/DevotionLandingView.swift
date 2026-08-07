// Mirrors the devotion branch of src/app/(column)/devotions/[slug]/page.tsx:
// what's inside, why it's grounded this way, an ordered preview of the
// eight steps, and a "Begin This Devotion" hand-off into the worship
// stepper.
import SwiftUI
import DomainKit

struct DevotionLandingView: View {
    let devotion: Devotion
    @Binding var path: NavigationPath

    @Environment(\.dismiss) private var dismiss

    private var membership: SeriesMembership? { seriesMembership(devotion) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 6) {
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Text("\u{2190}").font(.ccDisplay(15)).foregroundStyle(.ccInk)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.bottom, 10)

                    if let membership {
                        Button {
                            path.append(DevotionRoute.series(membership.series.slug))
                        } label: {
                            Text("Part \(membership.part.day) of \(membership.series.parts.count) \u{00B7} \(membership.series.title)")
                                .labelCaps(size: 9, tracking: 0.14, color: .ccOchre)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("Grounded in \(groundingLabel(devotion.grounding))")
                            .labelCaps(size: 9, tracking: 0.14, color: .ccOchre)
                    }

                    Text(devotion.title)
                        .headingPage()
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)

                    Text(devotion.description)
                        .font(.ccBody(13))
                        .italic()
                        .foregroundStyle(.ccInk2)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.top, 6)

                    Rectangle().fill(Color.ccHairline).frame(width: 36, height: 1)
                        .padding(.top, 18)
                        .padding(.bottom, 4)

                    VStack(spacing: 0) {
                        ForEach(Array(devotion.steps.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text("\(i + 1)")
                                    .font(.ccDisplay(10))
                                    .foregroundStyle(.ccOchre)
                                    .frame(width: 18, alignment: .leading)
                                Text(stepPreviewLabel(step))
                                    .font(.ccBody(13))
                                    .foregroundStyle(.ccInk)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                            }
                            .padding(.vertical, 10)
                            .overlay(alignment: .bottom) {
                                if i < devotion.steps.count - 1 {
                                    Rectangle().fill(Color.ccFill).frame(height: 1)
                                }
                            }
                        }
                    }
                    .padding(.top, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }

            Button {
                path.append(DevotionRoute.worship(slug: devotion.slug, startStep: 1))
            } label: {
                Text("Begin This Devotion")
                    .labelCaps(size: 11, tracking: 0.1, color: .ccCard)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Color.ccInk)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 32)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.ccHairline).frame(height: 1)
            }
        }
        .background(Color.ccCard.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .hidesFloatingTabBar()
    }

    private func stepPreviewLabel(_ step: WorshipStep) -> String {
        let isCatechism = step.elements.first?.typeName == "catechism"
        let detail = isCatechism ? "today\u{2019}s question" : stepDetail(step)
        return detail.map { "\(step.role) \u{2014} \($0)" } ?? step.role
    }
}
