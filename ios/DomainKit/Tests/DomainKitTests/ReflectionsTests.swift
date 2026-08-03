// No web vitest suite exists for src/lib/reflections.ts/commentary.ts to
// port 1:1 (unlike most DomainKit ports) — these cases were written directly
// against the bundled content/commentary/WSC-1.md fixture.
import Testing
@testable import DomainKit

@Suite("reflections")
struct ReflectionsTests {
    @Test("bundled WSC-1 essay loads with parsed frontmatter")
    func loadsBundledEssay() {
        let post = getReflectionByEntryId("WSC-1")
        #expect(post != nil)
        #expect(post?.title == "Made for Glory and Joy")
        #expect(post?.subtitle == "On the chief end of man")
        #expect(post?.author == "Maxwell Kendall")
        #expect(post?.authorSlug == "maxwell-kendall")
        #expect(post?.date == "2026-07-05")
        #expect(post?.slug == "made-for-glory-and-joy")
        #expect(post?.series == nil)
        #expect(post?.part == nil)
        #expect(post?.body.contains("## Two ends that are one") == true)
    }

    @Test("lookup by slug matches lookup by entry id")
    func slugLookupMatchesEntryLookup() {
        let byEntry = getReflectionByEntryId("WSC-1")
        let bySlug = byEntry.map { getReflectionBySlug($0.slug) } ?? nil
        #expect(bySlug == byEntry)
    }

    @Test("unknown entry ids and slugs return nil")
    func unknownReturnsNil() {
        #expect(getReflectionByEntryId("WSC-999") == nil)
        #expect(getReflectionBySlug("not-a-real-essay") == nil)
    }

    @Test("listCommentaryIds includes every loaded entry id")
    func listCommentaryIdsIncludesLoaded() {
        let ids = listCommentaryIds()
        for post in loadReflections() {
            #expect(ids.contains(post.entryId))
        }
    }

    @Test("slugify mirrors the web helper's punctuation/whitespace rules")
    func slugifyRules() {
        #expect(slugify("Made for Glory and Joy") == "made-for-glory-and-joy")
        #expect(slugify("Man's Chief End") == "mans-chief-end")
        #expect(slugify("  Leading & Trailing -- ") == "leading-trailing")
    }
}

@Suite("formatDate")
struct FormatDateTests {
    @Test("long style spells the month and includes the year")
    func long() {
        #expect(formatDate("2026-07-08") == "July 8, 2026")
    }

    @Test("short style abbreviates the month and drops the year")
    func short() {
        #expect(formatDate("2026-07-08", style: .short) == "Jul 8")
    }

    @Test("nil input renders empty")
    func nilInput() {
        #expect(formatDate(nil) == "")
    }

    @Test("malformed input passes through unchanged")
    func malformed() {
        #expect(formatDate("not-a-date") == "not-a-date")
    }
}
