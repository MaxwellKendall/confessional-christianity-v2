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
