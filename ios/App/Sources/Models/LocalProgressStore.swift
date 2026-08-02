// Ported from src/lib/localCatechismProgress.ts + src/hooks/useSessionTrack.ts:
// same "resume existing track, else start fresh at Q1" semantics, same
// milestone-on-advance bookkeeping. Tracks are keyed by the catechism's
// contentId (e.g. "WSC"), matching program.contentId — not the program slug.
import Foundation
import SwiftData

@MainActor
final class LocalProgressStore {
    private let context: ModelContext

    init(context: ModelContext) {
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
    func activeTrack() -> LocalCatechismTrack? {
        let all = (try? context.fetch(FetchDescriptor<LocalCatechismTrack>())) ?? []
        if let activeId = settings().activeCatechismId, let match = all.first(where: { $0.catechismId == activeId }) {
            return match
        }
        return all.max { $0.updatedAt < $1.updatedAt }
    }

    /// Resumes the existing track for this catechism, or starts a fresh one
    /// at question 1 — the same fallback `useSessionTrack` applies with no
    /// `?start=` param.
    @discardableResult
    func resumeOrStartTrack(catechismId: String) -> LocalCatechismTrack {
        if let existing = track(for: catechismId) {
            settings().activeCatechismId = catechismId
            return existing
        }
        return startTrack(catechismId: catechismId, startingQuestion: 1)
    }

    /// Always (re)starts the track at `startingQuestion`, clearing milestones —
    /// mirrors startLocalCatechismTrack's overwrite semantics verbatim.
    @discardableResult
    func startTrack(catechismId: String, startingQuestion: Int) -> LocalCatechismTrack {
        let now = Date()
        if let existing = track(for: catechismId) {
            existing.currentQuestion = startingQuestion
            existing.startedAtQuestion = startingQuestion
            existing.startedAt = now
            existing.updatedAt = now
            existing.milestones = [:]
            settings().activeCatechismId = catechismId
            return existing
        }
        let created = LocalCatechismTrack(
            catechismId: catechismId, currentQuestion: startingQuestion,
            startedAtQuestion: startingQuestion, startedAt: now, updatedAt: now
        )
        context.insert(created)
        settings().activeCatechismId = catechismId
        return created
    }

    // The "Next Question" primitive: the current question enters the record
    // as introduced and the position advances, clamped one past the end so a
    // finished track reads as complete.
    @discardableResult
    func advanceQuestion(catechismId: String, totalQuestions: Int) -> LocalCatechismTrack? {
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
        return existing
    }

    // Jumping to an arbitrary question repositions the track without
    // touching milestones — it's browsing, not re-introducing material.
    @discardableResult
    func jumpToQuestion(catechismId: String, questionNumber: Int, totalQuestions: Int) -> LocalCatechismTrack? {
        guard let existing = track(for: catechismId) else { return nil }
        existing.currentQuestion = min(totalQuestions, max(1, questionNumber))
        existing.updatedAt = Date()
        settings().activeCatechismId = catechismId
        return existing
    }
}
