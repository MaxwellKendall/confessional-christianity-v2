// Choose sermon photos, correct the proposed groups, and review each imported sermon.
import SwiftUI
import SwiftData
import PhotosUI
import DomainKit

struct BatchImportView: View {
    @State var model: BatchImportModel
    var onClose: () -> Void
    var onKeep: () -> Void = {}
    var onJournal: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    @State private var reviewing: ReviewModel?
    @State private var selectedSermon = 0
    @State private var kept: Set<UUID> = []
    @State private var discarded: Set<UUID> = []
    @State private var opensDate = false
    @State private var editingGroup: SermonGroup?
    @State private var groupEditorFocus: EditSermonDetailsSheet.Field?
    @State private var picked: [PhotosPickerItem] = []
    @State private var showsPicker = false
    @State private var showsCancel = false
    @State private var finishFailed = false
    #if DEBUG
    @State private var appliedFixture = false
    #endif

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ccPaper.ignoresSafeArea())
        .fullScreenCover(item: $reviewing) { review in
            ReviewView(model: review, onClose: { reviewing = nil }, onFinish: {
                if review.review.hasNothingToKeep {
                    discarded.insert(review.noteId)
                } else {
                    kept.insert(review.noteId)
                    onKeep()
                }
                let pending = model.noteIds.indices.filter { !kept.contains(model.noteIds[$0]) && !discarded.contains(model.noteIds[$0]) }
                if let next = pending.first(where: { $0 > selectedSermon }) ?? pending.first {
                    selectedSermon = next
                }
                reviewing = nil
            }, startsEditingDate: opensDate)
        }
        #if DEBUG
        .onAppear {
            guard !appliedFixture, model.step == .done else { return }
            appliedFixture = true
            switch UserDefaults.standard.string(forKey: "LordsDayBatchFixture") {
            case "date":
                if let id = model.noteIds.last { openReview(id, editingDate: true) }
            case "allKept":
                kept = Set(model.noteIds)
            default:
                break
            }
        }
        #endif
        .sheet(item: $editingGroup) { group in
            EditSermonDetailsSheet(initial: model.details(of: group), readFromNotes: model.sermon(of: group),
                                   dateIsGuess: model.date(of: group).isGuess, initialFocus: groupEditorFocus) { edit in
                try model.edit(group, details: edit)
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
        case .grouping: groupingList
        case .done:
            if kept.count == model.noteIds.count { allKept }
            else { queue }
        }
    }

    private var header: some View {
        let groups = model.grouping?.groups.count ?? 0
        let title = switch model.step {
        case .picking: "Several sermons at once"
        case .reading: "Reading your notes"
        case .grouping: "Here's how I split them"
        case .done: kept.count == model.noteIds.count ? "All sermons kept" : "\(kept.count) of \(model.noteIds.count) kept"
        }
        let eyebrow = switch model.step {
        case .grouping: "Import · \(model.pages.count) pages · \(groups) sermons"
        case .done: "Imported sermons"
        default: "Import"
        }
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(eyebrow.uppercased()).font(.ccLabelCaps).tracking(1.2).foregroundStyle(.ccInk2)
                Text(title).font(.ccTitle).foregroundStyle(.ccInk)
            }
            Spacer()
            Button {
                if model.pages.isEmpty || model.step == .done { onClose() }
                else { showsCancel = true }
            } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(Color.ccFill, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.ccUI(15, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(ChapelPrimaryButtonStyle())
    }

    // MARK: Choosing and reading

    private var picking: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.pages.isEmpty {
                    introArtwork
                    Text("Choose photos of notes from as many past sermons as you like.")
                        .font(.ccBody(17))
                    introNote("info.circle", "Up to \(BatchImportDraft.maxPhotos) photos per import. Have more? Import these first, then the rest.")
                        .accessibilityIdentifier("batch.cap")
                    introNote("text.alignleft", "Pages are sorted into sermons as they're read. You can check the split before reviewing cards.")
                    introNote("calendar", "Each sermon is dated from its notes or photos. If neither has a date, the date is marked as a guess.")
                } else {
                    Text("\(model.pages.count) of \(BatchImportDraft.maxPhotos) photos")
                        .font(.ccUI(13, weight: .semibold))
                        .foregroundStyle(.ccInk2)
                    ProgressView(value: Double(model.pages.count), total: Double(BatchImportDraft.maxPhotos)).tint(.ccChapel)
                    if !model.canAddPhotos && model.step == .picking {
                        Text("Add these, then import the rest.").font(.ccUI(13)).foregroundStyle(.ccInk2)
                    }
                }
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
                }
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) {
            if model.step == .picking {
                VStack(spacing: 8) {
                    if model.canAddPhotos {
                        primaryButton(model.pages.isEmpty ? "Choose Photos" : "Add Photos") { showsPicker = true }
                            .accessibilityIdentifier("batch.choose")
                    }
                    if !model.pages.isEmpty {
                        primaryButton(model.readCount > 0 ? "Read the rest" : "Read \(model.pages.count) photos") { model.read() }
                            .accessibilityIdentifier("batch.read")
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 8)
                .background(Color.ccPaper)
            }
        }
    }

    private var introArtwork: some View {
        ZStack {
            ForEach(0..<4) { index in
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.ccSurface)
                    .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Color.ccLine) }
                    .overlay {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 30, weight: .thin))
                            .foregroundStyle(.ccGilt)
                    }
                    .frame(width: 66, height: 86)
                    .rotationEffect(.degrees((Double(index) - 1.5) * 5))
                    .offset(x: (Double(index) - 1.5) * 39)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 110)
        .background(Color.ccFill, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityHidden(true)
    }

    private func introNote(_ icon: String, _ copy: String) -> some View {
        Label {
            Text(copy).font(.ccUI(13)).foregroundStyle(.ccInk2)
        } icon: {
            Image(systemName: icon).foregroundStyle(.ccGilt)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.ccSurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.ccLine) }
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
        let oversized = model.grouping?.oversizedGroups.count ?? 0
        return ScrollView {
            VStack(spacing: 10) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    if index > 0 {
                        Button {
                            model.merge(group.id, into: groups[index - 1].id)
                        } label: {
                            Label("Same sermon", systemImage: "arrow.triangle.merge")
                                .font(.ccUI(12, weight: .semibold))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Color.ccFill, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("batch.merge.\(index - 1)")
                    }
                    groupCard(group, index: index, groups: groups)
                }
                Text("Drop here for a new sermon")
                    .font(.ccUI(13, weight: .semibold))
                    .foregroundStyle(.ccChapel)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color.ccFill, in: RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.ccLine, style: StrokeStyle(dash: [5, 4])) }
                    .dropDestination(for: String.self) { items, _ in
                        guard let page = items.first.flatMap(UUID.init(uuidString:)), model.pages.contains(where: { $0.id == page }) else { return false }
                        model.moveToNewGroup(page)
                        return true
                    }
                Text("Hold and drag a page to move it. Tap the scissors between pages to start a new sermon there.")
                    .font(.ccUI(12)).foregroundStyle(.ccInk2).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20).padding(.bottom, 12)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Text("Each sermon is drafted on its own and lands in the journal by its date.")
                    .font(.ccUI(12)).foregroundStyle(.ccInk2).multilineTextAlignment(.center)
                primaryButton(oversized > 0 ? "Fix \(oversized) over the page limit" : "Draft \(groups.count) sermon\(groups.count == 1 ? "" : "s")") {
                    do { try model.finish() } catch { finishFailed = true }
                }
                .disabled(!(model.grouping?.canContinue ?? false) || model.retryingPage != nil)
                .accessibilityIdentifier("batch.finish")
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
            .background(Color.ccPaper)
        }
    }

    private func groupCard(_ group: SermonGroup, index: Int, groups: [SermonGroup]) -> some View {
        let details = model.details(of: group)
        let date = model.date(of: group)
        let over = group.pageIds.count > CaptureDraft.maxPages
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                Text("\(index + 1)").font(.ccUI(13, weight: .semibold))
                    .foregroundStyle(.ccChapel).frame(width: 29, height: 29)
                    .background(Color.ccFill, in: Circle())
                VStack(alignment: .leading, spacing: 5) {
                    Text(details.title ?? details.passage ?? "No title on the page")
                        .font(.ccDisplay(16, semibold: true))
                    HStack(spacing: 5) {
                        Text(date.date.formatted(.dateTime.month(.abbreviated).day()))
                        if date.isGuess {
                            Button { editDetails(group, focus: .date) } label: { dateMark(.guess) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("batch.group.guessedDate")
                        } else if date.source != .confirmed {
                            dateMark(date.source)
                        }
                        Text("· \(group.pageIds.count) pages")
                    }
                    .font(.ccUI(11)).foregroundStyle(.ccInk2)
                }
                Spacer(minLength: 0)
                Button("Edit") { editDetails(group) }
                    .font(.ccUI(12, weight: .semibold)).foregroundStyle(.ccChapel)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit details for sermon \(index + 1)")
            }
            .accessibilityIdentifier("batch.group.\(index)")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(group.pageIds.enumerated()), id: \.element) { offset, page in
                        if offset > 0 {
                            Button { model.split(group.id, at: page) } label: {
                                Image(systemName: "scissors").font(.system(size: 12))
                                    .frame(width: 30, height: 44)
                            }
                            .buttonStyle(.plain).foregroundStyle(.ccChapel)
                            .accessibilityLabel("Start a new sermon at page \(pageNumber(page))")
                        }
                        pageMenu(page, in: group, groups: groups)
                    }
                }
            }
            if let page = group.pageIds.first(where: { id in model.pages.contains { $0.id == id && $0.read?.failed == true } }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Page \(pageNumber(page)) couldn’t be read.")
                    Button(model.retryingPage == page ? "Reading again…" : "Try again") { model.retry(page) }
                        .disabled(model.retryingPage != nil)
                }
                .font(.ccUI(12, weight: .semibold)).foregroundStyle(.ccDanger)
            }
            if over {
                Text("\(group.pageIds.count) pages. A sermon takes \(CaptureDraft.maxPages) at most.")
                    .font(.ccUI(12, weight: .semibold)).foregroundStyle(.ccDanger)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(over ? Color.ccDangerFill : Color.ccSurface, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(over ? Color.ccDanger : Color.ccLine) }
        .dropDestination(for: String.self) { items, _ in
            guard let page = items.first.flatMap(UUID.init(uuidString:)), model.pages.contains(where: { $0.id == page }) else { return false }
            model.move(page, to: group.id)
            return true
        }
    }

    private func editDetails(_ group: SermonGroup, focus: EditSermonDetailsSheet.Field? = nil) {
        groupEditorFocus = focus
        editingGroup = group
    }

    private func pageNumber(_ page: UUID) -> Int {
        (model.pages.firstIndex { $0.id == page } ?? 0) + 1
    }

    private func pageMenu(_ page: UUID, in group: SermonGroup, groups: [SermonGroup]) -> some View {
        Menu {
            Menu("Move") {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, target in
                    if target.id != group.id {
                        Button("Sermon \(index + 1)") { model.move(page, to: target.id) }
                    }
                }
                Button("New sermon") { model.moveToNewGroup(page) }
            }
            if group.pageIds.first != page {
                Button("Start a new sermon here") { model.split(group.id, at: page) }
            }
            Button("Remove page", role: .destructive) { model.removePage(page) }
        } label: {
            thumbnail(page, label: "\(pageNumber(page))", read: true)
        }
        .disabled(model.retryingPage != nil)
        .draggable(page.uuidString)
        .accessibilityLabel("Page \(pageNumber(page))")
        .accessibilityIdentifier("batch.page.\(pageNumber(page))")
    }

    private func dateMark(_ source: ServiceDateResolution.Source) -> some View {
        let text = switch source {
        case .notes: "From notes"
        case .photo: "From photo date"
        case .guess: "Date guessed"
        case .confirmed: "Date confirmed"
        }
        return Text(text).font(.ccUI(10, weight: .semibold))
            .foregroundStyle(source == .guess ? .ccDanger : .ccChapel)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(source == .guess ? Color.ccDangerFill : Color.ccFill, in: Capsule())
    }

    private var queue: some View {
        let groups = model.grouping?.groups ?? []
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        Capsule().fill(kept.contains(group.id) ? Color.ccChapel : Color.ccGilt)
                            .frame(height: 4)
                            .overlay { Capsule().strokeBorder(index == selectedSermon ? Color.ccInk : .clear) }
                    }
                }
                .padding(.horizontal, 20)
                .accessibilityHidden(true)
                Text("Sermon \(selectedSermon + 1) of \(groups.count) · Swipe through or review in any order.")
                    .font(.ccUI(12)).foregroundStyle(.ccInk2).padding(.horizontal, 20)
                    .accessibilityIdentifier("batch.queue.progress")
                queuePager(groups)


                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    Button { withAnimation(.easeOut(duration: 0.2)) { selectedSermon = index } } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 3).fill(Color(hex: queuePalette(index).accent)).frame(width: 5, height: 30)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(queueTitle(group)).font(.ccDisplay(14, semibold: true)).foregroundStyle(.ccInk)
                                Text(queueDate(group).formatted(.dateTime.month(.abbreviated).day()))
                                    .font(.ccUI(12)).foregroundStyle(.ccInk2)
                            }
                            Spacer()
                            Text(queueStatus(group)).font(.ccUI(12, weight: .semibold))
                                .foregroundStyle(.ccChapel)
                        }
                        .padding(.vertical, 6)
                        .overlay(alignment: .bottom) { Rectangle().fill(Color.ccLine).frame(height: 1) }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func queuePager(_ groups: [SermonGroup]) -> some View {
        GeometryReader { proxy in
            let width = min(300, proxy.size.width - 40)
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        queueCard(group, index: index)
                            .frame(width: width)
                            .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, (proxy.size.width - width) / 2, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: Binding<Int?>(
                get: { selectedSermon },
                set: { if let index = $0 { selectedSermon = index } }
            ), anchor: .center)
        }
        .frame(height: 400)
    }

    private func queueTitle(_ group: SermonGroup) -> String {
        model.note(for: group.id)?.sermonTitle ?? "Sermon notes"
    }

    private func queueDate(_ group: SermonGroup) -> Date {
        model.note(for: group.id)?.serviceDate ?? model.date(of: group).date
    }

    private func queuePalette(_ index: Int) -> QuoteCardPalette {
        let rotation = LordsDayFeed.rotation
        return LordsDayFeed.palette(rotation[index % rotation.count], dark: colorScheme == .dark)
    }

    private func queueCard(_ group: SermonGroup, index: Int) -> some View {
        let palette = queuePalette(index)
        let isPending = !kept.contains(group.id) && !discarded.contains(group.id)
        let dateIsGuess = isPending && model.details(for: group.id)?.dateIsGuess == true
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(queueDate(group).formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                    .font(.ccLabelCaps).tracking(0.7).foregroundStyle(Color(hex: palette.accent))
                if dateIsGuess {
                    Button { openReview(group.id, editingDate: true) } label: { dateMark(.guess) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("batch.queue.guessedDate")
                }
            }
            Text(queueTitle(group)).font(.ccTitle).lineLimit(2)
            if let passage = model.note(for: group.id)?.passageRef {
                Text(passage).font(.ccBody(17)).lineLimit(1)
            }
            if let preacher = model.note(for: group.id)?.preacher {
                Text(preacher).font(.ccUI(13)).foregroundStyle(Color(hex: palette.muted))
            }
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                ForEach(group.pageIds.prefix(6), id: \.self) { page in
                    thumbnail(page, label: "\(pageNumber(page))", read: true, width: 40, height: 52)
                }
            }
            Divider().overlay(Color(hex: palette.frame)).padding(.top, 5)
            HStack {
                Text(queueStatus(group)).font(.ccUI(12, weight: .semibold))
                Spacer()
                if isPending {
                    Button("Review") { openReview(group.id) }.buttonStyle(.borderedProminent).tint(Color(hex: palette.accent)).foregroundStyle(Color(hex: palette.field))
                        .accessibilityIdentifier("batch.queue.review")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(Color(hex: palette.ink))
        .background(Color(hex: palette.field), in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Color(hex: palette.frame)) }
    }

    private func queueStatus(_ group: SermonGroup) -> String {
        if kept.contains(group.id) { return "✓ Kept" }
        if discarded.contains(group.id) { return "Discarded" }
        if model.details(for: group.id)?.hasNothingToKeep == true { return "Couldn’t draft" }
        return "Ready to review"
    }

    private var allKept: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "checkmark").font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.ccOnChapel)
                    .frame(width: 80, height: 80)
                    .background(Color.ccChapel, in: Circle())
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                Text("Your sermons are in the journal on the days they were preached.")
                    .font(.ccBody(17)).foregroundStyle(.ccInk2)
                ForEach(model.grouping?.groups ?? []) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(queueTitle(group)).font(.ccDisplay(15, semibold: true))
                        Text(queueDate(group).formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                            .font(.ccUI(13)).foregroundStyle(.ccInk2)
                    }
                }
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) {
            primaryButton("Open the journal", action: onJournal)
                .padding(.horizontal, 20).padding(.vertical, 8)
                .background(Color.ccPaper)
        }
    }

    private func openReview(_ id: UUID, editingDate: Bool = false) {
        opensDate = editingDate
        reviewing = model.review(for: id)
    }

    private func thumbnail(_ id: UUID, label: String, read: Bool, width: CGFloat = 57, height: CGFloat = 75) -> some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let image = model.thumbnails[id] {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color.ccFill
                }
            }
            .frame(width: width, height: height)
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
/// Screenshot hook: `-LordsDayBatchFixture picker|cap|reading|groups|oversized|failed|queue|review|date|allKept|keep`. Seven sample pages read by
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
                BatchImportView(model: model, onClose: {})
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
        let generator = BatchFixtureGenerator(failsPage: scene == "failed" ? 6 : nil,
                                             pageDelay: scene == "reading" ? .seconds(2) : .milliseconds(120))
        guard let model = try? BatchImportModel(context: context, storeProvider: storeProvider, generator: generator, root: root) else { return }
        if scene == "cap" {
            for index in 1...BatchImportDraft.maxPhotos { model.add(Self.samplePage(index)) }
        } else if scene != "picker" {
            for (index, takenAt) in BatchFixtureGenerator.takenAt(datingLastFromPhotos: keeps).enumerated() {
                model.add(Self.samplePage(index + 1), takenAt: takenAt)
            }
            model.read()
            if scene == "reading" {
                self.model = model
                return
            }
            while model.step == .reading { try? await Task.sleep(for: .milliseconds(50)) }
        }
        if scene == "oversized", let groups = model.grouping?.groups, let first = groups.first {
            for group in groups.dropFirst() { model.merge(group.id, into: first.id) }
        }
        if ["review", "date", "queue", "allKept"].contains(scene) || keeps {
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
            if scene == "review", let id = ids.last, let note = try? storeProvider().note(id: id) {
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
    private let failsPage: Int?
    private let pageDelay: Duration

    init(failsPage: Int? = nil, pageDelay: Duration = .milliseconds(120)) {
        self.failsPage = failsPage
        self.pageDelay = pageDelay
    }

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
                    try? await Task.sleep(for: self.pageDelay)
                    let page = start + i
                    if page == self.failsPage {
                        continuation.yield(.pageFailed(i))
                        continue
                    }
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
