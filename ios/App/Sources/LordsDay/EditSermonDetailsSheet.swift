// Focused sheet for editing a sermon's details (TKL-1085, pass 1): Title,
// Preacher, Passage, Church and Date. Shared by the review screen, a kept
// sermon's cover card (landing + reel), and the journal summary. Keeps the
// focused field visible above the keyboard, validates Passage on the server's
// OSIS path with an inline error (never silently dropping it), and marks fields
// that came from the notes.
import SwiftUI
import DomainKit

struct EditSermonDetailsSheet: View {
    enum Field: String, Hashable, CaseIterable {
        /// Not a text field: opening on it shows the calendar and scrolls to it (TKL-1085).
        case title, preacher, passage, church, date
    }

    let initial: SermonDetailsEdit
    let readFromNotes: SermonDetails?
    /// Nothing said when it was preached (no date in the notes, no photo date): say so.
    var dateIsGuess: Bool = false
    var initialFocus: Field? = nil
    let onSave: (SermonDetailsEdit) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var preacher: String
    @State private var passage: String
    @State private var church: String
    @State private var serviceDate: Date
    @State private var saveError: String?
    @State private var showsCalendar: Bool
    @FocusState private var focused: Field?

    init(
        initial: SermonDetailsEdit,
        readFromNotes: SermonDetails? = nil,
        dateIsGuess: Bool = false,
        initialFocus: Field? = nil,
        onSave: @escaping (SermonDetailsEdit) throws -> Void
    ) {
        self.initial = initial
        self.readFromNotes = readFromNotes
        self.dateIsGuess = dateIsGuess
        self.initialFocus = initialFocus
        _showsCalendar = State(initialValue: initialFocus == .date)
        self.onSave = onSave
        _title = State(initialValue: initial.title ?? "")
        _preacher = State(initialValue: initial.preacher ?? "")
        _passage = State(initialValue: initial.passage ?? "")
        _church = State(initialValue: initial.church ?? "")
        _serviceDate = State(initialValue: initial.serviceDate)
    }

    private var passageValidation: SermonPassageValidation {
        validateSermonPassage(passage)
    }

    private var passageError: String? {
        if case .invalid(let message) = passageValidation { return message }
        return nil
    }

    private var calendarIsUnchanged: Bool {
        Calendar.current.isDate(serviceDate, inSameDayAs: initial.serviceDate)
    }

    private var canSave: Bool {
        passageError == nil
    }

    private var readFlags: SermonDetailsReadFlags {
        readFromNotes?.readFlags(
            title: title,
            preacher: preacher,
            passage: passage,
            church: church,
            serviceDate: serviceDate
        ) ?? .none
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: ChapelSpace.l) {
                        textField(
                            id: .title,
                            label: "Title",
                            placeholder: "Sermon title",
                            text: $title,
                            readFromNotes: readFlags.title,
                            isDisplay: true,
                            submitLabel: .next,
                            accessibilityId: "sermonDetails.title"
                        ) {
                            focused = .preacher
                        }

                        textField(
                            id: .preacher,
                            label: "Preacher",
                            placeholder: "Not on the page",
                            text: $preacher,
                            readFromNotes: readFlags.preacher,
                            isDisplay: false,
                            submitLabel: .next,
                            accessibilityId: "sermonDetails.preacher"
                        ) {
                            focused = .passage
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            textField(
                                id: .passage,
                                label: "Passage",
                                placeholder: "e.g. Revelation 2:8-11",
                                text: $passage,
                                readFromNotes: readFlags.passage,
                                isDisplay: false,
                                hasError: passageError != nil,
                                submitLabel: .next,
                                accessibilityId: "sermonDetails.passage"
                            ) {
                                focused = .church
                            }
                            if let passageError {
                                Text(passageError)
                                    .font(.ccUI(13))
                                    .foregroundStyle(.ccDanger)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("sermonDetails.passageError")
                            }
                        }

                        textField(
                            id: .church,
                            label: "Church",
                            placeholder: "Congregation name",
                            text: $church,
                            readFromNotes: readFlags.church,
                            isDisplay: false,
                            submitLabel: .done,
                            accessibilityId: "sermonDetails.church"
                        ) {
                            if canSave {
                                focused = nil
                                save()
                            } else {
                                focused = .passage
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            fieldHeader("Date", readFromNotes: readFlags.serviceDate)
                            Group {
                                if showsCalendar {
                                    DatePicker("Service date", selection: $serviceDate, in: ...Date(), displayedComponents: .date)
                                        .datePickerStyle(.graphical)
                                        .labelsHidden()
                                        .padding(.horizontal, 4)
                                } else {
                                    HStack {
                                        DatePicker("Service date", selection: $serviceDate, displayedComponents: .date)
                                            .labelsHidden()
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 46)
                                }
                            }
                            .tint(.ccChapel)
                            .accessibilityIdentifier("sermonDetails.date")
                            .background(Color.ccSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(showsCalendar ? Color.ccChapel : Color.ccLine, lineWidth: showsCalendar ? 1.5 : 1)
                            )
                            if dateIsGuess && calendarIsUnchanged {
                                Text("A guess: neither your notes nor the photos say when it was preached. Pick the Sunday.")
                                    .font(.ccUI(13))
                                    .foregroundStyle(.ccOchre)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("sermonDetails.dateGuess")
                            }
                        }
                        .id(Field.date)

                        if let saveError {
                            Text(saveError)
                                .font(.ccUI(13.5))
                                .foregroundStyle(.ccDanger)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.ccDangerFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    .padding(.horizontal, ChapelSpace.gutter)
                    .padding(.top, ChapelSpace.l)
                    .padding(.bottom, 32)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(Color.ccPaper.ignoresSafeArea())
                .onChange(of: focused) { _, target in
                    guard let target else { return }
                    if target == .date { focused = nil; return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                }
                .onAppear {
                    if let initialFocus {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            if initialFocus != .date { focused = initialFocus }
                            proxy.scrollTo(initialFocus, anchor: .center)
                        }
                    }
                }
            }
            .navigationTitle("Sermon details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.ccPaper, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.ccChapel)
                        .accessibilityIdentifier("sermonDetails.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: save)
                        .fontWeight(.semibold)
                        .foregroundStyle(canSave ? .ccChapel : .ccInk3)
                        .disabled(!canSave)
                        .accessibilityIdentifier("sermonDetails.done")
                }
            }
        }
        .tint(.ccChapel)
    }

    private func fieldHeader(_ label: String, readFromNotes: Bool) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.ccUI(11.5, weight: .medium))
                .tracking(11.5 * 0.08)
                .textCase(.uppercase)
                .foregroundStyle(.ccInk3)
            if readFromNotes {
                Text("read from your notes")
                    .font(.ccUI(11.5))
                    .foregroundStyle(.ccGilt)
            }
        }
    }

    private func textField(
        id: Field,
        label: String,
        placeholder: String,
        text: Binding<String>,
        readFromNotes: Bool,
        isDisplay: Bool,
        hasError: Bool = false,
        submitLabel: SubmitLabel,
        accessibilityId: String,
        onSubmit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldHeader(label, readFromNotes: readFromNotes)
            HStack(spacing: 8) {
                TextField(
                    label,
                    text: text,
                    prompt: Text(placeholder).foregroundStyle(Color.ccInk3)
                )
                .font(isDisplay ? .ccDisplay(17, semibold: true) : .ccUI(16))
                .foregroundStyle(.ccInk)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(submitLabel)
                .focused($focused, equals: id)
                .onSubmit(onSubmit)
                .accessibilityIdentifier(accessibilityId)
                if !text.wrappedValue.isEmpty {
                    Button {
                        text.wrappedValue = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.ccInk3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear \(label)")
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 46)
            .background(Color.ccSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        hasError ? Color.ccDanger : (focused == id ? Color.ccChapel : Color.ccLine),
                        lineWidth: hasError || focused == id ? 1.5 : 1
                    )
            )
        }
        .id(id)
    }

    private func save() {
        let canonicalPassage: String?
        switch passageValidation {
        case .empty:
            canonicalPassage = nil
        case .valid(let canonical, _):
            canonicalPassage = canonical
        case .invalid:
            focused = .passage
            return
        }
        let edit = SermonDetailsEdit(
            title: normalizedNoteField(title),
            preacher: normalizedNoteField(preacher),
            passage: canonicalPassage,
            church: normalizedNoteField(church),
            serviceDate: serviceDate
        )
        do {
            try onSave(edit)
            dismiss()
        } catch {
            saveError = "Couldn't save on this iPhone. Try again."
        }
    }
}
