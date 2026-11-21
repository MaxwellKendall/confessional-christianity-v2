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
        #expect(names.isSuperset(of: ["LocalChild", "ChildCatechismTrack", "ProgressSettings"]))
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

        let started = Date(timeIntervalSince1970: 100)
        let milestones = [
            "3": MilestoneRecord(state: "mastered", introducedAt: started, reviewCount: 8),
            "4": MilestoneRecord(state: "reviewing", introducedAt: started, reviewCount: 2),
            "8": MilestoneRecord(state: "introduced", introducedAt: started, reviewCount: 0),
        ]
        let shipped = Schema([
            ShippedProgress.LocalCatechismTrack.self, LegacySettings.ProgressSettings.self,
            Retired.SeriesProgressRecord.self, Retired.ReadingPlanProgressRecord.self,
        ] + (withSyncTables ? syncModelTypes : []))
        do {
            let old = try ModelContainer(for: shipped, configurations: [ModelConfiguration(schema: shipped, url: url)])
            old.mainContext.insert(ShippedProgress.LocalCatechismTrack(
                catechismId: "WSC", currentQuestion: 9, startedAtQuestion: 3,
                startedAt: started, updatedAt: started, milestones: milestones
            ))
            old.mainContext.insert(ShippedProgress.LocalCatechismTrack(
                catechismId: "HC", currentQuestion: 15, startedAtQuestion: 1,
                startedAt: started, updatedAt: started.addingTimeInterval(10), milestones: milestones
            ))
            old.mainContext.insert(LegacySettings.ProgressSettings(activeCatechismId: "WSC"))
            old.mainContext.insert(Retired.SeriesProgressRecord(seriesSlug: "wsc", completedDays: [1, 2]))
            old.mainContext.insert(Retired.ReadingPlanProgressRecord(planSlug: "bible-in-a-year", completedDays: [1]))
            try old.mainContext.save()
        }

        let childId: UUID
        do {
            let upgraded = try openProgressContainer(at: url)
            let store = LocalProgressStore(context: upgraded.mainContext)
            childId = try #require(store.activeChildId)
            #expect(try upgraded.mainContext.fetch(FetchDescriptor<LocalChild>()).map(\.name) == ["My child"])
            let track = try #require(store.activeTrack(childId: childId))
            #expect(track.catechismId == "WSC")
            #expect(track.currentQuestion == 9)
            #expect(track.startedAtQuestion == 3)
            #expect(track.startedAt == started)
            #expect(track.updatedAt == started)
            let tracks = try upgraded.mainContext.fetch(FetchDescriptor<ChildCatechismTrack>())
            #expect(Set(tracks.map(\.catechismId)) == ["WSC", "HC"])
            #expect(tracks.allSatisfy { $0.childId == childId && $0.milestones == milestones })
        }
        let reopened = try openProgressContainer(at: url)
        let widgetStore = LocalProgressStore(context: ModelContext(reopened))
        #expect(widgetStore.activeChildId == childId)
        #expect(widgetStore.activeChildId.flatMap { widgetStore.activeTrack(childId: $0) }?.catechismId == "WSC")
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<LocalChild>()) == 1)
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<ChildCatechismTrack>()) == 2)
    }

    // TKL-825: a new guest must reach Today's empty state, so a store with no
    // progress to move gets no placeholder child. The first child is added by
    // the person (or by starting a session).
    @Test("a brand-new store opens with no children, and stays that way on reopen")
    @MainActor
    func freshStoreHasNoChildren() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Progress.sqlite")
        do {
            let fresh = try openProgressContainer(at: url)
            #expect(try fresh.mainContext.fetchCount(FetchDescriptor<LocalChild>()) == 0)
            #expect(LocalProgressStore(context: fresh.mainContext).activeChildId == nil)
        }
        let reopened = try openProgressContainer(at: url)
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<LocalChild>()) == 0)
        let store = LocalProgressStore(context: reopened.mainContext)
        let first = try store.addChild(name: "Samuel")
        #expect(store.activeChildId == first.id)
    }

    @Test("child profiles isolate tracks and delete only their own progress")
    @MainActor
    func managesChildren() throws {
        let config = ModelConfiguration(schema: progressSchema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: progressSchema, configurations: [config])
        let store = LocalProgressStore(context: container.mainContext)
        let first = try store.addChild(name: "First", age: 8)
        let second = try store.addChild(name: "Second")
        try store.renameChild(childId: second.id, name: "Renamed")
        #expect(second.name == "Renamed")
        #expect(first.age == 8)
        #expect(second.updatedAt >= second.createdAt)

        store.startTrack(childId: first.id, catechismId: "WSC", startingQuestion: 3)
        store.startTrack(childId: second.id, catechismId: "WSC", startingQuestion: 20)
        try store.selectChild(childId: second.id)
        #expect(store.activeChildId == second.id)
        #expect(store.activeTrack(childId: first.id)?.currentQuestion == 3)
        #expect(store.activeTrack(childId: second.id)?.currentQuestion == 20)

        let deletedId = second.id
        try store.deleteChild(childId: deletedId)
        #expect(store.activeChildId == first.id)
        #expect(store.activeTrack(childId: deletedId) == nil)
        #expect(store.activeTrack(childId: first.id)?.currentQuestion == 3)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<LocalChild>()) == 1)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<ChildCatechismTrack>()) == 1)
        #expect(store.startTrack(childId: deletedId, catechismId: "WSC", startingQuestion: 1) == nil)
    }
}

private enum LegacySettings {
    @Model
    final class ProgressSettings {
        var activeCatechismId: String?
        init(activeCatechismId: String?) {
            self.activeCatechismId = activeCatechismId
        }
    }
}

private enum ShippedProgress {
    @Model
    final class LocalCatechismTrack {
        @Attribute(.unique) var catechismId: String
        var currentQuestion: Int
        var startedAtQuestion: Int
        var startedAt: Date
        var updatedAt: Date
        private var milestonesData: Data

        var milestones: [String: MilestoneRecord] {
            get { (try? JSONDecoder().decode([String: MilestoneRecord].self, from: milestonesData)) ?? [:] }
            set { milestonesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
        }

        init(
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

}
