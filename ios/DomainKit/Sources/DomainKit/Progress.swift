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

    /// Progression rank for union merges: introduced < reviewing < mastered.
    public var stateRank: Int {
        switch state {
        case "introduced": 1
        case "reviewing": 2
        case "mastered": 3
        default: 0
        }
    }

    /// Union merge of two live milestones for the same question: the more
    /// advanced state wins (`mastered` > `reviewing` > `introduced`); equal
    /// states keep the higher review count (and newer write on tie);
    /// `introducedAt` keeps the earlier introduction instant.
    public static func merged(
        local: MilestoneRecord,
        remote: MilestoneRecord,
        localUpdatedAt: Date,
        remoteUpdatedAt: Date
    ) -> MilestoneRecord {
        let winningState: String
        if local.stateRank != remote.stateRank {
            winningState = local.stateRank > remote.stateRank ? local.state : remote.state
        } else if local.reviewCount != remote.reviewCount {
            winningState = local.reviewCount > remote.reviewCount ? local.state : remote.state
        } else {
            winningState = remoteUpdatedAt > localUpdatedAt ? remote.state : local.state
        }
        return MilestoneRecord(
            state: winningState,
            introducedAt: min(local.introducedAt, remote.introducedAt),
            reviewCount: max(local.reviewCount, remote.reviewCount)
        )
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
    internal var activeCatechismId: String?

    init(name: String, age: Int? = nil, now: Date = Date()) {
        self.id = UUID()
        self.name = name
        self.age = age
        let stamped = SyncTimestamp.truncate(now)
        self.createdAt = stamped
        self.updatedAt = stamped
    }

    init(id: UUID, name: String, age: Int?, createdAt: Date, updatedAt: Date, activeCatechismId: String?) {
        self.id = id
        self.name = name
        self.age = age
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.activeCatechismId = activeCatechismId
    }

    func applySynced(name: String, age: Int?, createdAt: Date, updatedAt: Date, activeCatechismId: String?) {
        self.name = name
        self.age = age
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.activeCatechismId = activeCatechismId
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
    public internal(set) var activeChildId: UUID?
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
    LordsDayNote.self, NoteCard.self,
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
        settings.didInitializeChildren = true
        // Only progress that already exists needs a child to hold it. A new
        // store stays childless so a new guest sees Today's empty state (TKL-825).
        if !legacyTracks.isEmpty {
            let child = LocalChild(name: "My child")
            context.insert(child)
            child.activeCatechismId = settings.activeCatechismId
            settings.activeChildId = child.id
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
        }
        settings.activeCatechismId = nil
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
    let context: ModelContext
    /// When signed in, local writes atomically enqueue outbox entries for this Cognito subject.
    /// When nil (guest), writes stay strictly local and nothing is queued for sync.
    let syncSubject: String?
    let onLocalWrite: (@MainActor () -> Void)?

    public init(context: ModelContext, syncSubject: String? = nil, onLocalWrite: (@MainActor () -> Void)? = nil) {
        self.context = context
        self.syncSubject = syncSubject
        self.onLocalWrite = onLocalWrite
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
    public func addChild(name: String, age: Int? = nil, now: Date = Date()) throws -> LocalChild {
        let settings = try settings()
        let stamped = SyncTimestamp.truncate(now)
        let child = LocalChild(name: name, age: age, now: stamped)
        context.insert(child)
        if settings.activeChildId == nil { settings.activeChildId = child.id }
        try enqueueChildUpsert(child, updatedAt: stamped)
        try commitChanges(didSyncWrite: syncSubject != nil)
        return child
    }

    public func renameChild(childId: UUID, name: String, now: Date = Date()) throws {
        guard let child = try child(for: childId) else { return }
        let stamped = SyncTimestamp.truncate(now)
        child.name = name
        child.updatedAt = stamped
        try enqueueChildUpsert(child, updatedAt: stamped)
        try commitChanges(didSyncWrite: syncSubject != nil)
    }

    private enum SelectionError: Error {
        case childNotFound
    }

    public func selectChild(childId: UUID) throws {
        guard try child(for: childId) != nil else { throw SelectionError.childNotFound }
        try settings().activeChildId = childId
        try commitChanges(didSyncWrite: false)
    }

    public func deleteChild(childId: UUID, now: Date = Date()) throws {
        guard let child = try child(for: childId) else { return }
        let stamped = SyncTimestamp.truncate(now)
        let childTracks = try context.fetch(tracks(for: childId))
        let settings = try settings()
        if settings.activeChildId == childId {
            let others = try context.fetch(FetchDescriptor<LocalChild>(sortBy: [SortDescriptor(\.createdAt)]))
            settings.activeChildId = others.first(where: { $0.id != childId })?.id
        }
        try enqueueChildDeletionTombstones(child: child, tracks: childTracks, deletedAt: stamped)
        for track in childTracks { context.delete(track) }
        context.delete(child)
        try commitChanges(didSyncWrite: syncSubject != nil)
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

    private func commitChanges(didSyncWrite: Bool) throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        if didSyncWrite {
            onLocalWrite?()
        }
    }

    // SwiftData's autosave only flushes to disk on its own schedule (scene
    // deactivation, memory pressure, etc.), which is fine within a single
    // process but not for the widget extension — a separate process that
    // reads Progress.sqlite fresh on every timeline request. Saving
    // explicitly after every mutation is what makes "answer a question in
    // the app" show up in the widget on its next refresh instead of
    // whenever autosave next happens to run.
    private func saveTrack(
        _ track: ChildCatechismTrack,
        for child: LocalChild,
        updatedAt: Date,
        enqueueSync: (() throws -> Void)? = nil
    ) -> ChildCatechismTrack? {
        let activeChanged = child.activeCatechismId != track.catechismId
        child.activeCatechismId = track.catechismId
        if activeChanged {
            child.updatedAt = max(child.updatedAt, updatedAt)
        }
        do {
            if activeChanged {
                try enqueueChildUpsert(child, updatedAt: child.updatedAt)
            }
            try enqueueSync?()
            try commitChanges(didSyncWrite: syncSubject != nil)
            return track
        } catch {
            return nil
        }
    }

    /// Resumes the existing track for this catechism, or starts a fresh one at question 1.
    @discardableResult
    public func resumeOrStartTrack(childId: UUID, catechismId: String, now: Date = Date()) -> ChildCatechismTrack? {
        guard let child = try? child(for: childId) else { return nil }
        let stamped = SyncTimestamp.truncate(now)
        do {
            if let existing = try track(childId: childId, catechismId: catechismId) {
                return saveTrack(existing, for: child, updatedAt: stamped)
            }
            return createTrack(for: child, catechismId: catechismId, startingQuestion: 1, now: stamped)
        } catch {
            return nil
        }
    }

    /// Starts at `startingQuestion`, clearing existing milestones for this child's catechism.
    @discardableResult
    public func startTrack(childId: UUID, catechismId: String, startingQuestion: Int, now: Date = Date()) -> ChildCatechismTrack? {
        guard let child = try? child(for: childId) else { return nil }
        let stamped = SyncTimestamp.truncate(now)
        do {
            guard let existing = try track(childId: childId, catechismId: catechismId) else {
                return createTrack(for: child, catechismId: catechismId, startingQuestion: startingQuestion, now: stamped)
            }
            let clearedQuestions = existing.milestones.keys.compactMap(Int.init).sorted()
            existing.currentQuestion = startingQuestion
            existing.startedAtQuestion = startingQuestion
            existing.startedAt = stamped
            existing.updatedAt = stamped
            existing.milestones = [:]
            return saveTrack(existing, for: child, updatedAt: stamped) {
                for question in clearedQuestions {
                    try self.enqueueMilestoneTombstone(
                        childId: child.id, catechismId: catechismId, question: question, deletedAt: stamped
                    )
                }
                try self.enqueueAssignmentUpsert(existing, updatedAt: stamped)
                try self.enqueuePacingUpsert(existing, updatedAt: stamped)
            }
        } catch {
            return nil
        }
    }

    private func createTrack(for child: LocalChild, catechismId: String, startingQuestion: Int, now: Date) -> ChildCatechismTrack? {
        let created = ChildCatechismTrack(
            childId: child.id, catechismId: catechismId, currentQuestion: startingQuestion,
            startedAtQuestion: startingQuestion, startedAt: now, updatedAt: now
        )
        context.insert(created)
        return saveTrack(created, for: child, updatedAt: now) {
            try self.enqueueAssignmentUpsert(created, updatedAt: now)
            try self.enqueuePacingUpsert(created, updatedAt: now)
        }
    }

    // The "Next Question" primitive: the current question enters the record
    // as introduced and the position advances, clamped one past the end so a
    // finished track reads as complete.
    @discardableResult
    public func advanceQuestion(childId: UUID, catechismId: String, totalQuestions: Int, now: Date = Date()) -> ChildCatechismTrack? {
        guard let child = try? child(for: childId),
              let existing = try? track(childId: childId, catechismId: catechismId) else { return nil }
        let stamped = SyncTimestamp.truncate(now)
        let questionNum = existing.currentQuestion
        let key = String(questionNum)
        var addedMilestone: (Int, MilestoneRecord)?
        if questionNum <= totalQuestions, existing.milestones[key] == nil {
            let record = MilestoneRecord(state: "introduced", introducedAt: stamped, reviewCount: 0)
            var milestones = existing.milestones
            milestones[key] = record
            existing.milestones = milestones
            addedMilestone = (questionNum, record)
        }
        existing.currentQuestion = min(totalQuestions + 1, existing.currentQuestion + 1)
        existing.updatedAt = stamped
        return saveTrack(existing, for: child, updatedAt: stamped) {
            try self.enqueuePacingUpsert(existing, updatedAt: stamped)
            if let (q, milestone) = addedMilestone {
                try self.enqueueMilestoneUpsert(
                    childId: child.id, catechismId: catechismId, question: q, milestone: milestone, updatedAt: stamped
                )
            }
        }
    }

    // Jumping to an arbitrary question repositions the track without
    // touching milestones — it's browsing, not re-introducing material.
    @discardableResult
    public func jumpToQuestion(
        childId: UUID, catechismId: String, questionNumber: Int, totalQuestions: Int, now: Date = Date()
    ) -> ChildCatechismTrack? {
        guard let child = try? child(for: childId),
              let existing = try? track(childId: childId, catechismId: catechismId) else { return nil }
        let stamped = SyncTimestamp.truncate(now)
        existing.currentQuestion = min(totalQuestions, max(1, questionNumber))
        existing.updatedAt = stamped
        return saveTrack(existing, for: child, updatedAt: stamped) {
            try self.enqueuePacingUpsert(existing, updatedAt: stamped)
        }
    }

    /// Updates (or creates) a single question milestone and queues its sync row.
    @discardableResult
    public func updateMilestone(
        childId: UUID,
        catechismId: String,
        question: Int,
        state: String,
        introducedAt: Date? = nil,
        reviewCount: Int,
        now: Date = Date()
    ) -> ChildCatechismTrack? {
        guard let child = try? child(for: childId),
              let existing = try? track(childId: childId, catechismId: catechismId) else { return nil }
        let stamped = SyncTimestamp.truncate(now)
        let key = String(question)
        let intro = SyncTimestamp.truncate(introducedAt ?? existing.milestones[key]?.introducedAt ?? stamped)
        let updated = MilestoneRecord(state: state, introducedAt: intro, reviewCount: reviewCount)
        var milestones = existing.milestones
        milestones[key] = updated
        existing.milestones = milestones
        existing.updatedAt = max(existing.updatedAt, stamped)
        return saveTrack(existing, for: child, updatedAt: stamped) {
            try self.enqueueMilestoneUpsert(
                childId: child.id, catechismId: catechismId, question: question, milestone: updated, updatedAt: stamped
            )
        }
    }

    // MARK: Sync outbox helpers

    private func enqueueChildUpsert(_ child: LocalChild, updatedAt: Date) throws {
        guard let subject = syncSubject else { return }
        let cid = child.id.uuidString.lowercased()
        let payload = try JSONEncoder().encode(ChildSyncPayload(
            name: child.name,
            age: child.age,
            created_at: SyncTimestamp.format(child.createdAt),
            active_catechism_id: child.activeCatechismId
        ))
        try SyncMetaStore.upsert(
            table: SyncTable.children, rowId: cid, childId: cid, naturalKey: cid,
            updatedAt: updatedAt, in: context
        )
        try SyncMetaStore.enqueueOutbox(
            subject: subject, table: SyncTable.children, rowId: cid, childId: cid,
            payload: payload, updatedAt: updatedAt, in: context
        )
    }

    private func enqueueAssignmentUpsert(_ track: ChildCatechismTrack, updatedAt: Date) throws {
        guard let subject = syncSubject else { return }
        let cid = track.childId.uuidString.lowercased()
        let slug = SyncTable.catechismSlug(forContentId: track.catechismId)
        let naturalKey = SyncTable.assignmentNaturalKey(childId: track.childId, catechismId: track.catechismId)
        let rowId = try SyncMetaStore.resolvedRowId(
            table: SyncTable.catechismAssignments, naturalKey: naturalKey, in: context
        )
        let payload = try JSONEncoder().encode(CatechismAssignmentSyncPayload(
            catechism_slug: slug,
            started_at: SyncTimestamp.format(track.startedAt),
            started_at_question: track.startedAtQuestion
        ))
        try SyncMetaStore.upsert(
            table: SyncTable.catechismAssignments, rowId: rowId, childId: cid, naturalKey: naturalKey,
            updatedAt: updatedAt, in: context
        )
        try SyncMetaStore.enqueueOutbox(
            subject: subject, table: SyncTable.catechismAssignments, rowId: rowId, childId: cid,
            payload: payload, updatedAt: updatedAt, in: context
        )
    }

    private func enqueuePacingUpsert(_ track: ChildCatechismTrack, updatedAt: Date) throws {
        guard let subject = syncSubject else { return }
        let cid = track.childId.uuidString.lowercased()
        let slug = SyncTable.catechismSlug(forContentId: track.catechismId)
        let naturalKey = SyncTable.pacingNaturalKey(childId: track.childId, catechismId: track.catechismId)
        let rowId = try SyncMetaStore.resolvedRowId(
            table: SyncTable.catechismPacing, naturalKey: naturalKey, in: context
        )
        let payload = try JSONEncoder().encode(CatechismPacingSyncPayload(
            catechism_slug: slug,
            current_question: track.currentQuestion
        ))
        try SyncMetaStore.upsert(
            table: SyncTable.catechismPacing, rowId: rowId, childId: cid, naturalKey: naturalKey,
            updatedAt: updatedAt, in: context
        )
        try SyncMetaStore.enqueueOutbox(
            subject: subject, table: SyncTable.catechismPacing, rowId: rowId, childId: cid,
            payload: payload, updatedAt: updatedAt, in: context
        )
    }

    private func enqueueMilestoneUpsert(
        childId: UUID, catechismId: String, question: Int, milestone: MilestoneRecord, updatedAt: Date
    ) throws {
        guard let subject = syncSubject else { return }
        let cid = childId.uuidString.lowercased()
        let slug = SyncTable.catechismSlug(forContentId: catechismId)
        let naturalKey = SyncTable.milestoneNaturalKey(childId: childId, catechismId: catechismId, question: question)
        let rowId = try SyncMetaStore.resolvedRowId(
            table: SyncTable.catechismMilestones, naturalKey: naturalKey, in: context
        )
        let payload = try JSONEncoder().encode(CatechismMilestoneSyncPayload(
            catechism_slug: slug,
            question: question,
            state: milestone.state,
            introduced_at: SyncTimestamp.format(milestone.introducedAt),
            review_count: milestone.reviewCount
        ))
        try SyncMetaStore.upsert(
            table: SyncTable.catechismMilestones, rowId: rowId, childId: cid, naturalKey: naturalKey,
            updatedAt: updatedAt, in: context
        )
        try SyncMetaStore.enqueueOutbox(
            subject: subject, table: SyncTable.catechismMilestones, rowId: rowId, childId: cid,
            payload: payload, updatedAt: updatedAt, in: context
        )
    }

    private func enqueueMilestoneTombstone(
        childId: UUID, catechismId: String, question: Int, deletedAt: Date
    ) throws {
        guard let subject = syncSubject else { return }
        let cid = childId.uuidString.lowercased()
        let naturalKey = SyncTable.milestoneNaturalKey(childId: childId, catechismId: catechismId, question: question)
        let rowId = try SyncMetaStore.resolvedRowId(
            table: SyncTable.catechismMilestones, naturalKey: naturalKey, in: context
        )
        if let meta = try SyncMetaStore.meta(table: SyncTable.catechismMilestones, rowId: rowId, in: context) {
            context.delete(meta)
        }
        try SyncMetaStore.enqueueOutbox(
            subject: subject, table: SyncTable.catechismMilestones, rowId: rowId, childId: cid,
            payload: nil, updatedAt: deletedAt, deletedAt: deletedAt, in: context
        )
    }

    private func enqueueChildDeletionTombstones(
        child: LocalChild, tracks: [ChildCatechismTrack], deletedAt: Date
    ) throws {
        guard let subject = syncSubject else { return }
        let cid = child.id.uuidString.lowercased()
        // The profile goes first: the server refuses a co-guardian's profile tombstone and then
        // every progress tombstone with the same deletedAt, so a shared child's progress survives
        // a removal only its owner may make (TKL-1116).
        try SyncMetaStore.enqueueOutbox(
            subject: subject, table: SyncTable.children, rowId: cid, childId: cid,
            payload: nil, updatedAt: deletedAt, deletedAt: deletedAt, in: context
        )
        var tombstoned = Set<String>()
        for track in tracks {
            for key in track.milestones.keys.compactMap(Int.init).sorted() {
                let nat = SyncTable.milestoneNaturalKey(childId: child.id, catechismId: track.catechismId, question: key)
                let rowId = try SyncMetaStore.resolvedRowId(
                    table: SyncTable.catechismMilestones, naturalKey: nat, in: context
                )
                tombstoned.insert("\(SyncTable.catechismMilestones):\(rowId)")
                try SyncMetaStore.enqueueOutbox(
                    subject: subject, table: SyncTable.catechismMilestones, rowId: rowId, childId: cid,
                    payload: nil, updatedAt: deletedAt, deletedAt: deletedAt, in: context
                )
            }
            let pacingNat = SyncTable.pacingNaturalKey(childId: child.id, catechismId: track.catechismId)
            let pacingId = try SyncMetaStore.resolvedRowId(
                table: SyncTable.catechismPacing, naturalKey: pacingNat, in: context
            )
            tombstoned.insert("\(SyncTable.catechismPacing):\(pacingId)")
            try SyncMetaStore.enqueueOutbox(
                subject: subject, table: SyncTable.catechismPacing, rowId: pacingId, childId: cid,
                payload: nil, updatedAt: deletedAt, deletedAt: deletedAt, in: context
            )

            let assignNat = SyncTable.assignmentNaturalKey(childId: child.id, catechismId: track.catechismId)
            let assignId = try SyncMetaStore.resolvedRowId(
                table: SyncTable.catechismAssignments, naturalKey: assignNat, in: context
            )
            tombstoned.insert("\(SyncTable.catechismAssignments):\(assignId)")
            try SyncMetaStore.enqueueOutbox(
                subject: subject, table: SyncTable.catechismAssignments, rowId: assignId, childId: cid,
                payload: nil, updatedAt: deletedAt, deletedAt: deletedAt, in: context
            )
        }
        // Any remaining persisted meta rows for this child (e.g. pulled rows).
        for meta in try SyncMetaStore.allMeta(forChildId: child.id, in: context) {
            if meta.table != SyncTable.children, !tombstoned.contains(meta.lookupKey) {
                try SyncMetaStore.enqueueOutbox(
                    subject: subject, table: meta.table, rowId: meta.rowId, childId: cid,
                    payload: nil, updatedAt: deletedAt, deletedAt: deletedAt, in: context
                )
            }
            context.delete(meta)
        }
    }
}
