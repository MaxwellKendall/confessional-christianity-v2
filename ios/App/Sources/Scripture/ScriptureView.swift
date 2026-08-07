// The canonical page for a single proof text — mirrors
// src/app/(column)/scripture/[osis]/page.tsx: the citation heading, the ESV
// passage text (fetched live, same proxy Library's proof-texts panel uses),
// then every confession clause across the library that cites it, grouped by
// document. Reached only from a citation a user has already tapped, so
// (unlike web) there's no not-found state to handle — the tapped osis is
// always in the index.
import SwiftUI
import DomainKit

struct ScriptureView: View {
    let osis: String
    @Binding var path: NavigationPath

    @State private var passageText: String?
    @State private var passageLoaded = false

    private var citation: String { parseOsisBibleReference(osis) }
    private var citing: [ScriptureCitingEntry] { getScriptureCitingEntries(osis) }

    // Groups citing entries by document, preserving first-appearance order —
    // mirrors the web page's reduce-into-groups.
    private var byDocument: [(documentTitle: String, entries: [ScriptureCitingEntry])] {
        var order: [String] = []
        var grouped: [String: [ScriptureCitingEntry]] = [:]
        for entry in citing {
            if grouped[entry.documentTitle] == nil { order.append(entry.documentTitle) }
            grouped[entry.documentTitle, default: []].append(entry)
        }
        return order.map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                backBar

                VStack(spacing: 12) {
                    Text(citation).headingPage().multilineTextAlignment(.center)
                    if passageLoaded, let passageText {
                        VStack(spacing: 4) {
                            Text(passageText)
                                .font(.ccBody(15.5))
                                .italic()
                                .foregroundStyle(.ccInk)
                                .multilineTextAlignment(.center)
                            Text("ESV").labelCaps(size: 8.5, tracking: 0.1)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 10)

                VStack(alignment: .leading, spacing: 16) {
                    Text("Cited in the Confessions").labelCaps(size: 9.5, tracking: 0.1)
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(byDocument, id: \.documentTitle) { group in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(group.documentTitle).labelCaps(size: 9, tracking: 0.1)
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(Array(group.entries.enumerated()), id: \.offset) { _, entry in
                                        citingRow(entry)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 100)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.ccHairline).frame(height: 1)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .background(Color.ccCard)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: osis) {
            passageLoaded = false
            passageText = await EsvClient.shared.text(for: osis)
            passageLoaded = true
        }
    }

    private var backBar: some View {
        HStack {
            Button {
                if !path.isEmpty { path.removeLast() }
            } label: {
                Text("\u{2039} Back").labelCaps(size: 9.5, tracking: 0.1, color: .ccInk3).dottedUnderline(.ccInk3)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    // Clause can open far from its marker in long prose entries; keep the
    // tail, which is what the citation actually anchors to.
    private func trimClause(_ clause: String) -> String {
        clause.count > 220 ? "\u{2026}\(clause.suffix(220))" : clause
    }

    @ViewBuilder
    private func citingRow(_ entry: ScriptureCitingEntry) -> some View {
        Button {
            path.append(LibraryRoute.entry(slug: entry.documentSlug, entryId: entry.entryId))
        } label: {
            (
                Text(entry.entryLabel)
                    .font(.ccDisplay(13, semibold: true))
                    .foregroundStyle(.ccInk)
                + (entry.clause.isEmpty ? Text("") : Text(" \u{2014} \u{201C}\(trimClause(entry.clause))\u{201D}")
                    .font(.ccBody(13))
                    .italic()
                    .foregroundStyle(.ccInk2))
            )
            .multilineTextAlignment(.leading)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
