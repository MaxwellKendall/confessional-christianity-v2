// Ported from src/lib/readingPlans.ts, then extended natively (no web
// counterpart yet) with a second kind of plan. A plan is either:
//   - sequential: a fixed-length walk through the whole Bible in canonical
//     order, split evenly across totalDays — the canon itself is the plan,
//     no external plan data to source (see ReadingPlanContent.swift). The
//     reader's own first incomplete day is "current"; it starts whenever
//     they begin.
//   - calendarMonthly: a short cycle keyed to the calendar's day-of-month
//     rather than to when the reader started — day 5 of any month is the
//     same reading (Proverbs 5, say), and the cycle repeats every month.
//     Both of Proverbs' 31 chapters and Psalms' 150 divide evenly against a
//     31- or 30-day month, so these read one classic devotional habit
//     (a Proverbs chapter a day; the Psalter every thirty days) directly off
//     the canon, same as the sequential plans.
import Foundation

public enum ReadingPlanCadence: Sendable {
    case sequential
    case calendarMonthly(book: String, chaptersPerDay: Int)
}

public struct ReadingPlanDefinition: Sendable {
    public let slug: String
    public let title: String
    /// conversational short name used in cards/CTAs ("Continue {shortTitle}")
    public let shortTitle: String
    /// eyebrow shown on the plan's home screen: the plan's pace
    public let pace: String
    public let description: String
    public let totalDays: Int
    public let cadence: ReadingPlanCadence
}

public let READING_PLANS: [ReadingPlanDefinition] = [
    ReadingPlanDefinition(
        slug: "whole-bible-one-year",
        title: "Whole Bible, One Year",
        shortTitle: "One Year",
        pace: "One Year",
        description: "The whole Bible, canonical order, in daily readings across a year.",
        totalDays: 365,
        cadence: .sequential
    ),
    ReadingPlanDefinition(
        slug: "bible-in-90-days",
        title: "The Bible in 90 Days",
        shortTitle: "90 Days",
        pace: "90-Day",
        description: "The whole Bible, canonical order, at a faster daily pace.",
        totalDays: 90,
        cadence: .sequential
    ),
    ReadingPlanDefinition(
        slug: "proverb-of-the-day",
        title: "Proverb of the Day",
        shortTitle: "Daily Proverb",
        pace: "Monthly",
        description: "One chapter of Proverbs a day, matched to the calendar date — day 5 of any month is Proverbs 5.",
        totalDays: 31,
        cadence: .calendarMonthly(book: "Prov", chaptersPerDay: 1)
    ),
    ReadingPlanDefinition(
        slug: "psalter-in-a-month",
        title: "Psalter in a Month",
        shortTitle: "Monthly Psalter",
        pace: "Monthly",
        description: "Five psalms a day, matched to the calendar date — all 150 psalms every thirty days.",
        totalDays: 30,
        cadence: .calendarMonthly(book: "Ps", chaptersPerDay: 5)
    ),
]

public func getReadingPlan(_ slug: String) -> ReadingPlanDefinition? {
    READING_PLANS.first { $0.slug == slug }
}
