// Local, guest-only progress persistence — SwiftData port of
// src/lib/localCatechismProgress.ts and src/lib/localSeriesProgress.ts. No
// account, no name capture, same as the web app: this is the only progress
// store the app has in v1.
//
// Lives in DomainKit (not the App target) so the Home Screen widget
// extension — a separate process — can read the exact same models and
// resolution logic as the app, both pointed at the same App Group container
// (see ConfessionalChristianityApp.swift's sharedModelContainer and the
// widget's own TimelineProvider).
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

@Model
public final class LocalCatechismTrack {
    @Attribute(.unique) public var catechismId: String
    public var currentQuestion: Int
    public var startedAtQuestion: Int
    public var startedAt: Date
    public var updatedAt: Date
    private var milestonesData: Data

    public var milestones: [String: MilestoneRecord] {
        get { (try? JSONDecoder().decode([String: MilestoneRecord].self, from: milestonesData)) ?? [:] }
        set { milestonesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    public init(
        catechismId: String,
        currentQuestion: Int,
        startedAtQuestion: Int,
        startedAt: Date,
        updatedAt: Date,
        milestones: [String: MilestoneRecord] = [:]
    ) {
        self.catechismId = catechismId
        self.currentQuestion = currentQuestion
        self.startedAtQuestion = startedAtQuestion
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.milestonesData = (try? JSONEncoder().encode(milestones)) ?? Data()
    }
}

// Mirrors the top-level `activeCatechismId` field of the localStorage blob.
@Model
public final class ProgressSettings {
    public var activeCatechismId: String?
    public init(activeCatechismId: String? = nil) {
        self.activeCatechismId = activeCatechismId
    }
}

// SwiftData port of src/lib/localSeriesProgress.ts's per-series completions
// record — one row per series slug, completed day numbers as they're
// finished (order preserved, though only membership is ever read back).
@Model
public final class SeriesProgressRecord {
    @Attribute(.unique) public var seriesSlug: String
    private var completedDaysData: Data

    public var completedDays: [Int] {
        get { (try? JSONDecoder().decode([Int].self, from: completedDaysData)) ?? [] }
        set { completedDaysData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    public init(seriesSlug: String, completedDays: [Int] = []) {
        self.seriesSlug = seriesSlug
        self.completedDaysData = (try? JSONEncoder().encode(completedDays)) ?? Data()
    }
}

// The App Group both the app and the widget extension share so they can see
// the same SwiftData store across process boundaries. Registered as a real
// capability (Signing & Capabilities > App Groups) for both targets — see
// ios/App/Sources/ConfessionalChristianity.entitlements and
// ios/App/Widget/ConfessionalChristianityWidgetExtension.entitlements.
public let sharedAppGroupID = "group.com.confessionalchristianity.app"

public let progressSchema = Schema([
    LocalCatechismTrack.self, ProgressSettings.self, SeriesProgressRecord.self,
])

/// The single ModelContainer both the app and the widget extension build
/// from — same App Group file, so a session's progress the app just wrote is
/// visible to the widget's next timeline refresh with no sync step. Crashes
/// loudly on failure (matching SwiftData's own default `.modelContainer`
/// behavior) since there's no reasonable way to run either target without it.
public func makeSharedModelContainer() -> ModelContainer {
    guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: sharedAppGroupID) else {
        fatalError("DomainKit: App Group '\(sharedAppGroupID)' container unavailable — check the App Groups capability/entitlements.")
    }
    let config = ModelConfiguration(schema: progressSchema, url: groupURL.appending(path: "Progress.sqlite"))
    do {
        return try ModelContainer(for: progressSchema, configurations: [config])
    } catch {
        fatalError("DomainKit: failed to open shared ModelContainer: \(error)")
    }
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

    private func settings() -> ProgressSettings {
        if let existing = try? context.fetch(FetchDescriptor<ProgressSettings>()).first {
            return existing
        }
        let created = ProgressSettings()
        context.insert(created)
        return created
    }

    private func track(for catechismId: String) -> LocalCatechismTrack? {
        let predicate = #Predicate<LocalCatechismTrack> { $0.catechismId == catechismId }
        return try? context.fetch(FetchDescriptor(predicate: predicate)).first
    }

    /// The track the visitor last worked in: the recorded active catechism
    /// when it still has a track, otherwise the most recently updated track —
    /// mirrors getActiveLocalCatechismTrack verbatim (covers stores written
    /// before activeCatechismId was kept in sync).
    public func activeTrack() -> LocalCatechismTrack? {
        let all = (try? context.fetch(FetchDescriptor<LocalCatechismTrack>())) ?? []
        if let activeId = settings().activeCatechismId, let match = all.first(where: { $0.catechismId == activeId }) {
            return match
        }
        return all.max { $0.updatedAt < $1.updatedAt }
    }

    // SwiftData's autosave only flushes to disk on its own schedule (scene
    // deactivation, memory pressure, etc.), which is fine within a single
    // process but not for the widget extension — a separate process that
    // reads Progress.sqlite fresh on every timeline request. Saving
    // explicitly after every mutation is what makes "answer a question in
    // the app" show up in the widget on its next refresh instead of
    // whenever autosave next happens to run.
    private func save() {
        try? context.save()
    }

    /// Resumes the existing track for this catechism, or starts a fresh one
    /// at question 1 — the same fallback `useSessionTrack` applies with no
    /// `?start=` param.
    @discardableResult
    public func resumeOrStartTrack(catechismId: String) -> LocalCatechismTrack {
        if let existing = track(for: catechismId) {
            settings().activeCatechismId = catechismId
            save()
            return existing
        }
        return startTrack(catechismId: catechismId, startingQuestion: 1)
    }

    /// Always (re)starts the track at `startingQuestion`, clearing milestones —
    /// mirrors startLocalCatechismTrack's overwrite semantics verbatim.
    @discardableResult
    public func startTrack(catechismId: String, startingQuestion: Int) -> LocalCatechismTrack {
        let now = Date()
        if let existing = track(for: catechismId) {
            existing.currentQuestion = startingQuestion
            existing.startedAtQuestion = startingQuestion
            existing.startedAt = now
            existing.updatedAt = now
            existing.milestones = [:]
            settings().activeCatechismId = catechismId
            save()
            return existing
        }
        let created = LocalCatechismTrack(
            catechismId: catechismId, currentQuestion: startingQuestion,
            startedAtQuestion: startingQuestion, startedAt: now, updatedAt: now
        )
        context.insert(created)
        settings().activeCatechismId = catechismId
        save()
        return created
    }

    // The "Next Question" primitive: the current question enters the record
    // as introduced and the position advances, clamped one past the end so a
    // finished track reads as complete.
    @discardableResult
    public func advanceQuestion(catechismId: String, totalQuestions: Int) -> LocalCatechismTrack? {
        guard let existing = track(for: catechismId) else { return nil }
        let now = Date()
        let key = String(existing.currentQuestion)
        if existing.currentQuestion <= totalQuestions, existing.milestones[key] == nil {
            var milestones = existing.milestones
            milestones[key] = MilestoneRecord(state: "introduced", introducedAt: now, reviewCount: 0)
            existing.milestones = milestones
        }
        existing.currentQuestion = min(totalQuestions + 1, existing.currentQuestion + 1)
        existing.updatedAt = now
        settings().activeCatechismId = catechismId
        save()
        return existing
    }

    // Jumping to an arbitrary question repositions the track without
    // touching milestones — it's browsing, not re-introducing material.
    @discardableResult
    public func jumpToQuestion(catechismId: String, questionNumber: Int, totalQuestions: Int) -> LocalCatechismTrack? {
        guard let existing = track(for: catechismId) else { return nil }
        existing.currentQuestion = min(totalQuestions, max(1, questionNumber))
        existing.updatedAt = Date()
        settings().activeCatechismId = catechismId
        save()
        return existing
    }
}

// Ported from src/lib/localSeriesProgress.ts: which parts of each devotion
// series this device has finished. Its own store beside LocalProgressStore,
// same as those two sit beside each other on web. Only completions are
// stored; the current part is derived at read time via DomainKit's
// currentPartDay.
@MainActor
public final class LocalSeriesProgressStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    private func record(for seriesSlug: String) -> SeriesProgressRecord? {
        let predicate = #Predicate<SeriesProgressRecord> { $0.seriesSlug == seriesSlug }
        return try? context.fetch(FetchDescriptor(predicate: predicate)).first
    }

    public func getCompletedDays(_ seriesSlug: String) -> [Int] {
        record(for: seriesSlug)?.completedDays ?? []
    }

    /// Idempotent, like recordWorshipCompletion — replaying a finished part
    /// changes nothing, and progress never regresses.
    public func recordCompletion(seriesSlug: String, day: Int) {
        if let existing = record(for: seriesSlug) {
            guard !existing.completedDays.contains(day) else { return }
            existing.completedDays.append(day)
            try? context.save()
            return
        }
        context.insert(SeriesProgressRecord(seriesSlug: seriesSlug, completedDays: [day]))
        try? context.save()
    }
}
