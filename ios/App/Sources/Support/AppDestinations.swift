// Every push target, registered once and applied to each tab's
// NavigationStack (TKL-825). With three tabs, the Library, search, scripture
// and reflections are lookups that any tab can push, so each stack needs the
// same destinations.
import SwiftUI
import DomainKit

private struct AppDestinations: ViewModifier {
    @Binding var path: NavigationPath

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: String.self) { slug in
                if let program = getProgram(slug) {
                    SessionView(program: program, path: $path)
                }
            }
            .navigationDestination(for: LibraryRoute.self) { route in
                switch route {
                case .index:
                    LibraryIndexView(path: $path)
                case .document(let slug):
                    DocumentTocView(slug: slug, path: $path)
                case .entry(let slug, let entryId):
                    LibraryEntryView(slug: slug, entryId: entryId, path: $path)
                case .session(let programSlug, let questionNumber):
                    if let program = getProgram(programSlug) {
                        SessionView(program: program, path: $path, startQuestion: questionNumber)
                    }
                case .about:
                    AboutView(path: $path)
                }
            }
            .navigationDestination(for: ReflectionsRoute.self) { route in
                switch route {
                case .detail(let slug):
                    ReflectionDetailView(slug: slug, path: $path)
                }
            }
            .navigationDestination(for: ScriptureRoute.self) { route in
                switch route {
                case .detail(let osis):
                    ScriptureView(osis: osis, path: $path)
                case .reader(let source):
                    VerseReaderView(source: source)
                }
            }
            .navigationDestination(for: SearchRoute.self) { _ in
                SearchView(path: $path)
            }
    }
}

extension View {
    func appDestinations(path: Binding<NavigationPath>) -> some View {
        modifier(AppDestinations(path: path))
    }
}
