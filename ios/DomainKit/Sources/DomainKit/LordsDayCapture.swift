import Foundation

// Photographing Sunday's notes (TKL-860). The spec's non-goal: the photo stays on
// the device. Pages are JPEG files in an app-private folder per note (excluded
// from backup), never fields on LordsDayNote. They are written the moment a page
// is taken, so killing the app mid-capture loses nothing, and they are handed to
// the generator call (LordsDayCardsRequest) once capture is done.

public enum CaptureError: Error, Equatable { case pageLimit, noSuchPage, nothingToSend, tooManyPages, tooLarge }

public struct CapturePage: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    /// Bumped on retake so views reload the thumbnail.
    public var revision: Int
}

/// The pages of one note's capture, in order, backed by files.
public final class CaptureDraft {
    /// The generator endpoint takes 1–6 pages (src/lib/lordsDay/handler.ts MAX_PAGES).
    public static let maxPages = 6

    public let noteId: UUID
    public private(set) var pages: [CapturePage]
    private let folder: URL

    /// `~/Library/Application Support/LordsDayCapture`: app-private, not the App Group the widget reads.
    public static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LordsDayCapture", isDirectory: true)
    }

    public init(noteId: UUID, root: URL = CaptureDraft.defaultRoot) throws {
        self.noteId = noteId
        folder = root.appendingPathComponent(noteId.uuidString, isDirectory: true)
        try Self.makeFolder(root)
        try Self.makeFolder(folder)
        let manifest = folder.appendingPathComponent("pages.json")
        if let data = try? Data(contentsOf: manifest) {
            pages = try JSONDecoder().decode([CapturePage].self, from: data)
        } else {
            pages = []
        }
    }

    public var canAddPage: Bool { pages.count < Self.maxPages }

    @discardableResult public func addPage(_ jpeg: Data) throws -> UUID {
        guard canAddPage else { throw CaptureError.pageLimit }
        let page = CapturePage(id: UUID(), revision: 0)
        try jpeg.write(to: url(for: page.id), options: .atomic)
        pages.append(page)
        try saveManifest()
        return page.id
    }

    public func retakePage(_ id: UUID, with jpeg: Data) throws {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { throw CaptureError.noSuchPage }
        try jpeg.write(to: url(for: id), options: .atomic)
        pages[index].revision += 1
        try saveManifest()
    }

    public func removePage(_ id: UUID) throws {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { throw CaptureError.noSuchPage }
        pages.remove(at: index)
        try saveManifest()
        try? FileManager.default.removeItem(at: url(for: id))
    }

    public func data(for id: UUID) throws -> Data {
        guard pages.contains(where: { $0.id == id }) else { throw CaptureError.noSuchPage }
        return try Data(contentsOf: url(for: id))
    }

    /// Every page's JPEG in order: what the generator call sends.
    public func pageData() throws -> [Data] { try pages.map { try data(for: $0.id) } }

    /// Deletes this note's photos (cancelling a capture, or after the cards are kept).
    public func discard() throws {
        pages = []
        try FileManager.default.removeItem(at: folder)
    }

    /// Read-only count of saved pages for `noteId`, without creating any directory on disk.
    public static func savedPageCount(noteId: UUID, root: URL = CaptureDraft.defaultRoot) -> Int {
        let manifest = root.appendingPathComponent(noteId.uuidString, isDirectory: true).appendingPathComponent("pages.json")
        guard let data = try? Data(contentsOf: manifest),
              let pages = try? JSONDecoder().decode([CapturePage].self, from: data) else { return 0 }
        return pages.count
    }

    // MARK: The capture in progress, so a relaunch resumes it.

    public static func activeNoteId(root: URL = CaptureDraft.defaultRoot) throws -> UUID? {
        guard let text = try? String(contentsOf: root.appendingPathComponent("active"), encoding: .utf8) else { return nil }
        return UUID(uuidString: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public static func setActive(_ noteId: UUID?, root: URL = CaptureDraft.defaultRoot) throws {
        try makeFolder(root)
        let file = root.appendingPathComponent("active")
        if let noteId {
            try Data(noteId.uuidString.utf8).write(to: file, options: .atomic)
        } else if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }

    private func url(for id: UUID) -> URL { folder.appendingPathComponent("\(id.uuidString).jpg") }

    private func saveManifest() throws {
        try JSONEncoder().encode(pages).write(to: folder.appendingPathComponent("pages.json"), options: .atomic)
    }

    private static func makeFolder(_ url: URL) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var copy = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? copy.setResourceValues(values)
    }
}

/// Whether a capture has anything to finish with: a page, or typed notes.
/// Service date, passage, title and preacher are never required.
public struct CaptureContent: Equatable, Sendable {
    public let pageCount: Int
    public let typedText: String?
    public init(pageCount: Int, typedText: String?) { self.pageCount = pageCount; self.typedText = typedText }
    public var canFinish: Bool { pageCount > 0 || normalizedNoteField(typedText) != nil }
}

/// Optional note fields: blank means "not given", stored as nil.
public func normalizedNoteField(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
    return trimmed
}

/// The JSON body of `POST /api/lords-day/cards` (contract in src/lib/lordsDay/handler.ts).
/// Photos and typed notes are two inputs to the same call; photos win when both exist,
/// because the endpoint takes exactly one.
public struct LordsDayCardsRequest: Sendable {
    public static let maxBodyBytes = 4_000_000

    public var pages: [Data]
    public var typedText: String?
    public var passage: String?
    public var title: String?
    public var preacher: String?

    public init(pages: [Data], typedText: String?, passage: String?, title: String?, preacher: String?) {
        self.pages = pages; self.typedText = typedText; self.passage = passage; self.title = title; self.preacher = preacher
    }

    public func body() throws -> Data {
        var json: [String: Any] = [:]
        if !pages.isEmpty {
            guard pages.count <= CaptureDraft.maxPages else { throw CaptureError.tooManyPages }
            json["images"] = pages.map { ["data": $0.base64EncodedString(), "mimeType": "image/jpeg"] }
        } else if let text = normalizedNoteField(typedText) {
            json["extractedText"] = text
        } else {
            throw CaptureError.nothingToSend
        }
        for (key, value) in [("passage", passage), ("title", title), ("preacher", preacher)] {
            if let value = normalizedNoteField(value) { json[key] = value }
        }
        let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        guard data.count <= Self.maxBodyBytes else { throw CaptureError.tooLarge }
        return data
    }
}
