// Ported 1:1 from test/devotionSeries.test.ts.
import Testing
@testable import DomainKit

@Suite("the series manifest")
struct SeriesManifestTests {
    @Test("every series is retrievable by its slug")
    func retrievable() {
        for series in getAllSeries() {
            #expect(getSeries(series.slug) == series)
        }
        #expect(getSeries("christmastide") == nil)
    }

    @Test("series slugs share the /devotions/[slug] namespace without colliding")
    func noSlugCollision() {
        for series in getAllSeries() {
            #expect(getDevotion(series.slug) == nil)
        }
    }

    @Test("parts are numbered 1..n in order, each with a title and citation")
    func partsNumberedInOrder() {
        for series in getAllSeries() {
            #expect(series.parts.map(\.day) == Array(1...series.parts.count))
            for part in series.parts {
                #expect(!part.title.isEmpty)
                #expect(!part.citation.isEmpty)
            }
        }
    }

    @Test("advent is season-sourced, Prepare the Way, with the annunciation at part 9")
    func adventSeries() {
        let advent = getSeries("advent")!
        #expect(advent.source == .season(season: "advent"))
        #expect(advent.title == "Prepare the Way")
        #expect(seriesForSeason("advent") == advent)
        #expect(seriesSourceLabel(advent) == "Advent")
        #expect(advent.parts.count == SEASONS.first { $0.slug == "advent" }!.days)
        #expect(advent.parts[8].day == 9)
        #expect(advent.parts[8].title == "The Annunciation")
        #expect(advent.parts[8].citation == "Luke 1:26\u{2013}38")
    }

    @Test("wsc is catechism-sourced, ordered by question")
    func wscSeries() {
        let wsc = getSeries("wsc")!
        #expect(wsc.source == .catechism(documentId: "WSC"))
        #expect(seriesForCatechism("WSC") == wsc)
        #expect(seriesSourceLabel(wsc) == "Westminster Shorter Catechism")
        #expect(wsc.parts[0].day == 1)
        #expect(wsc.parts[0].citation == "WSC Q. 1")
        #expect(wsc.parts[0].devotionSlug == "wsc-1")
    }

    @Test("catechismQuestionsAuthored sums a part's covered questions, including paired parts")
    func questionsAuthored() {
        let wsc = getSeries("wsc")!
        #expect(catechismQuestionsAuthored(wsc) > wsc.parts.count)
        #expect(catechismQuestionsAuthored(wsc) == 66)
    }
}

@Suite("parts and their devotions")
struct PartsAndDevotionsTests {
    @Test("an authored part resolves to its devotion, by slug")
    func partResolvesToDevotion() {
        let advent = getSeries("advent")!
        let wsc = getSeries("wsc")!
        #expect(partDevotion(advent, 1) == getDevotion("advent-1"))
        #expect(partDevotion(advent, 3) == getDevotion("advent-3"))
        #expect(partDevotion(wsc, 1) == getDevotion("wsc-1"))
    }

    @Test("a part still in preparation resolves to nil")
    func unauthoredPart() {
        let advent = getSeries("advent")!
        #expect(partDevotion(advent, 24) == nil)
    }

    @Test("authored parts run contiguously from day 1")
    func contiguousFromDayOne() {
        for series in getAllSeries() {
            let authored = series.parts.map { partDevotion(series, $0.day) != nil }
            guard let frontier = authored.firstIndex(of: false) else { continue }
            #expect(!authored[frontier...].contains(true), "\(series.slug)")
        }
    }

    @Test("every season-grounded devotion is a listed part of its series")
    func seasonMembership() {
        for devotion in devotionsGroundedIn(.season) {
            let membership = seriesMembership(devotion)
            #expect(membership != nil)
            if let membership {
                #expect(partDevotion(membership.series, membership.part.day) == devotion)
            }
        }
    }

    @Test("every catechism-grounded devotion is a listed part of the wsc run")
    func catechismMembership() {
        for devotion in devotionsGroundedIn(.catechism) {
            let membership = seriesMembership(devotion)
            #expect(membership != nil)
            #expect(membership?.series.slug == "wsc")
            if let membership {
                #expect(partDevotion(membership.series, membership.part.day) == devotion)
            }
        }
    }

    @Test("a devotion pairing two questions is one part, not two")
    func pairedQuestionIsOnePart() {
        let paired = getDevotion("wsc-40")!
        #expect(paired.grounding == .catechism(entryIds: ["WSC-40", "WSC-41"]))
        let membership = seriesMembership(paired)!
        #expect(membership.part.citation == "WSC Q. 40\u{2013}41")
    }

    @Test("a standalone devotion belongs to no series")
    func standaloneDevotion() {
        #expect(seriesMembership(getDevotion("psalm-130")!) == nil)
    }
}
