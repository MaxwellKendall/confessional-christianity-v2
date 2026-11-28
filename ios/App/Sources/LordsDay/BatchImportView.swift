// The batch import screens (TKL-1107 skeleton: plain visuals; the approved
// design is TKL-1108). Choose up to 30 photos, read them, check which pages
// make each sermon (move a page, start a new sermon at a page, merge two), then
// make one note per sermon, each waiting in the existing review.
import SwiftUI
import SwiftData
import PhotosUI
import DomainKit

struct BatchImportView: View {
    @State var model: BatchImportModel
    var onClose: () -> Void
    /// The notes were made; the landing page lists their reviews.
    var onFinish: ([UUID]) -> Void

    @State private var picked: [PhotosPickerItem] = []
    @State private var showsPicker = false
    @State private var showsCancel = false
    @State private var finishFailed = false

    var body: some View {
        NavigationStack {
            content
                .background(Color.ccPaper.ignoresSafeArea())
                .navigationTitle("Import several sermons")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { if model.pages.isEmpty { onClose() } else { showsCancel = true } }
                    }
                }
        }
        .tint(.ccInk)
        .photosPicker(isPresented: $showsPicker, selection: $picked, maxSelectionCount: max(1, model.remainingPhotos),
                      selectionBehavior: .ordered, matching: .images, preferredItemEncoding: .current, photoLibrary: .shared())
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            Task { await model.add(items) }
        }
        .confirmationDialog("Leave this import?", isPresented: $showsCancel, titleVisibility: .visible) {
            Button("Keep for later") { onClose() }
            Button("Discard photos", role: .destructive) { model.discard(); onClose() }
        } message: {
            Text("The photos stay on this iPhone until you finish or discard them.")
        }
        .alert("Couldn't make the sermons", isPresented: $finishFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Nothing was lost. Try again.")
        }
    }

    @ViewBuilder private var content: some View {
        switch model.step {
        case .picking, .reading: picking
        case .grouping, .done: groupingList
        }
    }

    // MARK: Choosing and reading

    private var picking: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose up to \(BatchImportDraft.maxPhotos) photos of sermon notes, from as many Sundays as you like. Each sermon keeps up to \(CaptureDraft.maxPages) pages.")
                    .font(.ccUI(15))
                    .foregroundStyle(.ccInk2)
                    .accessibilityIdentifier("batch.cap")
                Text("\(model.pages.count) of \(BatchImportDraft.maxPhotos) photos")
                    .font(.ccUI(13, weight: .semibold))
                    .foregroundStyle(.ccInk3)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                    ForEach(Array(model.pages.enumerated()), id: \.element.id) { index, page in
                        thumbnail(page.id, label: "\(index + 1)", read: page.read != nil)
                            .contextMenu {
                                if model.step == .picking && model.grouping == nil {
                                    Button("Remove", role: .destructive) { model.removePage(page.id) }
                                }
                            }
                    }
                }
                if let failure = model.failure {
                    Text(failureText(failure))
                        .font(.ccUI(14))
                        .foregroundStyle(.ccDanger)
                }
                if model.step == .reading {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: Double(model.readCount), total: Double(max(model.pages.count, 1)))
                            .tint(.ccGilt)
                        Text("Reading your notes · \(model.readCount) of \(model.pages.count) pages")
                            .font(.ccUI(13))
                            .foregroundStyle(.ccInk2)
                    }
                    .accessibilityIdentifier("batch.reading")
                } else {
                    Button { showsPicker = true } label: {
                        Label(model.pages.isEmpty ? "Choose photos" : "Add photos", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.canAddPhotos)
                    .accessibilityIdentifier("batch.choose")
                    Button { model.read() } label: {
                        Text(model.readCount > 0 ? "Read the rest" : "Read \(model.pages.count) photo\(model.pages.count == 1 ? "" : "s")")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.ccChapel)
                    .disabled(model.pages.isEmpty)
                    .accessibilityIdentifier("batch.read")
                }
            }
            .padding(20)
        }
    }

    private func failureText(_ failure: CardsGeneratorError) -> String {
        switch failure {
        case .accountNeeded: "Sign in to read notes."
        case .offline: "You're offline. What was read is saved; read the rest when you're back online."
        case .rateLimited: "That's a lot of notes for one hour. What was read is saved; read the rest later."
        default: "Some photos couldn't be read. What was read is saved; try the rest again."
        }
    }

    // MARK: Grouping

    private var groupingList: some View {
        let groups = model.grouping?.groups ?? []
        return List {
            Section {
                Text("Check which pages make each sermon. Hold a page to move it or start a new sermon there.")
                    .font(.ccUI(14))
                    .foregroundStyle(.ccInk2)
            }
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(group.pageIds, id: \.self) { pageId in
                                pageMenu(pageId, in: group, index: index, groups: groups)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    if group.pageIds.count > CaptureDraft.maxPages {
                        Text("A sermon keeps up to \(CaptureDraft.maxPages) pages. Split this one at a page.")
                            .font(.ccUI(13))
                            .foregroundStyle(.ccDanger)
                    }
                    if index + 1 < groups.count {
                        Button("Merge with sermon \(index + 2)") { model.merge(groups[index + 1].id, into: group.id) }
                            .font(.ccUI(14))
                            .accessibilityIdentifier("batch.merge.\(index)")
                    }
                } header: {
                    groupHeader(group, index: index)
                }
            }
            Section {
                Button {
                    do {
                        try model.finish()
                        onFinish(model.noteIds)
                    } catch {
                        finishFailed = true
                    }
                } label: {
                    Text("Make \(groups.count) sermon\(groups.count == 1 ? "" : "s")")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.ccChapel)
                .disabled(!(model.grouping?.canContinue ?? false))
                .accessibilityIdentifier("batch.finish")
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func groupHeader(_ group: SermonGroup, index: Int) -> some View {
        let sermon = model.sermon(of: group)
        let date = model.date(of: group)
        let dateText = date.date.formatted(.dateTime.month(.abbreviated).day().year())
        let how = switch date.source {
        case .notes: "from the notes"
        case .photo: "from the photos"
        case .guess: "guessed"
        }
        return VStack(alignment: .leading, spacing: 2) {
            Text("Sermon \(index + 1) · \(group.pageIds.count) page\(group.pageIds.count == 1 ? "" : "s")")
                .font(.ccUI(12, weight: .semibold))
            Text(sermon?.title ?? sermon?.passage ?? "No title read")
                .font(.ccDisplay(15, semibold: true))
                .foregroundStyle(.ccInk)
                .textCase(nil)
            Text("\(dateText) · \(how)")
                .font(.ccUI(12))
                .foregroundStyle(date.isGuess ? .ccOchre : .ccInk3)
                .textCase(nil)
        }
        .accessibilityIdentifier("batch.group.\(index)")
    }

    private func pageMenu(_ pageId: UUID, in group: SermonGroup, index: Int, groups: [SermonGroup]) -> some View {
        let number = (model.pages.firstIndex { $0.id == pageId } ?? 0) + 1
        return Menu {
            ForEach(Array(groups.enumerated()), id: \.element.id) { other, target in
                if target.id != group.id {
                    Button("Move to sermon \(other + 1)") { model.move(pageId, to: target.id) }
                }
            }
            if group.pageIds.first != pageId {
                Button("Start a new sermon here") { model.split(group.id, at: pageId) }
            }
        } label: {
            thumbnail(pageId, label: "\(number)", read: true)
        }
        .accessibilityIdentifier("batch.page.\(number)")
    }

    private func thumbnail(_ id: UUID, label: String, read: Bool) -> some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let image = model.thumbnails[id] {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color.ccFill
                }
            }
            .frame(width: 72, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(label)
                .font(.ccUI(11, weight: .semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(4)
        }
        .opacity(read || model.step != .reading ? 1 : 0.55)
    }
}

#if DEBUG
/// Screenshot hook: `-LordsDayBatchFixture picker|groups|review|keep`. Seven sample pages read by
/// `BatchFixtureGenerator` into three sermons: a date read from the notes (Nov 15), a date from the
/// photos (Nov 8) and, for `groups`/`review`, a guessed date (`keep` dates it from its photos, Nov 1).
/// `picker`, `groups` and `review` use a throwaway folder and an in-memory store; `review` opens the
/// guessed sermon's review. `keep` writes to the app's store, keeps all three reviews and shows the app
/// (pair with `-StartTab lordsDay -OpenJournal YES` for the journal).
struct LordsDayBatchFixture: View {
    let scene: String
    @Environment(\.modelContext) private var appContext
    @Environment(SyncService.self) private var sync
    @State private var model: BatchImportModel?
    @State private var review: ReviewModel?
    @State private var kept = false

    var body: some View {
        ZStack {
            if kept {
                RootView()
            } else if let review {
                ReviewView(model: review, onClose: {}, onFinish: {})
            } else if let model {
                BatchImportView(model: model, onClose: {}, onFinish: { _ in })
            }
        }
        .task { await load() }
    }

    private func load() async {
        let keeps = scene == "keep"
        let context: ModelContext
        let root: URL
        let storeProvider: @MainActor () -> LordsDayStore
        if keeps {
            context = appContext
            root = CaptureDraft.defaultRoot
            storeProvider = { [sync, appContext] in sync.lordsDayStore(in: appContext) }
        } else {
            let container = try! ModelContainer(for: progressSchema, configurations: [ModelConfiguration(schema: progressSchema, isStoredInMemoryOnly: true)])
            context = ModelContext(container)
            root = FileManager.default.temporaryDirectory.appendingPathComponent("batch-fixture-\(UUID().uuidString)")
            storeProvider = { LordsDayStore(context: context) }
        }
        let generator = BatchFixtureGenerator()
        guard let model = try? BatchImportModel(context: context, storeProvider: storeProvider, generator: generator, root: root) else { return }
        if scene != "picker" {
            for (index, takenAt) in BatchFixtureGenerator.takenAt(datingLastFromPhotos: keeps).enumerated() {
                model.add(Self.samplePage(index + 1), takenAt: takenAt)
            }
            model.read()
            while model.step == .reading { try? await Task.sleep(for: .milliseconds(50)) }
        }
        if scene == "review" || keeps {
            try? model.finish()
            let ids = model.noteIds
            if keeps {
                for id in ids {
                    guard let note = try? storeProvider().note(id: id) else { continue }
                    let session = ReviewModel.session(for: note, context: context, storeProvider: storeProvider, generator: generator, root: root)
                    try? session.finish()
                }
                kept = true
                return
            }
            if let id = ids.last, let note = try? storeProvider().note(id: id) {
                review = ReviewModel.session(for: note, context: context, storeProvider: storeProvider, generator: generator, root: root)
                return
            }
        }
        self.model = model
    }

    /// A ruled page with a page number, standing in for a photo of notes.
    static func samplePage(_ number: Int) -> Data {
        let size = CGSize(width: 600, height: 800)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(white: 0.96, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.6, green: 0.7, blue: 0.85, alpha: 1).setStroke()
            for y in stride(from: 120.0, to: size.height, by: 40) {
                ctx.cgContext.move(to: CGPoint(x: 30, y: y))
                ctx.cgContext.addLine(to: CGPoint(x: size.width - 30, y: y))
            }
            ctx.cgContext.strokePath()
            ("Page \(number)" as NSString).draw(at: CGPoint(x: 40, y: 50), withAttributes: [
                .font: UIFont.systemFont(ofSize: 44, weight: .semibold), .foregroundColor: UIColor.darkGray,
            ])
        }
        return image.jpegData(compressionQuality: 0.8)!
    }
}

/// Replays sample reads for the batch, chunk by chunk, in the order the batch asks for them.
final class BatchFixtureGenerator: CardsGenerator, @unchecked Sendable {
    private let lock = NSLock()
    private var nextPage = 0

    /// What each of the seven pages names.
    static let sermons: [SermonDetails?] = [
        SermonDetails(title: "Triumph of the Lamb", preacher: nil, passage: "Revelation 1:1-3", church: nil, serviceDate: "2026-11-15"),
        nil,
        SermonDetails(title: "Gospel Partnership", preacher: nil, passage: "Philippians 4:14-20", church: nil, serviceDate: nil),
        nil,
        nil,
        SermonDetails(title: "A Tale of Two Prayers", preacher: nil, passage: "Luke 18:9-14", church: nil, serviceDate: nil),
        nil,
    ]

    static func takenAt(datingLastFromPhotos: Bool) -> [Date?] {
        let calendar = Calendar.current
        let lamb = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 13))!
        let partnership = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 13))!
        let prayers = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 13))!
        let last: [Date?] = datingLastFromPhotos ? [prayers, prayers.addingTimeInterval(60)] : [nil, nil]
        return [lamb, lamb.addingTimeInterval(60), partnership, partnership.addingTimeInterval(60), partnership.addingTimeInterval(120)] + last
    }

    func draft(_ request: LordsDayCardsRequest) -> AsyncThrowingStream<LordsDayCardsEvent, Error> {
        let start: Int = lock.withLock {
            defer { nextPage += request.pages.count }
            return nextPage
        }
        let count = request.pages.count
        return AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.started(pages: count))
                for i in 0..<count {
                    try? await Task.sleep(for: .milliseconds(120))
                    let page = start + i
                    let sermon = Self.sermons.indices.contains(page) ? Self.sermons[page] : nil
                    let cards = [
                        DraftCardPayload(kind: "key_point", page: i, order: 0, text: "A point from page \(page + 1) of \(sermon?.title ?? "these notes").", sourceKey: "fixture-\(page):0"),
                        DraftCardPayload(kind: "verse", page: i, order: 1, reference: "Romans 8:28", osis: "Rom.8.28", sourceKey: "fixture-\(page):1"),
                    ]
                    continuation.yield(.page(i, cardCount: cards.count, extractedText: "Page \(page + 1)", generationId: "fixture-\(page)"))
                    if let sermon { continuation.yield(.sermon(i, sermon)) }
                    for card in cards { continuation.yield(.card(card)) }
                }
                continuation.yield(.done(failedPages: []))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func redraft(_ request: LordsDayRedraftRequest) async throws -> DraftCardPayload { throw CardsGeneratorError.noCard }
}
#endif
