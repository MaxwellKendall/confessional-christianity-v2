// Ported from src/lib/readingPlanContent.ts. A plan's days aren't authored
// content — they're the canon itself, walked in canonical order and split
// evenly across the plan's length. BIBLE_BOOKS already holds that order and
// each book's chapter count (Bible.swift), so a day's reading is derived,
// never stored.
import Foundation

public struct ReadingPlanDay: Sendable {
    public let day: Int
    /// OSIS chapter range ("Gen.34-Gen.36"), the citation/text-fetch key.
    public let osis: String
    /// display citation ("Genesis 34–36").
    public let citation: String
}

private struct PlanChapter {
    let bookOsis: String
    let bookName: String
    let chapter: Int
}

private let allChapters: [PlanChapter] = BIBLE_BOOKS.flatMap { book in
    (1...book.chapters).map { PlanChapter(bookOsis: book.osis, bookName: book.name, chapter: $0) }
}

private func citation(for chapters: [PlanChapter]) -> String {
    guard let first = chapters.first, let last = chapters.last else { return "" }
    if first.bookOsis == last.bookOsis {
        return first.chapter == last.chapter
            ? "\(first.bookName) \(first.chapter)"
            : "\(first.bookName) \(first.chapter)\u{2013}\(last.chapter)"
    }
    return "\(first.bookName) \(first.chapter) \u{2013} \(last.bookName) \(last.chapter)"
}

private func osis(for chapters: [PlanChapter]) -> String {
    guard let first = chapters.first, let last = chapters.last else { return "" }
    let start = "\(first.bookOsis).\(first.chapter)"
    let end = "\(last.bookOsis).\(last.chapter)"
    return start == end ? start : "\(start)-\(end)"
}

/// One day's reading: the canon's chapters split evenly across the plan's
/// length, in canonical order. Nil outside the plan's day range.
public func getReadingPlanDay(_ plan: ReadingPlanDefinition, _ day: Int) -> ReadingPlanDay? {
    guard day >= 1, day <= plan.totalDays else { return nil }
    let total = allChapters.count
    let start = (total * (day - 1)) / plan.totalDays
    let end = (total * day) / plan.totalDays
    guard start < end else { return nil }
    let chapters = Array(allChapters[start..<end])
    return ReadingPlanDay(day: day, osis: osis(for: chapters), citation: citation(for: chapters))
}

/// The whole plan's schedule, in order — the calendar grid's day list reads
/// off this.
public func getReadingPlanSchedule(_ plan: ReadingPlanDefinition) -> [ReadingPlanDay] {
    (1...plan.totalDays).compactMap { getReadingPlanDay(plan, $0) }
}
