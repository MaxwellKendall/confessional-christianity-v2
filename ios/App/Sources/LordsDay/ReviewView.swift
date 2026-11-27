// Reviewing the drafted cards before the week is kept (TKL-863, the review
// screen of the approved TKL-836 v2 prototype). Cards fill in one at a time as
// the generator reads each page, with a progress line and a placeholder card
// where the next ones will land; nothing blocks, and Close leaves them
// arriving. Each card can be kept or removed, switched between Key point,
// Quote and Verse, and have its words (and a quote's attribution) edited.
// Verse goes through the verse picker, so a Verse card only ever holds a
// reference. "Add N cards to my week" keeps the kept ones, in order.
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
    #endif

    @Environment(\.colorScheme) private var colorScheme
    @Environment(AuthService.self) private var auth
    @State private var current: String?
    @State private var editing: ReviewCard?
    @State private var pickingVerseFor: ReviewCard?
    @State private var showsSignIn = false
    @State private var finishFailed = false

    private var review: LordsDayReview { model.review }
    private var dark: Bool { colorScheme == .dark }
    private var paper: Color { Color(hex: dark ? 0x121513 : 0xf5f5f1) }
    private var ink: Color { Color(hex: dark ? 0xebece6 : 0x1c1f1c) }
    private var ink2: Color { Color(hex: dark ? 0xaeb4ac : 0x545a53) }
    private var fill: Color { Color(hex: dark ? 0x232823 : 0xecede7) }
    private var gilt: Color { Color(hex: dark ? 0xd3a654 : 0xa67a2c) }
    private var chapel: Color { Color(hex: dark ? 0xa8c6b6 : 0x2e4a3e) }
    private var onChapel: Color { Color(hex: dark ? 0x102019 : 0xf2f4ef) }
    private var danger: Color { Color(hex: dark ? 0xec8a7c : 0x9b3328) }
    private var dangerFill: Color { Color(hex: dark ? 0x2c1b18 : 0xf6e9e6) }

    private var currentCard: ReviewCard? {
        review.cards.first { $0.id == current } ?? (current == Self.placeholderId ? nil : review.cards.first)
    }

    private static let placeholderId = "drafting"

    var body: some View {
        VStack(spacing: 0) {
            header
            pager
            dots
            if let card = currentCard { controls(for: card) } else { Spacer(minLength: 0) }
            Spacer(minLength: 0)
            notices
            footer
        }
        .foregroundStyle(ink)
        .background(paper.ignoresSafeArea())
        .onAppear {
            if auth.phase.isSignedIn && model.failure == .accountNeeded {
                model.retry()
            } else {
                model.startIfNeeded()
            }
            #if DEBUG
            if let startAt { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { current = startAt } }
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
        .sheet(item: $editing) { card in
            EditCardSheet(card: card, preacher: model.preacher) { words, attribution in
                try? model.edit(card.id, words: words, attribution: attribution)
            }
        }
        .sheet(item: $pickingVerseFor) { card in
            VersePickerView(startOsis: card.verseRef ?? model.passage.flatMap(citationToOsis)) { osis in
                try? model.chooseVerse(card.id, osis: osis)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button("Close", action: onClose)
                    .font(.system(size: 16))
                    .foregroundStyle(chapel)
                    .accessibilityIdentifier("review.close")
                Spacer()
                Text("Your week, from your notes")
                    .font(.ccDisplay(10.5))
                    .tracking(10.5 * 0.16)
                    .textCase(.uppercase)
                    .foregroundStyle(ink2)
                Spacer()
                Color.clear.frame(width: 44, height: 1)
            }
            .padding(.bottom, 6)
            sermonFields
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(ink2)
                .fixedSize(horizontal: false, vertical: true)
            if review.isDrafting {
                ProgressLine(value: review.progress, track: fill, bar: gilt)
                    .padding(.top, 6)
                    .accessibilityLabel("Reading your notes")
                    .accessibilityValue("\(Int(review.progress * 100)) percent")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    /// The sermon, as the notes named it (TKL-1061), each field edited in place. An empty
    /// title shows what the sermon is otherwise called: its passage, else its date.
    private var sermonFields: some View {
        let date = model.serviceDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let fallback = SermonHeading(title: nil, passage: model.passage, preacher: nil, date: date).headline
        return VStack(alignment: .leading, spacing: 4) {
            TextField("Sermon title", text: $model.titleText, prompt: Text(fallback).foregroundStyle(ink.opacity(0.55)), axis: .vertical)
                .font(.ccDisplay(23, semibold: true))
                .lineLimit(1...2)
                .submitLabel(.done)
                .accessibilityLabel("Sermon title")
                .accessibilityIdentifier("review.sermon.title")
            HStack(spacing: 6) {
                TextField("Preacher", text: $model.preacherText, prompt: Text("Preacher").foregroundStyle(ink2.opacity(0.6)))
                    .fixedSize()
                    .accessibilityIdentifier("review.sermon.preacher")
                Text("·").foregroundStyle(ink2.opacity(0.6))
                TextField("Passage", text: $model.passageText, prompt: Text("Passage").foregroundStyle(ink2.opacity(0.6)))
                    .accessibilityIdentifier("review.sermon.passage")
            }
            .font(.system(size: 14))
            .foregroundStyle(ink2)
            .lineLimit(1)
        }
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled()
    }

    private var subtitle: String {
        let count = review.cards.count
        if review.isDrafting {
            // Real units: which page the model is on, and what it has found (TKL-1053).
            let read = review.transcribedPageCount
            let where_ = review.pageCount > 1 && read > 0 ? "Page \(min(read + 1, review.pageCount)) of \(review.pageCount)" : "Reading your notes"
            let so = count == 0 ? "" : " · \(count) card\(count == 1 ? "" : "s") so far"
            return "\(where_)\(so). You can close this; they keep coming."
        }
        if count == 0 { return "No cards yet." }
        return "Swipe through. Change the kind, edit the words, ask again, or remove."
    }

    // MARK: Pager

    private var pagerIds: [String] {
        review.cards.map(\.id) + (review.isDrafting ? [Self.placeholderId] : [])
    }

    private var pager: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(review.cards) { card in
                    ReviewCardView(card: card, palette: palette(for: card), preacher: model.preacher)
                        .containerRelativeFrame(.horizontal)
                        .id(card.id)
                        .accessibilityIdentifier("review.card.\(card.id)")
                        .transition(.opacity.combined(with: .offset(y: 10)))
                }
                if review.isDrafting {
                    DraftingCard(
                        fill: fill,
                        ink2: ink2,
                        accent: chapel,
                        cardsSoFar: review.cards.count,
                        transcription: review.newestTranscription
                    )
                        .containerRelativeFrame(.horizontal)
                        .id(Self.placeholderId)
                }
            }
            .scrollTargetLayout()
            .animation(.easeOut(duration: 0.35), value: review.cards.map(\.id))
        }
        .contentMargins(.horizontal, 32, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $current)
        .frame(maxHeight: 440)
        .frame(minHeight: 300)
        .overlay {
            if review.cards.isEmpty && !review.isDrafting { emptyState }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text(review.phase == .notStarted ? "Your notes are saved." : "No cards came back from these notes.")
                .font(.ccBody(19))
            Text(review.phase == .notStarted ? "Cards are drafted from them when you try again." : "Try again, or retake the photos with the whole page in frame.")
                .font(.system(size: 14))
                .foregroundStyle(ink2)
        }
        .multilineTextAlignment(.center)
        .padding(32)
    }

    private func palette(for card: ReviewCard) -> QuoteCardPalette {
        let index = review.cards.firstIndex(of: card) ?? 0
        return LordsDayFeed.palette(LordsDayFeed.rotation[index % LordsDayFeed.rotation.count], dark: dark)
    }

    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(pagerIds, id: \.self) { id in
                let on = id == (current ?? pagerIds.first)
                RoundedRectangle(cornerRadius: 3)
                    .fill(on ? ink : ink.opacity(0.2))
                    .frame(width: on ? 16 : 6, height: 6)
            }
        }
        .padding(.top, 12)
        .animation(.easeOut(duration: 0.2), value: current)
        .accessibilityHidden(true)
    }

    // MARK: Controls for the current card

    private func controls(for card: ReviewCard) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(CardKind.allCases, id: \.self) { kind in
                    Button {
                        if kind == .verse { pickingVerseFor = card } else { try? model.setKind(card.id, to: kind) }
                    } label: {
                        Text(kind.label)
                            .font(.system(size: 13.5, weight: card.kind == kind ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(card.kind == kind ? ink : fill, in: Capsule())
                            .foregroundStyle(card.kind == kind ? paper : ink2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(card.kind == kind ? .isSelected : [])
                    .accessibilityHint(kind == .verse ? "Opens the Bible to pick the verse" : "")
                }
            }
            // Cards arrive kept, so there is no Keep to press. Editing is the
            // call to action; removing is deliberate, quiet and reversible.
            HStack(spacing: 10) {
                if card.isRemoved {
                    Button { model.keep(card.id) } label: {
                        Label("Keep this card", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 15, weight: .semibold))
                            .padding(.vertical, 10)
                            .padding(.horizontal, 18)
                            .background(chapel.opacity(0.14), in: Capsule())
                            .foregroundStyle(chapel)
                    }
                    .accessibilityIdentifier("review.keep")
                } else {
                    Button {
                        if card.kind == .verse { pickingVerseFor = card } else { editing = card }
                    } label: {
                        Label(
                            card.kind == .verse ? "Change verse" : "Edit",
                            systemImage: card.kind == .verse ? "book" : "pencil"
                        )
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 20)
                        .background(chapel, in: Capsule())
                        .foregroundStyle(onChapel)
                    }
                    .accessibilityIdentifier("review.edit")

                    if model.canRedraft(card.id) {
                        Button { model.redraft(card.id) } label: {
                            Label("Try again", systemImage: "arrow.triangle.2.circlepath")
                                .font(.system(size: 15))
                                .padding(.vertical, 10)
                                .padding(.horizontal, 14)
                                .foregroundStyle(chapel)
                                .opacity(model.redrafting == card.id ? 0.4 : 1)
                        }
                        .disabled(model.redrafting != nil)
                        .accessibilityIdentifier("review.redraft")
                        .accessibilityHint("Asks for another card in this one's place")
                    }

                    Button { model.remove(card.id) } label: {
                        Label("Remove", systemImage: "xmark")
                            .font(.system(size: 15))
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .foregroundStyle(ink2)
                    }
                    .accessibilityIdentifier("review.remove")
                }
            }
            .buttonStyle(.plain)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 4)
        }
        .padding(.top, 14)
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
        .padding(.horizontal, 20)
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
            Text(text).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                if let actionTitle {
                    Button(actionTitle, action: action)
                        .font(.system(size: 14, weight: .semibold))
                        .accessibilityIdentifier(actionId ?? actionTitle)
                }
                if let secondaryTitle, let secondaryAction {
                    Button(secondaryTitle, action: secondaryAction)
                        .font(.system(size: 13, weight: .medium))
                        .accessibilityIdentifier(secondaryId ?? secondaryTitle)
                }
            }
        }
        .foregroundStyle(danger)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(dangerFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var footer: some View {
        VStack(spacing: 6) {
            if let index = review.blockingCardIndex {
                Button {
                    current = review.cards[index].id
                } label: {
                    Text("Card \(index + 1) has no words. Edit it or remove it.")
                        .font(.system(size: 13))
                        .foregroundStyle(danger)
                }
                .buttonStyle(.plain)
            } else if !review.isDrafting, !review.unhandledUnreadPages.isEmpty {
                let n = review.unhandledUnreadPages.count
                Text(
                    review.canRetry
                        ? "Retry or skip \(n) unread page\(n == 1 ? "" : "s") to finish."
                        : "Keep what's here to finish without \(n) unfinished page\(n == 1 ? "" : "s")."
                )
                    .font(.system(size: 13))
                    .foregroundStyle(ink2)
                    .accessibilityIdentifier("review.unreadHint")
            }
            Button {
                do {
                    try model.finish()
                    onFinish()
                } catch {
                    finishFailed = true
                }
            } label: {
                Text(finishLabel)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(chapel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(onChapel)
            }
            .disabled(!review.canFinish)
            .opacity(review.canFinish ? 1 : 0.4)
            .accessibilityIdentifier("review.finish")
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var finishLabel: String {
        if review.isDrafting { return "Reading your notes…" }
        let count = review.keptCount
        return "Add \(count) card\(count == 1 ? "" : "s") to my week"
    }
}

// MARK: Cards

private struct ReviewCardView: View {
    let card: ReviewCard
    let palette: QuoteCardPalette
    let preacher: String?
    @State private var verseText: String?

    private var accent: Color { Color(hex: palette.accent) }
    private var muted: Color { Color(hex: palette.muted) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(hex: palette.field)
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                Text(card.kind.label)
                    .font(.ccDisplay(10.5))
                    .tracking(10.5 * 0.2)
                    .textCase(.uppercase)
                    .foregroundStyle(accent)
                    .padding(.bottom, 18)
                // A long passage must never trail off (TKL-1053). When the words fit
                // they render as before; when they don't, the card scrolls them.
                ViewThatFits(in: .vertical) {
                    content
                    ScrollView(.vertical, showsIndicators: false) {
                        content.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: 34, leading: 26, bottom: 48, trailing: 26))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            Text(source)
                .font(.system(size: 12))
                .foregroundStyle(muted)
                .lineLimit(2)
                .padding(.horizontal, 26)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

            if let badge = statusBadge {
                Text(badge)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(muted)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .foregroundStyle(Color(hex: palette.ink))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .opacity(card.isRemoved ? 0.35 : 1)
        .scaleEffect(card.isRemoved ? 0.96 : 1)
        .animation(.easeOut(duration: 0.2), value: card.decision)
        .accessibilityElement(children: .combine)
        .task(id: card.verseRef) {
            verseText = nil
            guard card.kind == .verse, let ref = card.verseRef, let osis = osis(ref) else { return }
            if let bundled = bundledEsvText(for: osis), !bundled.isEmpty { verseText = bundled; return }
            verseText = await EsvClient.shared.text(for: osis)
        }
    }

    @ViewBuilder private var content: some View {
        switch card.kind {
        case .keyPoint, .quote:
            Text(card.text.isEmpty ? "No words yet. Tap Edit." : card.text)
                .font(.ccBody(22))
                .lineSpacing(5)
                .opacity(card.text.isEmpty ? 0.6 : 1)
        case .verse:
            let reference = card.verseRef.map { ref in osis(ref).map(parseOsisBibleReference) ?? ref } ?? ""
            if let verseText = verseText?.trimmingCharacters(in: .whitespacesAndNewlines), !verseText.isEmpty {
                Text(verseText)
                    .font(.ccBody(21))
                    .lineSpacing(5)
                Text(reference)
                    .font(.ccDisplay(12))
                    .tracking(12 * 0.18)
                    .textCase(.uppercase)
                    .foregroundStyle(accent)
                    .padding(.top, 16)
            } else {
                Text(reference).font(.ccBody(28))
            }
        }
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

    private var statusBadge: String? {
        switch card.decision {
        case .remove: "Removed"
        case .keep: card.editedByUser ? "Kept · Edited" : "Kept"
        case .undecided: card.editedByUser ? "Edited" : nil
        }
    }

    private func osis(_ ref: String) -> String? {
        ReaderChapter.chapterOSIS(for: ref) != nil ? ref : citationToOsis(ref)
    }
}

/// Where the next cards will land while the generator is still reading.
private struct DraftingCard: View {
    let fill: Color
    let ink2: Color
    let accent: Color
    let cardsSoFar: Int
    /// The model's transcription of the page it has just read, once there is one.
    let transcription: String?
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(fill)
            .overlay {
                VStack(alignment: .leading, spacing: 12) {
                    if let transcription, !transcription.isEmpty {
                        // The writer's own words, as the model read them (TKL-1053).
                        Text("Read from your notes")
                            .font(.ccDisplay(10.5))
                            .tracking(10.5 * 0.2)
                            .textCase(.uppercase)
                            .foregroundStyle(accent)
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
                                .fill(ink2.opacity(pulse ? 0.16 : 0.08))
                                .containerRelativeFrame(.horizontal) { length, _ in length * width * 0.75 }
                                .frame(height: width == 0.4 ? 10 : 18)
                        }
                    }
                    Text(cardsSoFar == 0 ? "Reading your notes…" : "More cards on the way…")
                        .font(.system(size: 13))
                        .foregroundStyle(ink2)
                        .padding(.top, 8)
                }
                .padding(26)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
            }
            .accessibilityElement()
            .accessibilityLabel("More cards on the way")
    }
}

private struct ProgressLine: View {
    let value: Double
    let track: Color
    let bar: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(bar).frame(width: max(8, geometry.size.width * value))
            }
        }
        .frame(height: 3)
        .animation(.easeOut(duration: 0.5), value: value)
    }
}

// MARK: Editing

private struct EditCardSheet: View {
    let card: ReviewCard
    let preacher: String?
    let save: (String, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var words: String
    @State private var attribution: String
    private let initialAttribution: String

    init(card: ReviewCard, preacher: String?, save: @escaping (String, String?) -> Void) {
        self.card = card
        self.preacher = preacher
        self.save = save
        _words = State(initialValue: card.text)
        initialAttribution = card.attribution ?? preacher ?? ""
        _attribution = State(initialValue: initialAttribution)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $words)
                        .font(.ccBody(18))
                        .frame(minHeight: 140)
                } header: {
                    Text(card.kind.label)
                } footer: {
                    Text("Drafted from your photo. Change the words; they're yours.")
                }
                if card.kind == .quote {
                    Section {
                        HStack {
                            TextField("Who said it", text: $attribution)
                                .textInputAutocapitalization(.words)
                            if !attribution.isEmpty {
                                Button { attribution = "" } label: { Image(systemName: "xmark.circle.fill") }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("Clear attribution")
                            }
                        }
                    } header: {
                        Text("Attribution")
                    } footer: {
                        Text("Leave it empty to name no one.")
                    }
                }
            }
            .navigationTitle("Edit card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        // An untouched attribution stays as drafted (nil still means "the preacher").
                        save(words, card.kind == .quote && attribution != initialAttribution ? attribution : nil)
                        dismiss()
                    }
                    .disabled(words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#if DEBUG
/// Screenshot hook: `-LordsDayReviewFixture filling|complete|smyrna`, optionally
/// `-LordsDayReviewCard p0-1` (or `drafting`) to open at that card. Replays sample
/// drafts into a throwaway folder and an in-memory store; `filling` stops
/// after two pages and stays mid-fill. `smyrna` drafts the Revelation 2:8-11 note
/// from a note with no sermon fields, so its title, preacher and passage come from the
/// drafted `sermon` event (TKL-1061).
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
        ZStack {
            if finished {
                RootView()
            } else if let model {
                ReviewView(model: model, onClose: {}, onFinish: {
                    if persistsToAppStore { finished = true }
                }, startAt: UserDefaults.standard.string(forKey: "LordsDayReviewCard"))
                    .onChange(of: model.review.canFinish) { _, ready in
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
            for _ in 0..<(scene == "smyrna" ? 1 : 3) { try! draft.addPage(CaptureModel.jpegForUpload(CaptureFixture.samplePage())!) }
            let generator = scene == "smyrna"
                ? FixtureCardsGenerator.smyrna
                : FixtureCardsGenerator(stopsAfter: scene == "filling" ? 2 : nil, delay: .milliseconds(scene == "filling" ? 300 : 150))
            model = ReviewModel.session(for: note, context: context, storeProvider: storeProvider, generator: generator, root: root)
        }
    }
}
#endif
