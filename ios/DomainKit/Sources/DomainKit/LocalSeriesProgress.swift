// Ported from src/lib/localSeriesProgress.ts. The persistence itself
// (SwiftData) lives app-side, same split as LocalCatechismTrack/
// LocalProgressStore; this is the one pure function the domain layer owns.
import Foundation

/// The part Continue should jump to: the first of the series' days without a
/// completion. A suggestion, not a gate — every authored part stays reachable
/// regardless of this value. Nil once every part is complete.
public func currentPartDay(_ completedDays: [Int], totalParts: Int) -> Int? {
    let done = Set(completedDays)
    for day in 1...max(totalParts, 1) where day <= totalParts {
        if !done.contains(day) { return day }
    }
    return nil
}
