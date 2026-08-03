// The Devotions tab's root: since the full devotions hub (mirroring
// src/app/(column)/devotions/page.tsx) hasn't been ported, this lists the
// authored series directly (advent, wsc) rather than block the tab bar's
// Devotions destination on unbuilt content — an honest, minimal root
// consistent with milestones.ts's "not yet mapped" pattern elsewhere.
import SwiftUI
import DomainKit

struct DevotionsTabView: View {
    @Binding var path: NavigationPath

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                SiteHeaderView(path: $path)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Devotion Series")
                            .labelCaps(size: 9.5, tracking: 0.14)
                            .padding(.top, 24)
                            .padding(.bottom, 2)

                        ForEach(getAllSeries(), id: \.slug) { series in
                            Button {
                                path.append(DevotionRoute.series(series.slug))
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(series.title).headingSection()
                                    Text(series.tagline)
                                        .font(.ccBody(13))
                                        .italic()
                                        .foregroundStyle(.ccInk2)
                                }
                                .padding(20)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.ccFill)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }
            }
            .background(Color.ccCanvas)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: DevotionRoute.self) { route in
                switch route {
                case .series(let slug):
                    if let series = getSeries(slug) {
                        DevotionSeriesView(series: series, path: $path)
                    }
                case .devotion(let slug):
                    if let devotion = getDevotion(slug) {
                        DevotionLandingView(devotion: devotion, path: $path)
                    }
                case .worship(let slug, let startStep):
                    if let devotion = getDevotion(slug) {
                        DevotionWorshipView(devotion: devotion, startStep: startStep, path: $path)
                    }
                case .catechismHandoff(let programSlug, let devotionSlug, let returnStep):
                    if let program = getProgram(programSlug) {
                        SessionView(
                            program: program, path: $path,
                            handoff: DevotionHandoff(devotionSlug: devotionSlug, returnStep: returnStep)
                        )
                    }
                }
            }
            .navigationDestination(for: ScriptureRoute.self) { route in
                switch route {
                case .detail(let osis):
                    ScriptureView(osis: osis, path: $path)
                }
            }
            .navigationDestination(for: LibraryRoute.self) { route in
                switch route {
                case .document(let slug):
                    DocumentTocView(slug: slug, path: $path)
                case .entry(let slug, let entryId):
                    LibraryEntryView(slug: slug, entryId: entryId, path: $path)
                case .session(let programSlug, let questionNumber):
                    if let program = getProgram(programSlug) {
                        SessionView(program: program, path: $path, startQuestion: questionNumber)
                    }
                }
            }
            .navigationDestination(for: SearchRoute.self) { _ in
                SearchView(path: $path)
            }
        }
        .tint(.ccInk)
    }
}
