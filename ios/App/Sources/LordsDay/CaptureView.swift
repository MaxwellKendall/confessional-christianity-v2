// Photographing Sunday's notes (TKL-860), per the approved v2 prototype on
// TKL-836: a dark camera screen with a viewfinder, the shutter, a strip of the
// pages taken, and Done. "Choose from Photos" and "Type instead" sit either side
// of the shutter. Passage, title, preacher and date are optional, behind a
// details row. Every change autosaves (CaptureModel); the pages stay on the
// device and wait for the generator call (TKL-863).
import SwiftUI
import SwiftData
import PhotosUI
import DomainKit

private let camBackground = Color(hex: 0x0d0f0e)
private let camGilt = Color(hex: 0xd3a654)
private let camPaper = Color(hex: 0xfbf8ef)
// The camera is always dark, so its light button can't be the adaptive on-chapel (dark text's colour there).
private let camButton = Color(hex: 0xf2f4ef)

/// The system's light/dark setting. The camera forces dark on its whole
/// presentation, so a sheet it opens would inherit dark from it; the window
/// scene still carries the system's own choice (TKL-949).
@MainActor func systemColorScheme() -> ColorScheme {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    return scene?.traitCollection.userInterfaceStyle == .dark ? .dark : .light
}

struct CaptureView: View {
    @State var model: CaptureModel
    var onClose: () -> Void
    /// Done: the notes are ready to draft cards from (TKL-863). Without it, Done just closes.
    var onFinish: (() -> Void)? = nil
    /// DEBUG screenshots: the simulator has no camera, so show a sample page in the viewfinder.
    var simulatedViewfinder: UIImage? = nil

    @State private var camera = CameraController()
    @State private var cameraStatus: CameraController.Status = .starting
    @State private var picked: [PhotosPickerItem] = []
    @State private var showsPicker = false
    @State private var showsTyping = false
    @State private var showsDetails = false
    @State private var showsCancel = false
    @State private var selectedPage: CapturePage?
    @State private var shutterFlash = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            detailsRow
            viewfinder
                .padding(.horizontal, 18)
                .padding(.top, 12)
            if let target = model.retakeTarget, let index = model.pages.firstIndex(where: { $0.id == target }) {
                retakeBanner(index: index)
            }
            pageStrip
            controls
            footer
        }
        .background(camBackground.ignoresSafeArea())
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .task {
            if simulatedViewfinder == nil { cameraStatus = await camera.start() } else { cameraStatus = .unavailable }
        }
        .onDisappear { camera.stop() }
        .photosPicker(isPresented: $showsPicker, selection: $picked,
                      maxSelectionCount: model.retakeTarget != nil ? 1 : max(1, CaptureDraft.maxPages - model.pages.count),
                      selectionBehavior: .ordered, matching: .images)
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            Task { await addPicked(items) }
        }
        .sheet(isPresented: $showsTyping) {
            TypeNotesView(model: model).preferredColorScheme(systemColorScheme())
        }
        .sheet(isPresented: $showsDetails) {
            NoteDetailsView(model: model).preferredColorScheme(systemColorScheme())
        }
        .confirmationDialog(selectedPage.flatMap { page in model.pages.firstIndex(of: page).map { "Page \($0 + 1)" } } ?? "Page",
                            isPresented: Binding(get: { selectedPage != nil }, set: { if !$0 { selectedPage = nil } }),
                            titleVisibility: .visible, presenting: selectedPage) { page in
            Button("Retake") { model.retakeTarget = page.id }
            Button("Replace from Photos") { model.retakeTarget = page.id; showsPicker = true }
            Button("Remove", role: .destructive) { model.removePage(page.id) }
        }
        .confirmationDialog("Leave Sunday's notes?", isPresented: $showsCancel, titleVisibility: .visible) {
            Button("Keep for later") { onClose() }
            Button("Discard notes", role: .destructive) { model.discard(); onClose() }
        } message: {
            Text("They're saved on this iPhone. You can come back and finish them.")
        }
    }

    // MARK: Parts

    private var topBar: some View {
        HStack {
            Button("Cancel") { if model.hasContent { showsCancel = true } else { onClose() } }
                .font(.system(size: 16))
            Spacer()
            Text("Sunday's notes")
                .labelCaps(size: 12, tracking: 0.14, color: .white.opacity(0.85))
            Spacer()
            SavedIndicator(state: model.saveState)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var detailsRow: some View {
        Button { showsDetails = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                Text(detailsSummary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("Edit")
                    .foregroundStyle(camGilt)
            }
            .font(.system(size: 13.5))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .accessibilityLabel("Service details, optional: \(detailsSummary)")
    }

    private var detailsSummary: String {
        let date = model.serviceDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let parts = [normalizedNoteField(model.passage), normalizedNoteField(model.title), normalizedNoteField(model.preacher)].compactMap { $0 }
        return parts.isEmpty ? "\(date) · passage, title, preacher (optional)" : ([date] + parts).joined(separator: " · ")
    }

    private var viewfinder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(hex: 0x2a2a27))
            switch cameraStatus {
            case .running:
                CameraPreview(session: camera.session)
            case .starting:
                Text("Starting camera…").font(.system(size: 14)).opacity(0.6)
            case .denied:
                cameraMessage(title: "Camera is off",
                              body: "Allow camera access in Settings to photograph your notes, or choose a photo you already took.",
                              settings: true)
            case .unavailable:
                if let simulatedViewfinder {
                    Image(uiImage: simulatedViewfinder)
                        .resizable()
                        .scaledToFit()
                        .rotationEffect(.degrees(-2.5))
                        .shadow(color: .black.opacity(0.5), radius: 15, y: 8)
                        .padding(28)
                } else {
                    cameraMessage(title: "No camera here",
                                  body: "Choose a photo of your notes, or type them instead.",
                                  settings: false)
                }
            }
            Corners().stroke(camGilt, style: StrokeStyle(lineWidth: 3, lineCap: .round)).padding(22)
                .allowsHitTesting(false)
            if shutterFlash { Color.white.opacity(0.7) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(maxHeight: .infinity)
    }

    private func cameraMessage(title: String, body: String, settings: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.ccDisplay(22, semibold: true))
            Text(body).font(.system(size: 15)).opacity(0.8).fixedSize(horizontal: false, vertical: true)
            if settings, let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url).foregroundStyle(camGilt).font(.system(size: 15, weight: .semibold))
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func retakeBanner(index: Int) -> some View {
        HStack {
            Text("Retaking page \(index + 1)").font(.system(size: 13.5, weight: .medium))
            Spacer()
            Button("Keep it") { model.retakeTarget = nil }.foregroundStyle(camGilt).font(.system(size: 13.5))
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private var pageStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(model.pages.enumerated()), id: \.element.id) { index, page in
                    Button { selectedPage = page } label: {
                        Group {
                            if let image = model.thumbnails[page.id] {
                                Image(uiImage: image).resizable().scaledToFill()
                            } else {
                                camPaper
                            }
                        }
                        .frame(width: 40, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(model.retakeTarget == page.id ? camGilt : .clear, lineWidth: 2))
                        .overlay(alignment: .bottomTrailing) {
                            Text("\(index + 1)")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(.black.opacity(0.6), in: Capsule())
                                .padding(2)
                        }
                    }
                    .accessibilityLabel("Page \(index + 1). Retake or remove")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 20)
            .animation(.spring(duration: 0.25), value: model.pages)
        }
        .frame(height: 58)
        .padding(.top, 8)
    }

    private var controls: some View {
        HStack {
            sideButton(icon: "photo.on.rectangle", label: "Choose from\nPhotos") { showsPicker = true }
                .disabled(!model.canAddPage)
                .accessibilityIdentifier("capture.photos")
            Spacer()
            Button(action: shoot) {
                Circle().strokeBorder(.white, lineWidth: 4).frame(width: 74, height: 74)
                    .overlay(Circle().fill(.white).frame(width: 60, height: 60))
            }
            .disabled(!canShoot)
            .opacity(canShoot ? 1 : 0.35)
            .accessibilityLabel(model.retakeTarget == nil ? "Take photo" : "Retake photo")
            Spacer()
            sideButton(icon: "pencil.line", label: "Type\ninstead") { showsTyping = true }
                .accessibilityIdentifier("capture.type")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var canShoot: Bool {
        model.canAddPage && (cameraStatus == .running || simulatedViewfinder != nil)
    }

    private func sideButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 22))
                Text(label).font(.system(size: 12)).multilineTextAlignment(.center).lineLimit(2)
            }
            .frame(width: 84)
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        Button {
            model.finish()
            (onFinish ?? onClose)()
        } label: {
            Text(finishLabel)
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(camButton, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(Color(hex: 0x102019))
        }
        .disabled(!model.canFinish)
        .opacity(model.canFinish ? 1 : 0.35)
        .accessibilityIdentifier("capture.done")
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var finishLabel: String {
        let count = model.pages.count
        if count > 0 { return "Done · \(count) page\(count == 1 ? "" : "s")" }
        if model.canFinish { return "Done · typed notes" }
        return "Take a photo of each page"
    }

    // MARK: Actions

    private func shoot() {
        withAnimation(.easeOut(duration: 0.12)) { shutterFlash = true }
        Task {
            let image: UIImage? = if let simulatedViewfinder { simulatedViewfinder } else { await camera.capture() }
            withAnimation(.easeIn(duration: 0.2)) { shutterFlash = false }
            if let image { model.addPhoto(image) }
        }
    }

    private func addPicked(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard model.canAddPage,
                  let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { continue }
            model.addPhoto(image)
        }
    }
}

/// The gilt corner brackets on the viewfinder.
private struct Corners: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let arm: CGFloat = 40
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + arm))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + arm, y: rect.minY))
        path.move(to: CGPoint(x: rect.maxX - arm, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - arm))
        return path
    }
}

struct SavedIndicator: View {
    let state: CaptureModel.SaveState
    var color: Color = Color(hex: 0xd3a654)

    var body: some View {
        switch state {
        case .idle: EmptyView()
        case .saved:
            HStack(spacing: 4) { Image(systemName: "checkmark.circle.fill"); Text("Saved") }
                .fixedSize()
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(color)
                .accessibilityLabel("Saved on this iPhone")
        case .failed:
            HStack(spacing: 4) { Image(systemName: "exclamationmark.triangle.fill"); Text("Not saved") }
                .fixedSize()
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.red)
        }
    }
}

/// "Type instead": a plain notes field. What's typed becomes the note's
/// `extractedText`, the same text the photo path reads from a page.
struct TypeNotesView: View {
    @Bindable var model: CaptureModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Text("Type the main lines: a point, a quote, a verse. The same cards come from this as from a photo.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.ccInk2)
                    .fixedSize(horizontal: false, vertical: true)
                TextEditor(text: $model.typedText)
                    .font(.ccBody(17))
                    .foregroundStyle(Color.ccInk)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Color.ccFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.ccHairline, lineWidth: 1))
                    .focused($focused)
                    .accessibilityLabel("Sermon notes")
            }
            .padding(20)
            .background(Color.ccCard.ignoresSafeArea())
            .navigationTitle("Type instead")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.ccCard, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SavedIndicator(state: model.saveState, color: .ccGilt)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Color.ccInk)
                }
            }
            .onAppear { focused = true }
        }
    }
}

/// Service date, passage, title and preacher: all optional.
struct NoteDetailsView: View {
    @Bindable var model: CaptureModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Service date", selection: $model.serviceDate, displayedComponents: .date)
                    TextField("Passage, e.g. Romans 8:28–30", text: $model.passage)
                    TextField("Sermon title", text: $model.title)
                    TextField("Preacher", text: $model.preacher)
                } footer: {
                    Text("All optional. A photo of your notes is enough.")
                }
                .listRowBackground(Color.ccFill)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { SavedIndicator(state: model.saveState, color: .ccGilt) }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.ccCard)
        .tint(.ccInk)
    }
}

#if DEBUG
/// Screenshot hook: `-LordsDayCaptureFixture camera|strip|type|details`. Uses a
/// throwaway folder and an in-memory store, so it never touches real notes.
struct CaptureFixture: View {
    let scene: String
    @State private var model: CaptureModel?
    @State private var showsTyping = false
    @State private var showsDetails = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let model {
                CaptureView(model: model, onClose: {}, simulatedViewfinder: Self.samplePage())
                    .sheet(isPresented: $showsTyping) { TypeNotesView(model: model).preferredColorScheme(systemColorScheme()) }
                    .sheet(isPresented: $showsDetails) { NoteDetailsView(model: model).preferredColorScheme(systemColorScheme()) }
            }
        }
        .task {
            let container = try! ModelContainer(for: progressSchema, configurations: [ModelConfiguration(schema: progressSchema, isStoredInMemoryOnly: true)])
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("capture-fixture-\(UUID().uuidString)")
            let model = CaptureModel(context: ModelContext(container), root: root)
            if scene == "strip" {
                for _ in 0..<3 { model.addPhoto(Self.samplePage()) }
                model.passage = "Romans 8:28–30"
            }
            if scene == "type" {
                model.typedText = "God works all things for good to those called.\n\"The golden chain cannot be broken.\"\nRomans 8:30"
            }
            self.model = model
            if scene == "type" { showsTyping = true }
            if scene == "details" { model.passage = "Romans 8:28–30"; showsDetails = true }
        }
    }

    @MainActor static func samplePage() -> UIImage {
        let page = VStack(alignment: .leading, spacing: 6) {
            Text("Rom 8:28–30").foregroundStyle(Color(hex: 0x9b3328))
            Text("God works ALL things")
            Text("for good — those called")
            Text("“The golden chain cannot")
            Text("be broken.”")
            Text("foreknew → predestined →")
            Text("called → justified → glorified")
        }
        .font(.custom("Marker Felt", size: 21))
        .foregroundStyle(Color(hex: 0x253a6b))
        .padding(24)
        .frame(width: 300, height: 400, alignment: .topLeading)
        .background(camPaper)
        let renderer = ImageRenderer(content: page)
        renderer.scale = 2
        return renderer.uiImage ?? UIImage()
    }
}
#endif
