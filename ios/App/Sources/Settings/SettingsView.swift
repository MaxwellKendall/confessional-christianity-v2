// Settings, opened from Today's avatar (TKL-825): the children (pick who is
// being catechized, add another) and About & Credits. Sign-in and the
// practice reminder join it in their own tickets (TKL-826).
import SwiftUI
import SwiftData
import DomainKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var observedChildren: [LocalChild]
    @Query private var observedTracks: [ChildCatechismTrack]
    @Query private var observedSettings: [ProgressSettings]
    @State private var showsAddChild = false

    private var store: LocalProgressStore { LocalProgressStore(context: modelContext) }

    var body: some View {
        let _ = observedChildren.map(\.updatedAt)
        let _ = observedTracks.map(\.updatedAt)
        let activeId = observedSettings.first?.activeChildId
        NavigationStack {
            List {
                Section("Children") {
                    ForEach(store.todayChildren()) { child in
                        Button {
                            try? store.selectChild(childId: child.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(child.name).foregroundStyle(.ccInk)
                                    Text("\(child.programShortTitle) · \(child.learned) of \(child.totalQuestions) learned")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.ccInk2)
                                }
                                Spacer()
                                if child.id == activeId {
                                    Image(systemName: "checkmark").foregroundStyle(.ccChapel)
                                }
                            }
                        }
                    }
                    Button("Add a child") { showsAddChild = true }
                        .foregroundStyle(.ccChapel)
                }
                Section {
                    NavigationLink("About & Credits") {
                        AboutView(path: .constant(NavigationPath()))
                            .toolbar(.visible, for: .navigationBar)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(.ccInk)
        .sheet(isPresented: $showsAddChild) { AddChildView() }
    }
}

struct AddChildView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var focused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textContentType(.givenName)
                        .submitLabel(.done)
                        .focused($focused)
                        .onSubmit(add)
                } footer: {
                    Text("Each child keeps their own place, starting at Q. 1 of the Shorter Catechism.")
                }
            }
            .navigationTitle("Add a child")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: add).disabled(trimmed.isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .tint(.ccInk)
        .presentationDetents([.medium])
    }

    private func add() {
        guard !trimmed.isEmpty else { return }
        let store = LocalProgressStore(context: modelContext)
        guard let child = try? store.addChild(name: trimmed) else { return }
        // The newest child becomes the one Today and the Catechism tab show.
        try? store.selectChild(childId: child.id)
        dismiss()
    }
}
