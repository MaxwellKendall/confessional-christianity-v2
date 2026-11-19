// TKL-856: SeriesProgressRecord and ReadingPlanProgressRecord shipped in the
// App Store 1.0 store (build 2, Aug 2026) and the devotions surface that used
// them is gone. They are dropped from progressSchema; an existing on-device
// store must still open, keep its catechism progress, and lose only the
// retired tables.
import Foundation
import Testing
import SwiftData
@testable import DomainKit

// The retired models exactly as they shipped (same entity names, same
// attributes), so a store written with the old schema can be built here.
enum Retired {
    @Model
    final class SeriesProgressRecord {
        @Attribute(.unique) var seriesSlug: String
        private var completedDaysData: Data
        init(seriesSlug: String, completedDays: [Int]) {
            self.seriesSlug = seriesSlug
            self.completedDaysData = (try? JSONEncoder().encode(completedDays)) ?? Data()
        }
    }

    @Model
    final class ReadingPlanProgressRecord {
        @Attribute(.unique) var planSlug: String
        private var completedDaysData: Data
        init(planSlug: String, completedDays: [Int]) {
            self.planSlug = planSlug
            self.completedDaysData = (try? JSONEncoder().encode(completedDays)) ?? Data()
        }
    }
}

@Suite("progressSchema", .serialized)
struct ProgressSchemaTests {
    @Test("no longer carries the retired devotion tables")
    func dropsRetiredModels() {
        let names = Set(progressSchema.entities.map(\.name))
        #expect(names.isSuperset(of: ["LocalCatechismTrack", "ProgressSettings"]))
        #expect(!names.contains("SeriesProgressRecord"))
        #expect(!names.contains("ReadingPlanProgressRecord"))
    }

    // Stores on devices come in two shapes: App Store 1.0 (no sync tables yet)
    // and anything built since the sync engine landed (TKL-813).
    @Test("a store written with an older schema opens and keeps catechism progress",
          arguments: [false, true])
    @MainActor
    func upgradesShippedStore(withSyncTables: Bool) throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "tkl856-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "Progress.sqlite")

        let shipped = Schema([
            LocalCatechismTrack.self, ProgressSettings.self,
            Retired.SeriesProgressRecord.self, Retired.ReadingPlanProgressRecord.self,
        ] + (withSyncTables ? syncModelTypes : []))
        do {
            let old = try ModelContainer(for: shipped, configurations: [ModelConfiguration(schema: shipped, url: url)])
            let store = LocalProgressStore(context: old.mainContext)
            _ = store.resumeOrStartTrack(catechismId: "WSC")
            _ = store.advanceQuestion(catechismId: "WSC", totalQuestions: 107)
            old.mainContext.insert(Retired.SeriesProgressRecord(seriesSlug: "wsc", completedDays: [1, 2]))
            old.mainContext.insert(Retired.ReadingPlanProgressRecord(planSlug: "bible-in-a-year", completedDays: [1]))
            try old.mainContext.save()
        }

        let upgraded = try ModelContainer(
            for: progressSchema,
            configurations: [ModelConfiguration(schema: progressSchema, url: url)]
        )
        let track = LocalProgressStore(context: upgraded.mainContext).activeTrack()
        #expect(track?.catechismId == "WSC")
        #expect(track?.currentQuestion == 2)
    }
}
