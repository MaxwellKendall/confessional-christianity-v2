// Ported 1:1 from test/devotions.test.ts (the scripture-browse-by-book,
// topic-hub, and BIBLE_BOOKS canon-table tests are out of scope — nothing
// in DomainKit reaches those axes yet).
import Testing
@testable import DomainKit

private let eightStepOrder = [
    "Call to Worship", "Confessing Sin", "Receiving Forgiveness", "Singing Praise",
    "Professing Faith", "Reading Scripture", "Making Requests", "Closing Prayer",
]

@Suite("the devotion manifest")
struct DevotionManifestTests {
    @Test("every devotion is retrievable by its slug")
    func retrievable() {
        for devotion in getAllDevotions() {
            #expect(getDevotion(devotion.slug) == devotion)
        }
    }

    @Test("unknown slugs return nil")
    func unknownSlug() {
        #expect(getDevotion("psalm-131") == nil)
    }

    @Test("slugs are unique")
    func uniqueSlugs() {
        let slugs = getAllDevotions().map(\.slug)
        #expect(Set(slugs).count == slugs.count)
    }
}

@Suite("a devotion hands off to the eight-step worship shell")
struct DevotionShellTests {
    @Test("every devotion follows the same eight-step order")
    func stepOrder() {
        for devotion in getAllDevotions() {
            #expect(devotion.steps.map(\.role) == eightStepOrder)
        }
    }

    @Test("professing faith stays the catechism hand-off, fifth in the order")
    func professingFaithHandoff() {
        for devotion in getAllDevotions() {
            let step = devotion.steps[4]
            #expect(step.role == "Professing Faith")
            #expect(step.elements[0].typeName == "catechism")
        }
    }

    @Test("stepDetail reads devotion steps like service steps")
    func stepDetailPreview() {
        let devotion = getDevotion("psalm-130")!
        #expect(stepDetail(devotion.steps[0]) == "Psalm 130:1\u{2013}2")
        #expect(stepDetail(devotion.steps[1]) == nil)
    }
}

@Suite("grounding")
struct GroundingTests {
    @Test("psalm-130 is grounded in the scripture axis")
    func psalm130Grounding() {
        let devotion = getDevotion("psalm-130")!
        #expect(devotion.grounding == .scripture(osis: "Ps.130", citation: "Psalm 130"))
        #expect(devotionsGroundedIn(.scripture).contains(devotion))
        #expect(!devotionsGroundedIn(.topic).contains(devotion))
    }

    @Test("labels name what a devotion is grounded in, per axis")
    func labelsPerAxis() {
        #expect(groundingLabel(.scripture(osis: "Ps.130", citation: "Psalm 130")) == "Psalm 130")
        #expect(groundingLabel(.topic(topic: "repentance")) == "Repentance")
        #expect(groundingLabel(.catechism(entryIds: ["WSC-1"])) == "WSC Q. 1")
        #expect(groundingLabel(.catechism(entryIds: ["WSC-40", "WSC-41"])) == "WSC Q. 40\u{2013}41")
        #expect(groundingLabel(.season(season: "advent", day: 3)) == "Advent \u{00B7} Day 3")
    }

    @Test("labels degrade to the raw value when a registry lookup misses")
    func labelsDegrade() {
        #expect(groundingLabel(.topic(topic: "lament")) == "lament")
        #expect(groundingLabel(.catechism(entryIds: ["XYZ-9"])) == "XYZ-9")
    }
}

@Suite("the browse registries")
struct BrowseRegistryTests {
    @Test("topics carry the hub row's curated vocabulary")
    func topics() {
        #expect(TOPICS.map(\.slug) == ["repentance", "gratitude", "suffering", "anxiety", "vocation"])
    }

    @Test("seasons size their daily runs (Advent 24, Lent 40)")
    func seasons() {
        #expect(SEASONS.map { ($0.slug, $0.days) }.elementsEqual([("advent", 24), ("lent", 40)], by: ==))
    }
}
