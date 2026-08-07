// Mirrors src/app/(column)/devotions/[slug]/SeriesLandingClient.tsx: the
// whole arc laid out in order — parts done, the next one up, whatever's
// still ahead — with one Continue that jumps to wherever the household
// left off. Nothing is locked: every authored part stays reachable
// directly from the list; only an unauthored part is unreachable, and
// that's a content gap, not a lock.
import SwiftUI
import SwiftData
import DomainKit

struct DevotionSeriesView: View {
    let series: DevotionSeries
    @Binding var path: NavigationPath

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var completed: [Int] = []

    private var store: LocalSeriesProgressStore { LocalSeriesProgressStore(context: modelContext) }
    private var total: Int { series.parts.count }
    private var done: Set<Int> { Set(completed) }
    private var current: Int? { currentPartDay(completed, totalParts: total) }
    private var currentDevotion: Devotion? { current.flatMap { partDevotion(series, $0) } }

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

            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 6) {
                        Text("\(seriesSourceLabel(series)) \u{00B7} A \(total)-Part Series \u{00B7} \(series.tagline)")
                            .labelCaps(size: 9, tracking: 0.14, color: .ccOchre)
                            .multilineTextAlignment(.center)
                        Text(series.title)
                            .headingPage()
                        Text(series.description)
                            .font(.ccBody(13))
                            .italic()
                            .foregroundStyle(.ccInk2)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .padding(.top, 4)
                        Text(current == nil ? "All \(total) parts complete" : "Part \(current!) of \(total)")
                            .labelCaps(size: 10, tracking: 0.12)
                            .padding(.top, 10)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color.ccHairline)
                                Rectangle().fill(Color.ccOchre)
                                    .frame(width: geo.size.width * Double(done.count) / Double(max(total, 1)))
                            }
                        }
                        .frame(height: 3)
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 22)

                    VStack(spacing: 0) {
                        ForEach(series.parts, id: \.day) { part in
                            partRow(part)
                        }
                    }

                    Text("Every part is open \u{2014} read in order, or jump to any part directly.")
                        .font(.ccBody(11))
                        .italic()
                        .foregroundStyle(.ccInk3)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .padding(.horizontal, 24)
                        .padding(.top, 14)
                }
                .padding(.bottom, 24)
            }

            VStack {
                if current == nil {
                    Text("This household has prayed the whole series, beginning to end.")
                        .font(.ccBody(12.5))
                        .italic()
                        .foregroundStyle(.ccInk2)
                        .multilineTextAlignment(.center)
                } else if let currentDevotion {
                    Button {
                        path.append(DevotionRoute.devotion(currentDevotion.slug))
                    } label: {
                        Text(done.count > 0 ? "Continue \u{2014} Part \(current!)" : "Begin \u{2014} Part 1")
                            .labelCaps(size: 11, tracking: 0.1, color: .ccCard)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(Color.ccInk)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                } else {
                    Text("Part \(current!) is still being prepared \u{2014} the series continues soon.")
                        .font(.ccBody(12.5))
                        .italic()
                        .foregroundStyle(.ccInk2)
                        .multilineTextAlignment(.center)
                }
            }
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
        .task {
            completed = store.getCompletedDays(series.slug)
        }
    }

    @ViewBuilder
    private func partRow(_ part: SeriesPart) -> some View {
        let devotion = partDevotion(series, part.day)
        let isDone = done.contains(part.day)
        let isCurrent = part.day == current
        let label = "Part \(part.day) \u{2014} \(part.title) (\(part.citation))"

        if let devotion {
            Button {
                path.append(DevotionRoute.devotion(devotion.slug))
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Text(isDone ? "\u{2713}" : (isCurrent ? "\u{25CF}" : "\u{25CB}"))
                        .font(.ccDisplay(10))
                        .foregroundStyle(.ccOchre)
                        .opacity(isCurrent ? 1 : 0.6)
                        .frame(width: 16)
                    Text(label)
                        .font(.ccBody(13))
                        .fontWeight(isCurrent ? .semibold : .regular)
                        .foregroundStyle(isDone ? .ccInk3 : .ccInk)
                        .multilineTextAlignment(.leading)
                    Spacer()
                }
                .padding(.horizontal, isCurrent ? 12 : 15)
                .padding(.vertical, isCurrent ? 12 : 10)
                .background(isCurrent ? Color.ccFill : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, isCurrent ? 12 : 0)
            .overlay(alignment: .bottom) {
                if !isCurrent { Rectangle().fill(Color.ccFill).frame(height: 1) }
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                Color.clear.frame(width: 16, height: 1)
                Text("\(label) \u{2014} in preparation")
                    .font(.ccBody(13))
                    .foregroundStyle(.ccMuted)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.ccFill).frame(height: 1)
            }
        }
    }
}
