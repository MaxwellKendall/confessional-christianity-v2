// Ported from src/lib/readingPlans.ts. The reading-plans domain: a second
// program type, sibling to devotion series. A plan is a fixed-length walk
// through the whole Bible in canonical order — no external plan data to
// source, the canon itself is the plan (see ReadingPlanContent.swift for
// the day-by-day schedule).
import Foundation

public struct ReadingPlanDefinition: Sendable {
    public let slug: String
    public let title: String
    /// conversational short name used in cards/CTAs ("Continue {shortTitle}")
    public let shortTitle: String
    /// eyebrow shown on the plan's home screen: the plan's pace
    public let pace: String
    public let description: String
    public let totalDays: Int
}

public let READING_PLANS: [ReadingPlanDefinition] = [
    ReadingPlanDefinition(
        slug: "whole-bible-one-year",
        title: "Whole Bible, One Year",
        shortTitle: "One Year",
        pace: "One Year",
        description: "The whole Bible, canonical order, in daily readings across a year.",
        totalDays: 365
    ),
    ReadingPlanDefinition(
        slug: "bible-in-90-days",
        title: "The Bible in 90 Days",
        shortTitle: "90 Days",
        pace: "90-Day",
        description: "The whole Bible, canonical order, at a faster daily pace.",
        totalDays: 90
    ),
]

public func getReadingPlan(_ slug: String) -> ReadingPlanDefinition? {
    READING_PLANS.first { $0.slug == slug }
}
