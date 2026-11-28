// The sample Lord's Day week for screenshots and UI tests (`-SeedSermonWeek YES`):
// last Sunday's Romans 8:28–30 notes with six kept cards. It replaces the retired
// week feed's fixture (TKL-1085 pass 3); the landing page, reel and journal read it
// from the app's own store like any kept sermon.
#if DEBUG
import Foundation
import SwiftData
import DomainKit

enum SampleSermonWeek {
    @MainActor @discardableResult
    static func seed(container: ModelContainer, today: Date = Date(), calendar: Calendar = .current) -> LordsDayNote {
        let store = LordsDayStore(context: container.mainContext)
        let note = LordsDayNote(serviceDate: lastSunday(onOrBefore: today, calendar: calendar),
                                passageRef: "Romans 8:28–30", preacher: "Rev. [your pastor]")
        try! store.save(note)
        try! store.appendCard(to: note, kind: .verse, body: "", verseRef: "Psalm 118:24")
        try! store.appendCard(to: note, kind: .keyPoint, body: "God's purpose, not my circumstances, decides what is good.")
        try! store.appendCard(to: note, kind: .quote, body: "Your worst day is not outside his purpose. It is inside it, and he is not finished.")
        try! store.appendCard(to: note, kind: .verse, body: "", verseRef: "John 3:16")
        try! store.appendCard(to: note, kind: .quote, body: "The golden chain has no weak link, because God forged every one.")
        try! store.appendCard(to: note, kind: .keyPoint, body: "“Glorified” is in the past tense. Tomorrow, worship like it is already settled.")
        return note
    }

    /// `-SeedSameDaySermon YES` (TKL-1115): a second, older note of the same Sunday with one kept card,
    /// so the reel holds two sermons on one day (the sample first, this one after it).
    @MainActor @discardableResult
    static func seedSameDayCompanion(container: ModelContainer, sample: LordsDayNote) -> LordsDayNote {
        let store = LordsDayStore(context: container.mainContext)
        let note = LordsDayNote(serviceDate: sample.serviceDate, sermonTitle: "The Morning Lesson",
                                createdAt: sample.createdAt.addingTimeInterval(-3600),
                                updatedAt: sample.createdAt.addingTimeInterval(-3600))
        try! store.save(note)
        try! store.appendCard(to: note, kind: .keyPoint, body: "The Lord's Day is a gift before it is a duty.")
        return note
    }
}
#endif
