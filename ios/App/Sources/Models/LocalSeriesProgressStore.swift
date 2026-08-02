// Ported from src/lib/localSeriesProgress.ts: which parts of each devotion
// series this device has finished. Its own store beside LocalProgressStore,
// same as those two sit beside each other on web. Only completions are
// stored; the current part is derived at read time via DomainKit's
// currentPartDay.
import Foundation
import SwiftData

@MainActor
final class LocalSeriesProgressStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    private func record(for seriesSlug: String) -> SeriesProgressRecord? {
        let predicate = #Predicate<SeriesProgressRecord> { $0.seriesSlug == seriesSlug }
        return try? context.fetch(FetchDescriptor(predicate: predicate)).first
    }

    func getCompletedDays(_ seriesSlug: String) -> [Int] {
        record(for: seriesSlug)?.completedDays ?? []
    }

    /// Idempotent, like recordWorshipCompletion — replaying a finished part
    /// changes nothing, and progress never regresses.
    func recordCompletion(seriesSlug: String, day: Int) {
        if let existing = record(for: seriesSlug) {
            guard !existing.completedDays.contains(day) else { return }
            existing.completedDays.append(day)
            return
        }
        context.insert(SeriesProgressRecord(seriesSlug: seriesSlug, completedDays: [day]))
    }
}
