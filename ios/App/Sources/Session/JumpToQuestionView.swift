// Mirrors src/app/(column)/programs/[slug]/session/jump/JumpToQuestionClient.tsx:
// a back arrow + label-caps title, a pill search field, a "Questions 1–N" /
// "N Matches" caption, and a plain row list (number + italic question,
// ochre when it's the current question).
import SwiftUI
import DomainKit

struct JumpToQuestionView: View {
    let program: ProgramDefinition
    let currentQuestion: Int
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var allQuestions: [(number: Int, question: String)] { listQuestions(program) }

    private var filtered: [(number: Int, question: String)] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return allQuestions }
        return allQuestions.filter {
            String($0.number) == q || $0.question.lowercased().contains(q)
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
                Text("Jump to Question").labelCaps(size: 10, tracking: 0.14)
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
                TextField("Search by number or phrase\u{2026}", text: $search)
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
                     : "Questions 1\u{2013}\(allQuestions.count)")
                    .labelCaps(size: 9.5, tracking: 0.1)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)

            if filtered.isEmpty {
                Text("No questions match \u{201C}\(search)\u{201D}.")
                    .font(.ccBody(13))
                    .italic()
                    .foregroundStyle(.ccInk2)
                    .padding(.top, 24)
                Spacer()
            } else {
                List(filtered, id: \.number) { item in
                    let active = item.number == currentQuestion
                    Button {
                        onSelect(item.number)
                        dismiss()
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Text("\(item.number)")
                                .font(.ccDisplay(14))
                                .foregroundStyle(active ? .ccOchre : .ccInk3)
                                .frame(width: 20, alignment: .leading)
                            Text(item.question)
                                .font(.ccBody(15))
                                .italic()
                                .foregroundStyle(.ccInk)
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
