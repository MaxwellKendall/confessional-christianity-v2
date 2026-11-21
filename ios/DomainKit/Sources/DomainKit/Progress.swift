import Darwin
import Foundation
import SwiftData

public struct MilestoneRecord: Codable, Equatable, Sendable {
    public var state: String // "introduced" | "reviewing" | "mastered"
    public var introducedAt: Date
    public var reviewCount: Int

    public init(state: String, introducedAt: Date, reviewCount: Int) {
        self.state = state
        self.introducedAt = introducedAt
        self.reviewCount = reviewCount
    }
}

// Retain the shipped entity so SwiftData can open every older store shape.
// The shared container transfers and deletes its rows in one save.
@Model
final class LocalCatechismTrack {
    @Attribute(.unique) var catechismId: String
    var currentQuestion: Int
    var startedAtQuestion: Int
    var startedAt: Date
    var updatedAt: Date
    fileprivate var milestonesData: Data

    init(catechismId: String, currentQuestion: Int, startedAtQuestion: Int,
         startedAt: Date, updatedAt: Date, milestonesData: Data) {
        self.catechismId = catechismId
        self.currentQuestion = currentQuestion
        self.startedAtQuestion = startedAtQuestion
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.milestonesData = milestonesData
    }
}

@Model
public final class LocalChild {
    @Attribute(.unique) public private(set) var id: UUID
    public fileprivate(set) var name: String
    public private(set) var age: Int?
    public private(set) var createdAt: Date
    public fileprivate(set) var updatedAt: Date
    fileprivate var activeCatechismId: String?

    init(name: String, age: Int? = nil) {
        self.id = UUID()
        self.name = name
        self.age = age
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }
}

@Model
public final class ChildCatechismTrack {
    @Attribute(.unique) private var childCatechismKey: String
    public private(set) var childId: UUID
    public private(set) var catechismId: String
    public var currentQuestion: Int
    public var startedAtQuestion: Int
    public var startedAt: Date
    public var updatedAt: Date
    fileprivate var milestonesData: Data

    public var milestones: [String: MilestoneRecord] {
        get { (try? JSONDecoder().decode([String: MilestoneRecord].self, from: milestonesData)) ?? [:] }
        set { milestonesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    public init(
        childId: UUID,
        catechismId: String,
        currentQuestion: Int,
        startedAtQuestion: Int,
        startedAt: Date,
        updatedAt: Date,
        milestones: [String: MilestoneRecord] = [:]
    ) {
        self.childCatechismKey = childId.uuidString + ":" + catechismId
        self.childId = childId
        self.catechismId = catechismId
        self.currentQuestion = currentQuestion
        self.startedAtQuestion = startedAtQuestion
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.milestonesData = (try? JSONEncoder().encode(milestones)) ?? Data()
    }
}

// activeCatechismId is retained for stores written before child profiles.
@Model
public final class ProgressSettings {
    var activeCatechismId: String?
    public fileprivate(set) var activeChildId: UUID?
    fileprivate var didInitializeChildren: Bool?
    init() {}
}

// The App Group both the app and the widget extension share so they can see
// the same SwiftData store across process boundaries. Registered as a real
// capability (Signing & Capabilities > App Groups) for both targets — see
// ios/App/Sources/ConfessionalChristianity.entitlements and
// ios/App/Widget/ConfessionalChristianityWidgetExtension.entitlements.
public let sharedAppGroupID = "group.com.confessionalchristianity.app"

// The sync engine's outbox and cursors (Sync.swift) live in this same store,
// so a queued change and the row it describes are saved together.
//
// TKL-856 dropped SeriesProgressRecord and ReadingPlanProgressRecord (devotion
// and reading-plan progress), which shipped in the App Store 1.0 store. The
// migration is SwiftData's automatic lightweight one: opening an older store
// with this schema drops the two tables and keeps everything else. That works
// whichever older shape a device has (1.0 had no sync tables), where an
// explicit VersionedSchema plan would have to match each shape exactly.
// ProgressSchemaTests opens both shapes. Core Data logs "Persistent History
// has to be truncated" once on that upgrade; nothing here reads history.
public let progressSchema = Schema([
    LocalCatechismTrack.self, ProgressSettings.self, LocalChild.self, ChildCatechismTrack.self,
] + syncModelTypes)

/// The single ModelContainer both the app and the widget extension build
/// from — same App Group file, so a session's progress the app just wrote is
/// visible to the widget's next timeline refresh with no sync step. Crashes
/// loudly on failure (matching SwiftData's own default `.modelContainer`
/// behavior) since there's no reasonable way to run either target without it.
@MainActor
public func makeSharedModelContainer() -> ModelContainer {
    guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: sharedAppGroupID) else {
        fatalError("DomainKit: App Group '\(sharedAppGroupID)' container unavailable — check the App Groups capability/entitlements.")
    }
    do {
        return try openProgressContainer(at: groupURL.appending(path: "Progress.sqlite"))
    } catch {
        fatalError("DomainKit: failed to open shared ModelContainer: \(error)")
    }
}

// The app and widget can both be the first process to open the upgraded store.
@MainActor
func openProgressContainer(at url: URL) throws -> ModelContainer {
    let lock = open(url.appendingPathExtension("lock").path, O_CREAT | O_RDWR, 0o600)
    guard lock >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    defer { close(lock) }
    while flock(lock, LOCK_EX) != 0 {
        if errno != EINTR { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    let config = ModelConfiguration(schema: progressSchema, url: url)
    let container = try ModelContainer(for: progressSchema, configurations: [config])
    let context = ModelContext(container)
    let priorSettings = try context.fetch(FetchDescriptor<ProgressSettings>()).first
    if priorSettings?.didInitializeChildren != true {
        let legacyTracks = try context.fetch(FetchDescriptor<LocalCatechismTrack>())
        let settings = priorSettings ?? ProgressSettings()
        if priorSettings == nil { context.insert(settings) }
        let child = LocalChild(name: "My child")
        context.insert(child)
        child.activeCatechismId = settings.activeCatechismId
        settings.activeCatechismId = nil
        settings.activeChildId = child.id
        settings.didInitializeChildren = true

        for legacy in legacyTracks {
            let track = ChildCatechismTrack(
                childId: child.id, catechismId: legacy.catechismId,
                currentQuestion: legacy.currentQuestion, startedAtQuestion: legacy.startedAtQuestion,
                startedAt: legacy.startedAt, updatedAt: legacy.updatedAt
            )
            track.milestonesData = legacy.milestonesData
            context.insert(track)
            context.delete(legacy)
        }
        try context.save()
    }
    return container
}

// Ported from src/lib/localCatechismProgress.ts + src/hooks/useSessionTrack.ts:
// same "resume existing track, else start fresh at Q1" semantics, same
// milestone-on-advance bookkeeping. Tracks are keyed by the catechism's
// contentId (e.g. "WSC"), matching program.contentId — not the program slug.
@MainActor
public final class LocalProgressStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public var activeChildId: UUID? {
        (try? context.fetch(FetchDescriptor<ProgressSettings>()).first)?.activeChildId
    }

    private func settings() throws -> ProgressSettings {
        if let existing = try context.fetch(FetchDescriptor<ProgressSettings>()).first {
            return existing
        }
        let created = ProgressSettings()
        context.insert(created)
        return created
    }

    private func child(for childId: UUID) throws -> LocalChild? {
        let predicate = #Predicate<LocalChild> { $0.id == childId }
        return try context.fetch(FetchDescriptor(predicate: predicate)).first
    }

    @discardableResult
    public func addChild(name: String, age: Int? = nil) throws -> LocalChild {
        let settings = try settings()
        let child = LocalChild(name: name, age: age)
        context.insert(child)
        if settings.activeChildId == nil { settings.activeChildId = child.id }
        try commitChanges()
        return child
    }

    public func renameChild(childId: UUID, name: String) throws {
        guard let child = try child(for: childId) else { return }
        child.name = name
        child.updatedAt = Date()
        try commitChanges()
    }

    public func selectChild(childId: UUID) throws {
        guard try child(for: childId) != nil else { return }
        try settings().activeChildId = childId
        try commitChanges()
    }

    public func deleteChild(childId: UUID) throws {
        guard let child = try child(for: childId) else { return }
        let childTracks = try context.fetch(tracks(for: childId))
        let settings = try settings()
        if settings.activeChildId == childId {
            let others = try context.fetch(FetchDescriptor<LocalChild>(sortBy: [SortDescriptor(\.createdAt)]))
            settings.activeChildId = others.first(where: { $0.id != childId })?.id
        }
        for track in childTracks { context.delete(track) }
        context.delete(child)
        try commitChanges()
    }

    private func tracks(for childId: UUID) -> FetchDescriptor<ChildCatechismTrack> {
        FetchDescriptor(predicate: #Predicate { $0.childId == childId })
    }

    private func track(childId: UUID, catechismId: String) throws -> ChildCatechismTrack? {
        let predicate = #Predicate<ChildCatechismTrack> {
            $0.childId == childId && $0.catechismId == catechismId
        }
        return try context.fetch(FetchDescriptor(predicate: predicate)).first
    }

    /// The selected child's last catechism, falling back to their latest track.
    public func activeTrack(childId: UUID) -> ChildCatechismTrack? {
        guard let child = try? child(for: childId) else { return nil }
        let all = (try? context.fetch(tracks(for: childId))) ?? []
        if let activeId = child.activeCatechismId, let match = all.first(where: { $0.catechismId == activeId }) {
            return match
        }
        return all.max { $0.updatedAt < $1.updatedAt }
    }

    private func commitChanges() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    // SwiftData's autosave only flushes to disk on its own schedule (scene
    // deactivation, memory pressure, etc.), which is fine within a single
    // process but not for the widget extension — a separate process that
    // reads Progress.sqlite fresh on every timeline request. Saving
    // explicitly after every mutation is what makes "answer a question in
    // the app" show up in the widget on its next refresh instead of
    // whenever autosave next happens to run.
    private func saveTrack(_ track: ChildCatechismTrack, for child: LocalChild) -> ChildCatechismTrack? {
        child.activeCatechismId = track.catechismId
        do {
            try commitChanges()
            return track
        } catch {
            return nil
        }
    }

    /// Resumes the existing track for this catechism, or starts a fresh one at question 1.
    @discardableResult
    public func resumeOrStartTrack(childId: UUID, catechismId: String) -> ChildCatechismTrack? {
        guard let child = try? child(for: childId) else { return nil }
        do {
            if let existing = try track(childId: childId, catechismId: catechismId) {
                return saveTrack(existing, for: child)
            }
            return createTrack(for: child, catechismId: catechismId, startingQuestion: 1)
        } catch {
            return nil
        }
    }

    /// Starts at `startingQuestion`, clearing existing milestones for this child's catechism.
    @discardableResult
    public func startTrack(childId: UUID, catechismId: String, startingQuestion: Int) -> ChildCatechismTrack? {
        guard let child = try? child(for: childId) else { return nil }
        do {
            guard let existing = try track(childId: childId, catechismId: catechismId) else {
                return createTrack(for: child, catechismId: catechismId, startingQuestion: startingQuestion)
            }
            let now = Date()
            existing.currentQuestion = startingQuestion
            existing.startedAtQuestion = startingQuestion
            existing.startedAt = now
            existing.updatedAt = now
            existing.milestones = [:]
            return saveTrack(existing, for: child)
        } catch {
            return nil
        }
    }

    private func createTrack(for child: LocalChild, catechismId: String, startingQuestion: Int) -> ChildCatechismTrack? {
        let now = Date()
        let created = ChildCatechismTrack(
            childId: child.id, catechismId: catechismId, currentQuestion: startingQuestion,
            startedAtQuestion: startingQuestion, startedAt: now, updatedAt: now
        )
        context.insert(created)
        return saveTrack(created, for: child)
    }

    // The "Next Question" primitive: the current question enters the record
    // as introduced and the position advances, clamped one past the end so a
    // finished track reads as complete.
    @discardableResult
    public func advanceQuestion(childId: UUID, catechismId: String, totalQuestions: Int) -> ChildCatechismTrack? {
        guard let child = try? child(for: childId),
              let existing = try? track(childId: childId, catechismId: catechismId) else { return nil }
        let now = Date()
        let key = String(existing.currentQuestion)
        if existing.currentQuestion <= totalQuestions, existing.milestones[key] == nil {
            var milestones = existing.milestones
            milestones[key] = MilestoneRecord(state: "introduced", introducedAt: now, reviewCount: 0)
            existing.milestones = milestones
        }
        existing.currentQuestion = min(totalQuestions + 1, existing.currentQuestion + 1)
        existing.updatedAt = now
        return saveTrack(existing, for: child)
    }

    // Jumping to an arbitrary question repositions the track without
    // touching milestones — it's browsing, not re-introducing material.
    @discardableResult
    public func jumpToQuestion(childId: UUID, catechismId: String, questionNumber: Int, totalQuestions: Int) -> ChildCatechismTrack? {
        guard let child = try? child(for: childId),
              let existing = try? track(childId: childId, catechismId: catechismId) else { return nil }
        existing.currentQuestion = min(totalQuestions, max(1, questionNumber))
        existing.updatedAt = Date()
        return saveTrack(existing, for: child)
    }
}
