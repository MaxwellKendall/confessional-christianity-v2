// A reading plan's home: one day at a time, mirroring SessionView's
// question-card shape rather than DevotionSeriesView's part list — a tap
// grid of 365 tiny numbers was both too small to hit reliably and the wrong
// interaction for a plan that's read sequentially. Swipe left/right (same
// convention as SessionView/DevotionWorshipView) pages through days; the
// "Day N of Total ▾" header opens the same jump-to-anywhere sheet pattern
// as JumpToQuestionView, for a reader who's already ahead elsewhere and
// wants to catch this device up to their real day in one move. Marking a
// day toggles — reading plan days, unlike devotion series parts, get
// jumped to and from freely enough that mis-marks need an undo.
import SwiftUI
import SwiftData
import DomainKit

struct ReadingPlanView: View {
    let plan: ReadingPlanDefinition
    @Binding var path: NavigationPath

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var completed: [Int] = []
    @State private var viewedDay = 1
    @State private var loaded = false
    @State private var showJump = false
    /// Which edge the incoming day card enters from — mirrors SessionView's
    /// navDirection, set just before each state change so paging forward vs.
    /// jumping backward reads as opposite slide directions.
    @State private var navDirection: Edge = .trailing

    private var store: LocalReadingPlanProgressStore { LocalReadingPlanProgressStore(context: modelContext) }
    private var done: Set<Int> { Set(completed) }
    private var progressPct: Double { Double(done.count) / Double(max(plan.totalDays, 1)) }
    private var viewedReading: ReadingPlanDay? { getReadingPlanDay(plan, viewedDay) }
    private var isViewedDone: Bool { done.contains(viewedDay) }

    var body: some View {
        VStack(spacing: 0) {
            header

            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)

                        if loaded, let viewedReading {
                            dayCard(viewedReading)
                                .frame(maxWidth: 560)
                                .frame(maxWidth: .infinity)
                                .id(viewedDay)
                                .transition(.asymmetric(
                                    insertion: .move(edge: navDirection).combined(with: .opacity),
                                    removal: .move(edge: navDirection == .trailing ? .leading : .trailing).combined(with: .opacity)
                                ))
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 34)
                    .padding(.vertical, 24)
                    .frame(minHeight: geo.size.height)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 24)
                        .onEnded { value in
                            guard loaded else { return }
                            let horizontal = value.translation.width
                            let vertical = value.translation.height
                            guard abs(horizontal) > abs(vertical), abs(horizontal) > 60 else { return }
                            if horizontal < 0 {
                                goNext()
                            } else {
                                goPrev()
                            }
                        }
                )
            }

            footer
        }
        .ignoresSafeArea(edges: .bottom)
        .background(Color.ccCard.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .hidesFloatingTabBar()
        .sheet(isPresented: $showJump) {
            JumpToReadingDayView(plan: plan, currentDay: viewedDay, completedDays: done) { day in
                jump(to: day)
            }
        }
        .task {
            completed = store.getCompletedDays(plan.slug)
            viewedDay = currentPartDay(completed, totalParts: plan.totalDays) ?? plan.totalDays
            loaded = true
        }
    }

    private var header: some View {
        VStack(spacing: 5) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Text("\u{2190}").font(.ccDisplay(15)).foregroundStyle(.ccInk)
                }
                .buttonStyle(.plain)
                Spacer()
            }

            Text(plan.title).labelCaps(size: 9.5)

            Button {
                showJump = true
            } label: {
                Text("Day \(viewedDay) of \(plan.totalDays) \u{25BE}")
                    .labelCaps(size: 9.5, color: .ccOchre)
                    .dottedUnderline(.ccOchre)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func dayCard(_ reading: ReadingPlanDay) -> some View {
        VStack(spacing: 18) {
            Text(isViewedDone ? "Read" : "Not Yet Read")
                .labelCaps(size: 9, tracking: 0.14, color: isViewedDone ? .ccOchre : .ccInk3)

            Text(reading.citation)
                .headingPage()
                .multilineTextAlignment(.center)

            Text("Swipe to browse other days")
                .font(.ccBody(12.5))
                .italic()
                .foregroundStyle(.ccInk3)

            Button {
                toggleDone()
            } label: {
                Text(isViewedDone ? "Mark as Not Done" : "Mark as Done")
                    .labelCaps(size: 11, tracking: 0.1, color: isViewedDone ? .ccInk : .ccCard)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
            .background(isViewedDone ? Color.ccFill : Color.ccInk)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay {
                if isViewedDone {
                    RoundedRectangle(cornerRadius: 3).stroke(Color.ccHairline, lineWidth: 1)
                }
            }
            .padding(.top, 10)
        }
    }

    private var footer: some View {
        VStack(spacing: 16) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.ccHairline)
                    Rectangle().fill(Color.ccOchre).frame(width: geo.size.width * progressPct)
                }
            }
            .frame(height: 3)

            HStack {
                if viewedDay > 1 {
                    Button {
                        goPrev()
                    } label: {
                        Text("\u{2190} Prev").labelCaps(size: 11, tracking: 0.1, color: .ccInk3)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 1)
                }
                Spacer()
                Text("\(done.count) of \(plan.totalDays) Days Read")
                    .font(.ccBody(11.5))
                    .italic()
                    .foregroundStyle(.ccInk3)
                Spacer()
                if viewedDay < plan.totalDays {
                    Button {
                        goNext()
                    } label: {
                        Text("Next \u{2192}").labelCaps(size: 11, tracking: 0.1, color: .ccInk)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 1)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 40)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.ccHairline).frame(height: 1)
        }
    }

    private func goNext() {
        guard viewedDay < plan.totalDays else { return }
        navDirection = .trailing
        withAnimation(.easeInOut(duration: 0.28)) {
            viewedDay += 1
        }
    }

    private func goPrev() {
        guard viewedDay > 1 else { return }
        navDirection = .leading
        withAnimation(.easeInOut(duration: 0.28)) {
            viewedDay -= 1
        }
    }

    private func jump(to day: Int) {
        let clamped = min(plan.totalDays, max(1, day))
        navDirection = clamped >= viewedDay ? .trailing : .leading
        withAnimation(.easeInOut(duration: 0.28)) {
            viewedDay = clamped
        }
    }

    private func toggleDone() {
        if done.contains(viewedDay) {
            store.markUnread(planSlug: plan.slug, day: viewedDay)
            completed.removeAll { $0 == viewedDay }
        } else {
            store.recordRead(planSlug: plan.slug, day: viewedDay)
            completed.append(viewedDay)
            // Marking the day you're looking at done reads as "finished,
            // what's next" — same auto-advance feel as SessionView's Next.
            if viewedDay < plan.totalDays {
                goNext()
            }
        }
    }
}
