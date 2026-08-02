// Local, guest-only progress persistence — SwiftData port of
// src/lib/localCatechismProgress.ts. No account, no name capture, same as
// the web app: this is the only progress store the iOS app has in v1.
import Foundation
import SwiftData

public struct MilestoneRecord: Codable, Equatable, Sendable {
    public var state: String // "introduced" | "reviewing" | "mastered"
    public var introducedAt: Date
    public var reviewCount: Int
}

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

// Mirrors the top-level `activeCatechismId` field of the localStorage blob.
@Model
final class ProgressSettings {
    var activeCatechismId: String?
    init(activeCatechismId: String? = nil) {
        self.activeCatechismId = activeCatechismId
    }
}

// SwiftData port of src/lib/localSeriesProgress.ts's per-series completions
// record — one row per series slug, completed day numbers as they're
// finished (order preserved, though only membership is ever read back).
@Model
final class SeriesProgressRecord {
    @Attribute(.unique) var seriesSlug: String
    private var completedDaysData: Data

    var completedDays: [Int] {
        get { (try? JSONDecoder().decode([Int].self, from: completedDaysData)) ?? [] }
        set { completedDaysData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    init(seriesSlug: String, completedDays: [Int] = []) {
        self.seriesSlug = seriesSlug
        self.completedDaysData = (try? JSONEncoder().encode(completedDays)) ?? Data()
    }
}
