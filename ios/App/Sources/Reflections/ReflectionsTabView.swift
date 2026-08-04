// The Reflections tab's root: mirrors src/app/(column)/reflections/page.tsx
// — every essay grouped by series (each sorted by part), then a standalone
// section for essays with no series, newest first within each list.
import SwiftUI
import DomainKit

struct ReflectionsTabView: View {
    @Binding var path: NavigationPath

    private var posts: [Reflection] { loadReflections() }
    private var seriesNames: [String] {
        var seen = Set<String>()
        return posts.compactMap(\.series).filter { seen.insert($0).inserted }
    }
    private var standalone: [Reflection] { posts.filter { $0.series == nil } }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                SiteHeaderView(path: $path)
                ScrollView {
                    VStack(spacing: 0) {
                        Text("Reflections").headingPage().padding(.top, 24).padding(.bottom, 4)

                        if posts.isEmpty {
                            Text("Essays are on their way.")
                                .font(.ccBody(13))
                                .italic()
                                .foregroundStyle(.ccInk2)
                                .multilineTextAlignment(.center)
                                .padding(.top, 40)
                        }

                        ForEach(seriesNames, id: \.self) { series in
                            seriesSection(series)
                        }

                        if !standalone.isEmpty {
                            VStack(spacing: 0) {
                                if !seriesNames.isEmpty {
                                    Text("Standalone Essays")
                                        .labelCaps(size: 9.5, tracking: 0.1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.bottom, 6)
                                }
                                ForEach(standalone, id: \.slug) { post in
                                    row(post)
                                }
                            }
                            .padding(.top, 20)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }
            }
            .background(Color.ccCard)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ReflectionsRoute.self) { route in
                switch route {
                case .detail(let slug):
                    ReflectionDetailView(slug: slug, path: $path)
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
            .navigationDestination(for: ScriptureRoute.self) { route in
                switch route {
                case .detail(let osis):
                    ScriptureView(osis: osis, path: $path)
                }
            }
            .navigationDestination(for: SearchRoute.self) { _ in
                SearchView(path: $path)
            }
        }
        .tint(.ccInk)
    }

    @ViewBuilder
    private func seriesSection(_ series: String) -> some View {
        VStack(spacing: 0) {
            Text("Series \u{00B7} \(series)")
                .labelCaps(size: 9.5, tracking: 0.1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 6)
            ForEach(posts.filter { $0.series == series }.sorted { ($0.part ?? 0) < ($1.part ?? 0) }, id: \.slug) { post in
                row(post)
            }
        }
        .padding(.top, 20)
    }

    @ViewBuilder
    private func row(_ post: Reflection) -> some View {
        Button {
            path.append(ReflectionsRoute.detail(slug: post.slug))
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(post.part.map { "Part \($0): \(post.title)" } ?? post.title)
                    .font(.ccDisplay(13.5, semibold: true))
                    .foregroundStyle(.ccInk)
                Text(
                    [post.author, formatDate(post.date, style: .short)]
                        .compactMap { $0 }
                        .filter { !$0.isEmpty }
                        .joined(separator: " \u{00B7} ")
                )
                .labelCaps(size: 9, tracking: 0.1)
                if let subtitle = post.subtitle {
                    Text(subtitle)
                        .font(.ccBody(12))
                        .foregroundStyle(.ccInk2)
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.ccHairline).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
