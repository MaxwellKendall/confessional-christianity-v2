// The Library tab's root: mirrors src/app/(column)/library/page.tsx — every
// document listed with its editorial blurb, plus a quiet nudge toward the
// Shorter Catechism for first-time visitors.
import SwiftUI
import DomainKit

struct LibraryTabView: View {
    @Binding var path: NavigationPath

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                SiteHeaderView(path: $path)
                ScrollView {
                    VStack(spacing: 0) {
                        Text("Library").headingPage().padding(.top, 24).padding(.bottom, 4)

                        VStack(spacing: 0) {
                            ForEach(LIBRARY_DOCUMENTS, id: \.slug) { doc in
                                Button {
                                    path.append(LibraryRoute.document(slug: doc.slug))
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(doc.name)
                                            .font(.ccDisplay(14, semibold: true))
                                            .foregroundStyle(.ccInk)
                                        Text(doc.blurb)
                                            .font(.ccBody(12.5))
                                            .italic()
                                            .foregroundStyle(.ccInk2)
                                    }
                                    .padding(.vertical, 13)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .overlay(alignment: .top) {
                                        Rectangle().fill(Color.ccHairline).frame(height: 1)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 16)

                        Button {
                            path.append(LibraryRoute.document(slug: "westminster-shorter-catechism"))
                        } label: {
                            HStack(spacing: 4) {
                                Text("New here? Start with the")
                                    .font(.ccBody(13))
                                    .italic()
                                    .foregroundStyle(.ccInk2)
                                Text("Shorter Catechism")
                                    .font(.ccBody(13))
                                    .italic()
                                    .foregroundStyle(.ccInk)
                                    .dottedUnderline(.ccInk)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 16)
                        .overlay(alignment: .top) {
                            Rectangle().fill(Color.ccHairline).frame(height: 1)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }
            }
            .background(Color.ccCard)
            .toolbar(.hidden, for: .navigationBar)
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
                }
            }
            .navigationDestination(for: SearchRoute.self) { _ in
                SearchView(path: $path)
            }
        }
        .tint(.ccInk)
    }
}
