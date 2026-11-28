// Reviewing the drafted cards before the week is kept (TKL-863, redesigned to
// match the approved TKL-1062 prototype in TKL-1085 pass 1). Sermon details
// edit in a focused sheet (never inline fields competing with the keyboard and
// card pager); cards fill in one at a time in a horizontal pager with each
// card's action row (Remove / Undo, Redraft with shimmer, in-place Edit with
// Save / Cancel) inside the card above "Keep these N cards".
import SwiftUI
import SwiftData
import DomainKit

struct ReviewView: View {
    @Bindable var model: ReviewModel
    var onClose: () -> Void
    var onFinish: () -> Void
    #if DEBUG
    /// Screenshot hook: the card the pager opens at.
    var startAt: String?
    /// Screenshot hook: open the details sheet focused on this field on appear.
    var fixtureOpenDetails: EditSermonDetailsSheet.Field?
    /// Screenshot hook: open this card in in-place edit mode on appear.
    var fixtureEditCard: String?
    #endif

    @Environment(\.colorScheme) private var colorScheme
    @Environment(AuthService.self) private var auth
    @State private var current: String?
    @State private var detailsSheet: DetailsSheetRequest?
    @State private var editingCardId: String?
    @State private var editKind: CardKind = .keyPoint
    @State private var editWords = ""
    @State private var editAttribution = ""
    @State private var editInitialAttribution = ""
    @State private var editVerseRef = ""
    @State private var pickingVerseForId: String?
    @State private var showsSignIn = false
    @State private var finishFailed = false
    @State private var confirmsDiscard = false

    private struct DetailsSheetRequest: Identifiable {
        let id = UUID()
        let focus: EditSermonDetailsSheet.Field?
    }

    private var review: LordsDayReview { model.review }
    private var dark: Bool { colorScheme == .dark }
    private static let placeholderId = "drafting"

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if editingCardId == nil {
                sermonDetailsCard
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if review.isDrafting {
                draftingBar
            }
            pager
            dots
            notices
            footer
        }
        .animation(.easeOut(duration: 0.2), value: editingCardId != nil)
        .foregroundStyle(.ccInk)
        .background(Color.ccPaper.ignoresSafeArea())
        .onAppear {
            if auth.phase.isSignedIn && model.failure == .accountNeeded {
                model.retry()
            } else {
                model.startIfNeeded()
            }
            #if DEBUG
            if let startAt {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { current = startAt }
            }
            if let fixtureOpenDetails {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    detailsSheet = DetailsSheetRequest(focus: fixtureOpenDetails)
                }
            }
            if let fixtureEditCard {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    if let card = model.review.card(fixtureEditCard) {
                        current = card.id
                        beginEdit(card)
                    }
                }
            }
            #endif
        }
        .onChange(of: auth.phase.isSignedIn) { _, signedIn in
            if signedIn && model.failure == .accountNeeded {
                showsSignIn = false
                model.retry()
            }
        }
        .task {
            for await online in NetworkConnectivity.shared.onlineUpdates() {
                if online, model.review.retryWhenOnline, model.review.canRetry {
                    model.retry()
                }
            }
        }
        .sheet(isPresented: $showsSignIn, onDismiss: { auth.cancelCode() }) {
            SignInSheet()
        }
        .sheet(item: $detailsSheet) { request in
            EditSermonDetailsSheet(
                initial: model.detailsEdit,
                readFromNotes: model.review.sermon,
                initialFocus: request.focus
            ) { edit in
                try model.updateDetails(edit)
            }
        }
        .sheet(isPresented: Binding(
            get: { pickingVerseForId != nil },
            set: { if !$0 { pickingVerseForId = nil } }
        )) {
            let startOsis = editVerseRef.isEmpty
                ? model.passage.flatMap(citationToOsis)
                : (ReaderChapter.chapterOSIS(for: editVerseRef) != nil ? editVerseRef : citationToOsis(editVerseRef))
            VersePickerView(startOsis: startOsis) { osis in
                editVerseRef = parseOsisBibleReference(osis)
                editKind = .verse
            }
        }
    }

    // MARK: Top bar & sermon details

    private var topBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("REVIEW").chapelCaps()
                Text("This week's sermon")
                    .font(.ccDisplay(21, semibold: true))
                    .foregroundStyle(.ccInk)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.ccInk)
                    .frame(width: 36, height: 36)
                    .background(Color.ccFill, in: Circle())
            }
            .accessibilityLabel("Close")
            .accessibilityIdentifier("review.close")
        }
        .padding(.horizontal, ChapelSpace.gutter)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var sermonDetailsCard: some View {
        let dateString = model.serviceDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let heading = SermonHeading(title: model.title, passage: model.passage, preacher: model.preacher, date: dateString)
        let flags = model.review.sermon?.readFlags(
            title: model.title ?? "",
            preacher: model.preacher ?? "",
            passage: model.passage ?? "",
            church: model.church ?? "",
            serviceDate: model.serviceDate
        ) ?? .none
        let anyReadFromNotes = flags.title || flags.preacher || flags.passage || flags.church || flags.serviceDate
        let metaParts = [model.passage, model.preacher, model.church].compactMap { $0 }
        // A batch-imported sermon whose date nothing said (TKL-1107) says so until its details are saved.
        let shownDate = model.dateIsGuess ? "\(dateString) (date guessed)" : dateString

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Button { openDetails(.title) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(heading.headline)
                                .font(.ccDisplay(17, semibold: true))
                                .foregroundStyle(model.title == nil ? .ccInk2 : .ccInk)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .accessibilityIdentifier("review.sermon.title")
                        }
                        if anyReadFromNotes {
                            Text("read from your notes")
                                .font(.ccUI(11))
                                .foregroundStyle(.ccGilt)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button { openDetails(nil) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Edit details")
                            .font(.ccUI(13, weight: .semibold))
                    }
                    .foregroundStyle(.ccChapel)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(Color.ccFill, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("review.sermon.editDetails")
            }

            Button { openDetails(model.passage == nil ? .passage : .preacher) } label: {
                HStack(spacing: 6) {
                    if metaParts.isEmpty {
                        Text("Add passage, preacher or church · \(shownDate)")
                            .font(.ccUI(13))
                            .foregroundStyle(.ccInk3)
                    } else {
                        Text((metaParts + [shownDate]).joined(separator: " · "))
                            .font(.ccUI(13))
                            .foregroundStyle(.ccInk2)
                            .accessibilityIdentifier("review.sermon.meta")
                    }
                    Spacer(minLength: 0)
                }
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.ccSurface, in: RoundedRectangle(cornerRadius: ChapelRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ChapelRadius.card, style: .continuous)
                .strokeBorder(Color.ccLine, lineWidth: 1)
        )
        .padding(.horizontal, ChapelSpace.gutter)
        .padding(.bottom, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review.sermon.card")
    }

    private func openDetails(_ focus: EditSermonDetailsSheet.Field?) {
        editingCardId = nil
        detailsSheet = DetailsSheetRequest(focus: focus)
    }

    private var draftingBar: some View {
        let count = review.cards.count
        let read = review.transcribedPageCount
        let where_ = review.pageCount > 1 && read > 0
            ? "Page \(min(read + 1, review.pageCount)) of \(review.pageCount)"
            : "Reading your notes"
        let so = count == 0 ? "" : " · \(count) card\(count == 1 ? "" : "s") so far"
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(where_)\(so). You can close this; they keep coming.")
                .font(.ccUI(13))
                .foregroundStyle(.ccInk2)
            ProgressLine(value: review.progress)
                .accessibilityLabel("Reading your notes")
                .accessibilityValue("\(Int(review.progress * 100)) percent")
        }
        .padding(.horizontal, ChapelSpace.gutter)
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    // MARK: Pager

    private var pagerIds: [String] {
        review.cards.map(\.id) + (review.isDrafting ? [Self.placeholderId] : [])
    }

    private var pager: some View {
        let total = review.cards.count
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(Array(review.cards.enumerated()), id: \.element.id) { index, card in
                    let isEditing = editingCardId == card.id
                    ReviewCardView(
                        card: card,
                        position: index + 1,
                        total: total,
                        palette: palette(for: card, index: index),
                        preacher: model.preacher,
                        isRedrafting: model.isRedrafting(card.id),
                        canRedraft: model.canRedraft(card.id),
                        isEditing: isEditing,
                        editKind: $editKind,
                        editWords: $editWords,
                        editAttribution: $editAttribution,
                        editVerseRef: $editVerseRef,
                        onRemove: { model.remove(card.id) },
                        onUndo: { model.keep(card.id) },
                        onRedraft: {
                            if editingCardId == card.id { editingCardId = nil }
                            model.redraft(card.id)
                        },
                        onEdit: { beginEdit(card) },
                        onCancelEdit: { editingCardId = nil },
                        onSaveEdit: { saveEdit(for: card) },
                        onPickVerse: { pickingVerseForId = card.id }
                    )
                    .containerRelativeFrame(.horizontal)
                    .id(card.id)
                    .accessibilityIdentifier("review.card.\(card.id)")
                }
                if review.isDrafting {
                    DraftingCard(
                        cardsSoFar: review.cards.count,
                        transcription: review.newestTranscription
                    )
                    .containerRelativeFrame(.horizontal)
                    .id(Self.placeholderId)
                }
            }
            .scrollTargetLayout()
            .animation(.easeOut(duration: 0.3), value: review.cards.map(\.id))
        }
        .contentMargins(.horizontal, ChapelSpace.gutter, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $current)
        .frame(maxHeight: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .overlay {
            if review.cards.isEmpty && !review.isDrafting { emptyState }
        }
    }

    private func beginEdit(_ card: ReviewCard) {
        editKind = card.kind
        editWords = card.words
        let initialAttr = card.attribution ?? model.preacher ?? ""
        editAttribution = initialAttr
        editInitialAttribution = initialAttr
        if let ref = card.verseRef {
            editVerseRef = ReaderChapter.chapterOSIS(for: ref) != nil ? parseOsisBibleReference(ref) : ref
        } else {
            editVerseRef = ""
        }
        editingCardId = card.id
    }

    private func saveEdit(for card: ReviewCard) {
        if editKind == .verse {
            guard case .valid(_, let osis) = validateSermonPassage(editVerseRef) else { return }
            try? model.chooseVerse(card.id, osis: osis)
        } else {
            let trimmed = editWords.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if card.kind != editKind {
                try? model.setKind(card.id, to: editKind)
            }
            let attr: String? = (editKind == .quote && editAttribution != editInitialAttribution) ? editAttribution : nil
            try? model.edit(card.id, words: trimmed, attribution: attr)
        }
        editingCardId = nil
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text(review.phase == .notStarted ? "Your notes are saved." : "No cards came back from these notes.")
                .font(.ccBody(19))
            Text(review.phase == .notStarted ? "Cards are drafted from them when you try again." : "Try again, or retake the photos with the whole page in frame.")
                .font(.ccUI(14))
                .foregroundStyle(.ccInk2)
        }
        .multilineTextAlignment(.center)
        .padding(32)
    }

    private func palette(for card: ReviewCard, index: Int) -> QuoteCardPalette {
        LordsDayFeed.palette(LordsDayFeed.rotation[index % LordsDayFeed.rotation.count], dark: dark)
    }

    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(pagerIds, id: \.self) { id in
                let on = id == (current ?? pagerIds.first)
                RoundedRectangle(cornerRadius: 3)
                    .fill(on ? Color.ccInk : Color.ccInk.opacity(0.2))
                    .frame(width: on ? 16 : 6, height: 6)
            }
        }
        .padding(.bottom, 8)
        .animation(.easeOut(duration: 0.2), value: current)
        .accessibilityHidden(true)
    }

    // MARK: Notices and footer

    @ViewBuilder private var notices: some View {
        let canSkipUnread = !review.isDrafting && !review.unhandledUnreadPages.isEmpty && !review.cards.isEmpty
        VStack(spacing: 8) {
            if let redraftFailure = model.redraftFailure {
                note(
                    redraftFailure == .noCard
                        ? "Nothing new came back for that card. The one you have is unchanged."
                        : "That card couldn't be drafted again. The one you have is unchanged.",
                    actionTitle: "OK",
                    actionId: "review.redraftFailure.dismiss"
                ) {
                    model.dismissRedraftFailure()
                }
            }
            if model.failure == .accountNeeded {
                if auth.isConfigured {
                    note("Sign in to draft cards from your notes. Your notes are saved.", actionTitle: "Sign in", actionId: "review.signIn") {
                        showsSignIn = true
                    }
                } else {
                    note("Drafting cards needs an account. Your notes are saved.", actionTitle: nil) {}
                }
            } else if let message = failureMessage {
                note(
                    message,
                    actionTitle: (review.canRetry || review.phase == .notStarted) ? "Try again" : nil,
                    actionId: "review.retry",
                    secondaryTitle: canSkipUnread ? "Skip unread" : nil,
                    secondaryId: "review.skipUnread",
                    secondaryAction: { model.skipUnreadPages() }
                ) {
                    model.retry()
                }
            } else if !review.isDrafting, !review.unhandledUnreadPages.isEmpty, !review.replayUnavailablePages.isEmpty {
                let pages = review.replayUnavailablePages.sorted().map { "\($0 + 1)" }.joined(separator: ", ")
                if review.canRetry {
                    note(
                        "Page \(pages)'s original draft is no longer available to resume. Try the remaining pages, or keep the cards already here.",
                        actionTitle: "Try again",
                        actionId: "review.retry",
                        secondaryTitle: canSkipUnread ? "Keep what's here" : nil,
                        secondaryId: "review.skipUnread",
                        secondaryAction: { model.skipUnreadPages() }
                    ) {
                        model.retry()
                    }
                } else {
                    note(
                        "Page \(pages)'s original draft is no longer available to resume. Your cards so far are saved.",
                        actionTitle: canSkipUnread ? "Keep what's here" : nil,
                        actionId: "review.skipUnread"
                    ) {
                        model.skipUnreadPages()
                    }
                }
            } else if !review.isDrafting, !review.unhandledUnreadPages.isEmpty, !review.failedPages.isEmpty {
                let pages = review.failedPages.sorted().map { "\($0 + 1)" }.joined(separator: ", ")
                note(
                    "Page \(pages) couldn't be read. Try again, or skip it to keep the cards already here.",
                    actionTitle: "Try again",
                    actionId: "review.retry",
                    secondaryTitle: canSkipUnread ? "Skip unread" : nil,
                    secondaryId: "review.skipUnread",
                    secondaryAction: { model.skipUnreadPages() }
                ) {
                    model.retry()
                }
            } else if !review.isDrafting, !review.unhandledUnreadPages.isEmpty, review.phase != .notStarted {
                note(
                    "Some of your notes haven't been read yet.",
                    actionTitle: "Try again",
                    actionId: "review.retry",
                    secondaryTitle: canSkipUnread ? "Skip unread" : nil,
                    secondaryId: "review.skipUnread",
                    secondaryAction: { model.skipUnreadPages() }
                ) {
                    model.retry()
                }
            }
            if model.saveFailed || finishFailed {
                note("Couldn't save on this iPhone. Your changes are still on screen; try again.", actionTitle: nil) {}
            }
        }
        .padding(.horizontal, ChapelSpace.gutter)
        .padding(.bottom, 6)
    }

    private var failureMessage: String? {
        switch model.failure {
        case .accountNeeded: nil
        case .offline: "You're offline. Your notes are saved; try again when you're back online."
        case .rateLimited: "Too many notes at once. Try again in a few minutes."
        case .failed: "Something went wrong reading your notes. They're saved; try again."
        case .noCard: "Nothing new came back for that card. The one you have is unchanged."
        case nil: nil
        }
    }

    private func note(
        _ text: String,
        actionTitle: String?,
        actionId: String? = nil,
        secondaryTitle: String? = nil,
        secondaryId: String? = nil,
        secondaryAction: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(text).font(.ccUI(13.5)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                if let actionTitle {
                    Button(actionTitle, action: action)
                        .font(.ccUI(13.5, weight: .semibold))
                        .accessibilityIdentifier(actionId ?? actionTitle)
                }
                if let secondaryTitle, let secondaryAction {
                    Button(secondaryTitle, action: secondaryAction)
                        .font(.ccUI(13, weight: .medium))
                        .accessibilityIdentifier(secondaryId ?? secondaryTitle)
                }
            }
        }
        .foregroundStyle(.ccDanger)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.ccDangerFill, in: RoundedRectangle(cornerRadius: ChapelRadius.card, style: .continuous))
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let index = review.blockingCardIndex {
                Button {
                    current = review.cards[index].id
                } label: {
                    Text("Card \(index + 1) has no words. Edit it or remove it.")
                        .font(.ccUI(13))
                        .foregroundStyle(.ccDanger)
                }
                .buttonStyle(.plain)
            } else if !review.isDrafting, !review.unhandledUnreadPages.isEmpty {
                let n = review.unhandledUnreadPages.count
                Text(
                    review.canRetry
                        ? "Retry or skip \(n) unread page\(n == 1 ? "" : "s") to finish."
                        : "Keep what's here to finish without \(n) unfinished page\(n == 1 ? "" : "s")."
                )
                .font(.ccUI(13))
                .foregroundStyle(.ccInk2)
                .accessibilityIdentifier("review.unreadHint")
            }

            if review.hasNothingToKeep && editingCardId == nil {
                // Nothing to keep can't be finished; without a way out it waits for review forever (TKL-1103).
                Button("Discard these notes") { confirmsDiscard = true }
                    .buttonStyle(ChapelQuietButtonStyle())
                    .accessibilityIdentifier("review.discard")
                    .confirmationDialog("Discard these notes?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
                        Button("Discard notes", role: .destructive) {
                            do {
                                try model.discard()
                                onFinish()
                            } catch {
                                finishFailed = true
                            }
                        }
                    } message: {
                        Text(review.cards.isEmpty
                             ? "Nothing was drafted from them. The photos will be deleted from this iPhone."
                             : "No cards are kept. The photos will be deleted from this iPhone.")
                    }
            } else {
                Button {
                    do {
                        try model.finish()
                        onFinish()
                    } catch {
                        finishFailed = true
                    }
                } label: {
                    Text(finishLabel)
                }
                .buttonStyle(ChapelPrimaryButtonStyle())
                .disabled(!review.canFinish || editingCardId != nil)
                .opacity(review.canFinish && editingCardId == nil ? 1 : 0.4)
                .accessibilityIdentifier("review.finish")
            }

            if review.blockingCardIndex == nil && review.unhandledUnreadPages.isEmpty && editingCardId == nil && !review.hasNothingToKeep {
                Text("Edit a card's words, or Redraft it for another from the same notes.")
                    .font(.ccUI(12.5))
                    .foregroundStyle(.ccInk3)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, ChapelSpace.gutter)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(Color.ccSurface)
        .overlay(alignment: .top) { Rectangle().fill(Color.ccLine).frame(height: 1) }
    }

    private var finishLabel: String {
        if review.isDrafting { return "Reading your notes…" }
        let count = review.keptCount
        if count == 1 { return "Keep this card" }
        return "Keep these \(count) cards"
    }
}

// MARK: Cards

private struct ReviewCardView: View {
    let card: ReviewCard
    let position: Int
    let total: Int
    let palette: QuoteCardPalette
    let preacher: String?
    let isRedrafting: Bool
    let canRedraft: Bool
    let isEditing: Bool
    @Binding var editKind: CardKind
    @Binding var editWords: String
    @Binding var editAttribution: String
    @Binding var editVerseRef: String
    let onRemove: () -> Void
    let onUndo: () -> Void
    let onRedraft: () -> Void
    let onEdit: () -> Void
    let onCancelEdit: () -> Void
    let onSaveEdit: () -> Void
    let onPickVerse: () -> Void

    @State private var verseText: String?
    @FocusState private var editFocused: Bool

    private var field: Color { Color(hex: palette.field) }
    private var ink: Color { Color(hex: palette.ink) }
    private var accent: Color { Color(hex: palette.accent) }
    private var muted: Color { Color(hex: palette.muted) }
    private var frame: Color { Color(hex: palette.frame) }

    private var canSaveEdit: Bool {
        if editKind == .verse {
            if case .valid = validateSermonPassage(editVerseRef) { return true }
            return false
        }
        return !editWords.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var verseEditError: String? {
        guard editKind == .verse else { return nil }
        let trimmed = editVerseRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if case .invalid(let msg) = validateSermonPassage(trimmed) { return msg }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topMeta
            cardBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            Rectangle().fill(frame).frame(height: 1)
            actionRow
        }
        .foregroundStyle(ink)
        .background(field)
        .clipShape(RoundedRectangle(cornerRadius: ChapelRadius.card, style: .continuous))
        .opacity(card.isRemoved ? 0.45 : 1)
        .animation(.easeOut(duration: 0.2), value: card.decision)
        .task(id: card.verseRef) {
            verseText = nil
            guard card.kind == .verse, let ref = card.verseRef, let osis = osis(ref) else { return }
            if let bundled = bundledEsvText(for: osis), !bundled.isEmpty { verseText = bundled; return }
            verseText = await EsvClient.shared.text(for: osis)
        }
        .onChange(of: isEditing) { _, active in
            if active {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { editFocused = true }
            } else {
                editFocused = false
            }
        }
    }

    private var topMeta: some View {
        HStack(spacing: 6) {
            Text("\(position) of \(total)")
                .foregroundStyle(muted)
            if card.isRemoved {
                Text("· removed").foregroundStyle(muted)
            } else {
                if card.redrafted {
                    Text("· redrafted").foregroundStyle(accent)
                        .accessibilityIdentifier("review.badge.redrafted")
                }
                if card.editedByUser {
                    Text("· edited").foregroundStyle(accent)
                        .accessibilityIdentifier("review.badge.edited")
                }
            }
            Spacer(minLength: 0)
        }
        .font(.ccUI(12, weight: .medium))
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    @ViewBuilder private var cardBody: some View {
        if isRedrafting {
            RedraftShimmerBody(kindLabel: card.kind.label, ink: ink, accent: accent, muted: muted)
        } else if isEditing {
            inPlaceEditor
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                kindLabel(card.kind).padding(.bottom, 14)
                ViewThatFits(in: .vertical) {
                    displayContent
                    ScrollView(.vertical, showsIndicators: false) {
                        displayContent.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                Text(source)
                    .font(.ccUI(12.5))
                    .foregroundStyle(muted)
                    .lineLimit(2)
                    .padding(.top, 12)
                Spacer(minLength: 0)
            }
        }
    }

    private var inPlaceEditor: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    ForEach(CardKind.allCases, id: \.self) { kind in
                        Button {
                            editKind = kind
                        } label: {
                            Text(kind.label)
                                .font(.ccUI(12, weight: editKind == kind ? .semibold : .regular))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(editKind == kind ? ink : ink.opacity(0.10), in: Capsule())
                                .foregroundStyle(editKind == kind ? field : ink)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if editKind == .verse {
                    Text("Reference")
                        .font(.ccUI(11.5, weight: .medium))
                        .foregroundStyle(muted)
                    TextField("e.g. Revelation 2:10", text: $editVerseRef)
                        .font(.ccUI(16))
                        .foregroundStyle(ink)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($editFocused)
                        .padding(10)
                        .background(ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(frame, lineWidth: 1))
                        .accessibilityIdentifier("review.edit.verseRef")
                    if let verseEditError {
                        Text(verseEditError)
                            .font(.ccUI(12))
                            .foregroundStyle(.ccDanger)
                    }
                    Button(action: onPickVerse) {
                        Label("Pick in Bible", systemImage: "book")
                            .font(.ccUI(13, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                } else {
                    Text("Text")
                        .font(.ccUI(11.5, weight: .medium))
                        .foregroundStyle(muted)
                    TextField("Card words", text: $editWords, axis: .vertical)
                        .font(.ccBody(17))
                        .lineSpacing(3)
                        .lineLimit(3...6)
                        .foregroundStyle(ink)
                        .focused($editFocused)
                        .padding(10)
                        .background(ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(frame, lineWidth: 1))
                        .accessibilityIdentifier("review.edit.words")

                    if editKind == .quote {
                        Text("Who said it")
                            .font(.ccUI(11.5, weight: .medium))
                            .foregroundStyle(muted)
                        TextField("Preacher or author", text: $editAttribution)
                            .font(.ccUI(15))
                            .foregroundStyle(ink)
                            .textInputAutocapitalization(.words)
                            .padding(10)
                            .background(ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(frame, lineWidth: 1))
                            .accessibilityIdentifier("review.edit.attribution")
                    }
                }
            }
        }
    }

    private func kindLabel(_ kind: CardKind) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(accent).frame(width: 18, height: 1)
            Text(kind.label)
                .font(.ccDisplay(10.5))
                .tracking(10.5 * 0.22)
                .textCase(.uppercase)
                .foregroundStyle(accent)
            Rectangle().fill(accent).frame(width: 18, height: 1)
        }
    }

    @ViewBuilder private var displayContent: some View {
        switch card.kind {
        case .keyPoint, .quote:
            Text(card.text.isEmpty ? "No words yet. Tap Edit." : card.text)
                .font(.ccBody(20))
                .lineSpacing(4)
                .opacity(card.text.isEmpty ? 0.6 : 1)
        case .verse:
            let reference = card.verseRef.map { ref in osis(ref).map(parseOsisBibleReference) ?? ref } ?? ""
            if let verseText = verseText?.trimmingCharacters(in: .whitespacesAndNewlines), !verseText.isEmpty {
                Text(verseText)
                    .font(.ccBody(19))
                    .lineSpacing(4)
                Text(reference)
                    .font(.ccDisplay(11.5))
                    .tracking(11.5 * 0.16)
                    .textCase(.uppercase)
                    .foregroundStyle(accent)
                    .padding(.top, 12)
            } else {
                Text(reference).font(.ccBody(24))
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 6) {
            if card.isRemoved {
                Button(action: onUndo) {
                    compactPill("Undo", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("review.keep")
                Spacer(minLength: 0)
            } else if isEditing {
                Button(action: onCancelEdit) {
                    compactPill("Cancel", systemImage: nil)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("review.edit.cancel")
                Spacer(minLength: 0)
                Button(action: onSaveEdit) {
                    compactPill("Save", systemImage: nil, solid: true)
                }
                .buttonStyle(.plain)
                .disabled(!canSaveEdit)
                .opacity(canSaveEdit ? 1 : 0.4)
                .accessibilityIdentifier("review.edit.save")
            } else if isRedrafting {
                Spacer(minLength: 0)
            } else {
                Button(action: onRemove) {
                    compactPill("Remove", systemImage: nil)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("review.remove")
                Spacer(minLength: 4)
                if canRedraft {
                    Button(action: onRedraft) {
                        compactPill("Redraft", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("review.redraft")
                    .accessibilityHint("Asks for another card in this one's place")
                }
                Button(action: onEdit) {
                    compactPill("Edit", systemImage: "pencil", solid: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("review.edit")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 54)
    }

    private func compactPill(_ title: String, systemImage: String?, solid: Bool = false) -> some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 12, weight: .semibold))
            }
            Text(title)
                .font(.ccUI(13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(solid ? field : ink)
        .padding(.horizontal, 11)
        .frame(height: 32)
        .background(solid ? ink : ink.opacity(0.10), in: Capsule())
        .contentShape(Capsule())
    }

    private var source: String {
        switch card.kind {
        case .keyPoint: return "Summed up from your notes"
        case .quote:
            guard let attribution = card.attribution else { return preacher ?? "No attribution" }
            return attribution.isEmpty ? "No attribution" : attribution
        case .verse: return card.editedByUser ? "Picked in the Bible" : "Read from your photo"
        }
    }

    private func osis(_ ref: String) -> String? {
        ReaderChapter.chapterOSIS(for: ref) != nil ? ref : citationToOsis(ref)
    }
}

/// Shimmer placeholder inside a card while it redrafts; sibling cards stay interactive.
private struct RedraftShimmerBody: View {
    let kindLabel: String
    let ink: Color
    let accent: Color
    let muted: Color
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer(minLength: 0)
            Text(kindLabel)
                .font(.ccDisplay(10.5))
                .tracking(10.5 * 0.22)
                .textCase(.uppercase)
                .foregroundStyle(accent)
            ForEach([0.90, 0.75, 0.55], id: \.self) { fraction in
                GeometryReader { geo in
                    Capsule()
                        .fill(ink.opacity(pulse ? 0.18 : 0.08))
                        .frame(width: geo.size.width * fraction)
                }
                .frame(height: 15)
            }
            Text("Redrafting from your notes…")
                .font(.ccUI(13))
                .foregroundStyle(muted)
                .padding(.top, 6)
            Spacer(minLength: 0)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

/// Where the next cards will land while the generator is still reading.
private struct DraftingCard: View {
    let cardsSoFar: Int
    let transcription: String?
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: ChapelRadius.card, style: .continuous)
            .fill(Color.ccFill)
            .overlay {
                VStack(alignment: .leading, spacing: 12) {
                    if let transcription, !transcription.isEmpty {
                        Text("Read from your notes")
                            .chapelCaps(color: .ccChapel)
                        ScrollView(.vertical, showsIndicators: false) {
                            Text(transcription)
                                .font(.ccBody(17))
                                .lineSpacing(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                    } else {
                        ForEach([0.4, 0.95, 0.85, 0.6], id: \.self) { width in
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.ccInk2.opacity(pulse ? 0.16 : 0.08))
                                .containerRelativeFrame(.horizontal) { length, _ in length * width * 0.75 }
                                .frame(height: width == 0.4 ? 10 : 18)
                        }
                    }
                    Text(cardsSoFar == 0 ? "Reading your notes…" : "More cards on the way…")
                        .font(.ccUI(13))
                        .foregroundStyle(.ccInk2)
                        .padding(.top, 8)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("More cards on the way")
    }
}

private struct ProgressLine: View {
    let value: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.ccFill)
                Capsule().fill(Color.ccGilt).frame(width: max(8, geometry.size.width * value))
            }
        }
        .frame(height: 3)
        .animation(.easeOut(duration: 0.5), value: value)
    }
}

#if DEBUG
/// Screenshot hook: `-LordsDayReviewFixture filling|complete|smyrna|empty` (`empty`: one page that drafts no cards, TKL-1103), optionally
/// `-LordsDayReviewCard p0-1` (or `drafting`), `-LordsDayReviewOpenDetails title|preacher|passage|church`,
/// `-LordsDayReviewApplyDetails "Title|Preacher|Passage|Church"`, `-LordsDayReviewEditCard p0-0`,
/// `-LordsDayReviewRedrafting p0-0`.
struct LordsDayReviewFixture: View {
    let scene: String
    @Environment(\.modelContext) private var appContext
    @Environment(SyncService.self) private var sync
    @State private var model: ReviewModel?
    @State private var finished = false

    private var persistsToAppStore: Bool {
        UserDefaults.standard.bool(forKey: "LordsDayReviewPersist")
    }

    private var autoKeep: Bool {
        UserDefaults.standard.bool(forKey: "LordsDayReviewAutoKeep")
    }

    var body: some View {
        let d = UserDefaults.standard
        let openDetails = d.string(forKey: "LordsDayReviewOpenDetails")
            .flatMap(EditSermonDetailsSheet.Field.init(rawValue:))
        ZStack {
            if finished {
                RootView()
            } else if let model {
                ReviewView(
                    model: model,
                    onClose: {},
                    onFinish: {
                        if persistsToAppStore { finished = true }
                    },
                    startAt: d.string(forKey: "LordsDayReviewCard"),
                    fixtureOpenDetails: openDetails,
                    fixtureEditCard: d.string(forKey: "LordsDayReviewEditCard")
                )
                .onChange(of: model.review.canFinish) { _, ready in
                    if ready, let apply = d.string(forKey: "LordsDayReviewApplyDetails") {
                        let parts = apply.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                        if parts.count >= 4 {
                            try? model.updateDetails(SermonDetailsEdit(
                                title: parts[0],
                                preacher: parts[1],
                                passage: parts[2],
                                church: parts[3],
                                serviceDate: model.serviceDate
                            ))
                        }
                    }
                    if ready, let redraftId = d.string(forKey: "LordsDayReviewRedrafting") {
                        model.setFixtureRedrafting(redraftId)
                    }
                    guard ready, autoKeep else { return }
                    try? model.finish()
                    if persistsToAppStore { finished = true }
                }
            }
        }
        .task(id: persistsToAppStore ? sync.activeSubject : "in-memory") {
            guard model == nil else { return }
            let context: ModelContext
            let storeProvider: @MainActor () -> LordsDayStore
            if persistsToAppStore {
                guard sync.activeSubject != nil else { return }
                context = appContext
                storeProvider = { [sync, appContext] in sync.lordsDayStore(in: appContext) }
            } else {
                let container = try! ModelContainer(for: progressSchema, configurations: [ModelConfiguration(schema: progressSchema, isStoredInMemoryOnly: true)])
                let memContext = ModelContext(container)
                context = memContext
                storeProvider = { LordsDayStore(context: memContext) }
            }
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("review-fixture-\(UUID().uuidString)")
            let customTitle = UserDefaults.standard.string(forKey: "LordsDayReviewTitle")
            let note = scene == "smyrna"
                ? LordsDayNote(serviceDate: CaptureModel.lastSunday(onOrBefore: Date()))
                : LordsDayNote(
                    serviceDate: CaptureModel.lastSunday(onOrBefore: Date()),
                    passageRef: "Romans 8:28–30",
                    sermonTitle: customTitle,
                    preacher: "Rev. [your pastor]"
                )
            try! storeProvider().save(note)
            let draft = try! CaptureDraft(noteId: note.id, root: root)
            for _ in 0..<(scene == "smyrna" || scene == "empty" ? 1 : 3) { try! draft.addPage(CaptureModel.jpegForUpload(CaptureFixture.samplePage())!) }
            let generator = scene == "smyrna"
                ? FixtureCardsGenerator.smyrna
                : scene == "empty"
                ? FixtureCardsGenerator(delay: .milliseconds(150), pages: [[]], pageText: ["(blank page)"])
                : FixtureCardsGenerator(stopsAfter: scene == "filling" ? 2 : nil, delay: .milliseconds(scene == "filling" ? 300 : 150))
            model = ReviewModel.session(for: note, context: context, storeProvider: storeProvider, generator: generator, root: root)
        }
    }
}
#endif
