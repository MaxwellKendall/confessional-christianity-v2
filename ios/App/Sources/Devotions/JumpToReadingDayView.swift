// Mirrors JumpToQuestionView's shape (back arrow + label-caps title, a pill
// search field, a "Days 1–N" / "N Matches" caption, a plain row list) for
// the reading plan's "skip ahead" case: a reader already partway through
// this plan elsewhere just wants to jump straight to their real day and
// keep going, not tap or swipe their way there one day at a time.
import SwiftUI
import DomainKit

struct JumpToReadingDayView: View {
    let plan: ReadingPlanDefinition
    let currentDay: Int
    let completedDays: Set<Int>
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var allDays: [ReadingPlanDay] { getReadingPlanSchedule(plan) }

    private var filtered: [ReadingPlanDay] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return allDays }
        return allDays.filter {
            String($0.day) == q || $0.citation.lowercased().contains(q)
        }
    }

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
                Text("Jump to Day").labelCaps(size: 10, tracking: 0.14)
                Spacer()
                Color.clear.frame(width: 15, height: 1)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.ccInk3)
                    .font(.system(size: 13))
                TextField("Search by day or passage\u{2026}", text: $search)
                    .font(.ccBody(13.5))
                    .italic()
                    .foregroundStyle(.ccInk)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color.ccFill))
            .padding(.horizontal, 20)

            HStack {
                Text(query
                     ? "\(filtered.count) Match\(filtered.count == 1 ? "" : "es")"
                     : "Days 1\u{2013}\(allDays.count)")
                    .labelCaps(size: 9.5, tracking: 0.1)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)

            if filtered.isEmpty {
                Text("No days match \u{201C}\(search)\u{201D}.")
                    .font(.ccBody(13))
                    .italic()
                    .foregroundStyle(.ccInk2)
                    .padding(.top, 24)
                Spacer()
            } else {
                List(filtered, id: \.day) { item in
                    let active = item.day == currentDay
                    let isDone = completedDays.contains(item.day)
                    Button {
                        onSelect(item.day)
                        dismiss()
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Text("\(item.day)")
                                .font(.ccDisplay(14))
                                .foregroundStyle(active ? .ccOchre : .ccInk3)
                                .frame(width: 36, alignment: .leading)
                            Text(item.citation)
                                .font(.ccBody(15))
                                .italic()
                                .foregroundStyle(.ccInk)
                            Spacer()
                            if isDone {
                                Text("\u{2713}")
                                    .font(.ccDisplay(12))
                                    .foregroundStyle(.ccOchre)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(active ? Color.ccOchre.opacity(0.1) : Color.ccCard)
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color.ccCard.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var query: Bool { !search.trimmingCharacters(in: .whitespaces).isEmpty }
}
