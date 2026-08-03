// A single confession/catechism entry's reading page — mirrors
// src/app/(column)/library/[confession]/[entry]/page.tsx, but for the
// proof-texts panel follows QuestionCardView's catechism-session pattern
// rather than web's per-citation click-to-expand list: one clause is
// "active" at a time (tap any footnote-marked clause to switch), its group's
// verses are fetched live through EsvClient and shown automatically. The
// scripture-cross-reference page (web's /scripture/[osis]) is a separate,
// not-yet-built phase, so citations don't link out yet.
//
// Paging also responds to a horizontal swipe (left = next, right = prev,
// the standard iOS carousel convention), not just the Prev/Next links —
// `.simultaneousGesture` so it doesn't fight the ScrollView's own vertical
// drag; only acts when the gesture is clearly horizontal and past a
// deliberate-swipe threshold.
import SwiftUI
import DomainKit

struct LibraryEntryView: View {
    let slug: String
    let entryId: String
    @Binding var path: NavigationPath

    @State private var activeMarker: String?
    @State private var verseTexts: [String: String?] = [:]

    private var page: EntryPage? { getEntryPage(slug, entryId: entryId) }
    private var groups: [ProofTextGroup] { page.map { proofTextGroups($0.item) } ?? [] }
    private var activeGroup: ProofTextGroup? { groups.first { $0.marker == activeMarker } }

    private var activeSegmentLabel: String? {
        guard let page else { return nil }
        let allSegments = entryQuoteSegments(page.item).flatMap { $0 }
        guard let segment = allSegments.first(where: { $0.marker == activeMarker }) else { return nil }
        return truncateClause(segment.text)
    }

    var body: some View {
        ScrollView {
            if let page {
                VStack(spacing: 0) {
                    breadcrumb(page)

                    VStack(spacing: 10) {
                        Text(entryPageLabel(page.item))
                            .labelCaps(size: 9.5, tracking: 0.1)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(entryQuoteSegments(page.item).enumerated()), id: \.offset) { _, line in
                                FlowText(prefix: "", segments: line, activeMarker: activeMarker) { marker in
                                    withAnimation(.easeOut(duration: 0.15)) { activeMarker = marker }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 22)

                    if !groups.isEmpty {
                        scriptureSection
                    }

                    HStack {
                        pagingLink(page.prevEntry, symbol: "\u{2190}", isNext: false)
                        Spacer()
                        pagingLink(page.nextEntry, symbol: "\u{2192}", isNext: true)
                    }
                    .padding(.top, 28)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color.ccHairline).frame(height: 1)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 100)
            }
        }
        .background(Color.ccCanvas)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { activeMarker = groups.first?.marker }
        .task(id: "\(entryId)|\(activeMarker ?? "")") {
            await loadVerseTexts()
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    guard abs(horizontal) > abs(vertical), abs(horizontal) > 60, let page else { return }
                    if horizontal < 0, let next = page.nextEntry {
                        navigate(to: next.entryId)
                    } else if horizontal > 0, let prev = page.prevEntry {
                        navigate(to: prev.entryId)
                    }
                }
        )
    }

    private func navigate(to entryId: String) {
        path.removeLast()
        path.append(LibraryRoute.entry(slug: slug, entryId: entryId))
    }

    @ViewBuilder
    private var scriptureSection: some View {
        VStack(spacing: 12) {
            Text("Proof Texts").labelCaps(size: 9.5, tracking: 0.1)

            if groups.count > 1, let label = activeSegmentLabel {
                HStack(spacing: 6) {
                    Circle().fill(Color.ccOchre).frame(width: 6, height: 6)
                    Text("Now Showing \u{2014} \u{201C}\(label)\u{201D}")
                        .labelCaps(size: 9, tracking: 0.1, color: .ccOchre)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.ccOchre.opacity(0.1)))
            }

            VStack(spacing: 14) {
                ForEach(activeGroup?.refs ?? [], id: \.osis) { ref in
                    VStack(spacing: 4) {
                        Text(resolvedVerseText(ref))
                            .font(.ccBody(15))
                            .italic()
                            .foregroundStyle(.ccInk)
                            .multilineTextAlignment(.center)
                        Text(ref.citation)
                            .labelCaps(size: 9, tracking: 0.1, color: .ccInk3)
                    }
                }
            }
            .frame(minHeight: 70)

            if groups.count > 1 {
                Text("Tap the other phrase above to see its verse")
                    .font(.ccBody(11))
                    .italic()
                    .foregroundStyle(.ccMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.ccHairline).frame(height: 1)
        }
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

    @ViewBuilder
    private func breadcrumb(_ page: EntryPage) -> some View {
        HStack(spacing: 4) {
            Button {
                path.removeLast(path.count)
            } label: {
                Text("Library").labelCaps(size: 9.5, tracking: 0.1, color: .ccInk3).dottedUnderline(.ccInk3)
            }
            .buttonStyle(.plain)
            Text("/").labelCaps(size: 9.5, tracking: 0.1, color: .ccInk3)
            Button {
                path.removeLast()
            } label: {
                Text(page.documentTitle).labelCaps(size: 9.5, tracking: 0.1, color: .ccInk3)
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    @ViewBuilder
    private func pagingLink(_ adjacent: AdjacentEntry?, symbol: String, isNext: Bool) -> some View {
        if let adjacent {
            Button {
                navigate(to: adjacent.entryId)
            } label: {
                Text(isNext ? "\(adjacent.title) \(symbol)" : "\(symbol) \(adjacent.title)")
                    .labelCaps(size: 10, tracking: 0.1, color: .ccInk)
                    .dottedUnderline(.ccInk)
            }
            .buttonStyle(.plain)
        } else {
            Text(isNext ? "Next \(symbol)" : "\(symbol) Prev")
                .labelCaps(size: 10, tracking: 0.1, color: .ccMuted)
        }
    }
}
