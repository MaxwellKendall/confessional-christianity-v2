// The Library index, pushed from the Catechism tab since TKL-825 removed the
// Library tab. Mirrors src/app/(column)/library/page.tsx — every
// document listed with its editorial blurb, plus a quiet nudge toward the
// Shorter Catechism for first-time visitors.
import SwiftUI
import DomainKit

struct LibraryIndexView: View {
    @Binding var path: NavigationPath

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
                SiteHeaderView(path: $path)
                ScrollView {
                    VStack(spacing: 0) {
                        HStack {
                            Button {
                                dismiss()
                            } label: {
                                Text("Back")
                                    .labelCaps(size: 9.5, tracking: 0.1, color: .ccInk3)
                                    .dottedUnderline(.ccInk3)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }
                        .padding(.top, 16)
                        Text("Library").headingPage().padding(.top, 16).padding(.bottom, 4)

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

                        Button {
                            path.append(LibraryRoute.about)
                        } label: {
                            Text("About & Credits")
                                .labelCaps(size: 9.5, tracking: 0.1, color: .ccInk3)
                                .dottedUnderline(.ccInk3)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }
            }
            .background(Color.ccCard)
            .toolbar(.hidden, for: .navigationBar)
    }
}
