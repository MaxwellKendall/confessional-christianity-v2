// The verse-by-verse reader's pure logic (TKL-873): the card sequence per
// entry point, the confession clauses citing a single verse (including
// containing ranges), the reader settings and the verse-card font step.
import Foundation
import Testing
@testable import DomainKit

private let rom8 = [
    ReaderVerse(osis: "Rom.8.28", verse: 28, text: "And we know that for those who love God all things work together for good,"),
    ReaderVerse(osis: "Rom.8.29", verse: 29, text: "For those whom he foreknew he also predestined"),
    ReaderVerse(osis: "Rom.8.30", verse: 30, text: "And those whom he predestined he also called,"),
]

private let sermon = ReaderSource.sermonText(
    passageOsis: "Rom.8.28-Rom.8.30", weekday: "Wednesday", dayIndex: 3, daysInWeek: 6,
    notesKeyPoint: "God works all things for the good of those he called."
)

private let proof = ReaderSource.proofText(
    catechismSlug: "westminster-shorter-catechism", questionNumber: 32,
    question: "What benefits do they that are effectually called partake of in this life?",
    answer: "They that are effectually called do in this life partake of justification, adoption, and sanctification…",
    osis: "Rom.8.30"
)

@Suite struct ReaderCardsTests {
    @Test func sermonWithKeyPointIsIntroVersesNotesEnd() {
        #expect(readerCards(for: sermon, verses: rom8) == [
            .intro, .verse(rom8[0]), .verse(rom8[1]), .verse(rom8[2]),
            .notes("God works all things for the good of those he called."), .end,
        ])
    }

    @Test func sermonWithoutKeyPointHasNoNotesCard() {
        let noNotes = ReaderSource.sermonText(
            passageOsis: "Rom.8.28-Rom.8.30", weekday: "Monday", dayIndex: 1, daysInWeek: 6, notesKeyPoint: nil
        )
        #expect(readerCards(for: noNotes, verses: rom8) == [
            .intro, .verse(rom8[0]), .verse(rom8[1]), .verse(rom8[2]), .end,
        ])
    }

    @Test func proofTextIsIntroVersesEnd() {
        #expect(readerCards(for: proof, verses: [rom8[2]]) == [.intro, .verse(rom8[2]), .end])
    }

    @Test(arguments: [sermon, proof])
    func emptyVersesGiveIntroAndEndOnly(source: ReaderSource) {
        #expect(readerCards(for: source, verses: []) == [.intro, .end])
    }
}

@Suite struct CitingEntriesForVerseTests {
    @Test(arguments: [
        ("Rom.8.28-Rom.8.30", "Rom.8.29", true),
        ("Rom.8.28-Rom.8.30", "Rom.8.28", true),
        ("Rom.8.28-Rom.8.30", "Rom.8.30", true),
        ("Rom.8.28-Rom.8.30", "Rom.8.31", false),
        ("Rom.8.29", "Rom.8.29", true),
        ("Rom.8.29", "Rom.8.2", false),
        ("Rom.7.24-Rom.8.2", "Rom.8.1", true),
        ("Rom.7.24-Rom.8.2", "Rom.7.25", true),
        ("Rom.7.24-Rom.8.2", "Rom.8.3", false),
        ("Rom.8", "Rom.8.16", true),
        ("Rom.8", "Rom.9.1", false),
        ("Rom.8-Rom.9", "Rom.9.33", true),
        ("Gen.1-Gen.2", "Gen.3.1", false),
        ("1Rom.8.16", "Rom.8.16", false),
        ("John.8.16", "Rom.8.16", false),
        ("Rom.8.28-Rom.8.30", "not-a-verse", false),
    ])
    func rangeContainment(range: String, verse: String, expected: Bool) {
        #expect(osisReference(range, containsVerse: verse) == expected)
    }

    @Test func rom816IncludesExactAndContainingRangeCitations() {
        let ids = citingEntries(forVerse: "Rom.8.16").map(\.entryId)
        #expect(ids == ROM_8_16_IDS)
        // WCF 18.2 cites Rom.8.15-Rom.8.16 only as a range: an exact-key lookup misses it.
        #expect(!getScriptureCitingEntries("Rom.8.16").map(\.entryId).contains("WCoF-18-2"))
        #expect(ids.contains("WCoF-18-2"))
    }

    @Test func rom830MatchesBundledData() {
        #expect(citingEntries(forVerse: "Rom.8.30").map(\.entryId) == ROM_8_30_IDS)
    }

    @Test func resultsAreDeduplicatedByEntryId() {
        for verse in ["Rom.8.16", "Rom.8.30", "Rom.8.28"] {
            let ids = citingEntries(forVerse: verse).map(\.entryId)
            #expect(ids.count == Set(ids).count)
        }
    }

    @Test func uncitedVerseHasNoCitingEntries() {
        #expect(citingEntries(forVerse: "Rom.16.24").isEmpty)
    }
}

@Suite(.serialized) struct ReaderSettingsTests {
    private func freshDefaults() -> UserDefaults {
        let name = "ReaderSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsMatchTheDesign() {
        let s = ReaderSettings()
        #expect(s.textSize == 2)
        #expect(s.showVerseNumbers)
        #expect(s.showConfessionMarks)
        #expect(!s.dark)
    }

    @Test func emptyStoreLoadsDefaults() {
        #expect(ReaderSettings.load(from: freshDefaults()) == ReaderSettings())
    }

    @Test func roundTripsThroughUserDefaults() {
        let defaults = freshDefaults()
        let changed = ReaderSettings(textSize: 4, showVerseNumbers: false, showConfessionMarks: false, dark: true)
        changed.save(to: defaults)
        #expect(ReaderSettings.load(from: defaults) == changed)
    }

    @Test func textSizeIsClampedToFiveSteps() {
        #expect(ReaderSettings(textSize: -3).textSize == 0)
        #expect(ReaderSettings(textSize: 9).textSize == 4)
        var s = ReaderSettings()
        s.textSize = 7
        #expect(s.textSize == 4)
    }
}

@Suite struct VerseFontSizeTests {
    @Test(arguments: [
        (0, 32), (69, 32), (70, 27), (119, 27), (120, 23), (179, 23), (180, 20), (900, 20),
    ])
    func stepsDownWithLengthAtDefaultSize(length: Int, expected: Double) {
        #expect(readerVerseFontSize(textLength: length, textSize: 2) == expected)
    }

    @Test(arguments: [(0, 28.0), (1, 30.0), (2, 32.0), (3, 34.0), (4, 36.0)])
    func settingsOffsetIsTwoPointsPerStep(textSize: Int, expected: Double) {
        #expect(readerVerseFontSize(textLength: 10, textSize: textSize) == expected)
    }

    @Test func outOfRangeTextSizeIsClamped() {
        #expect(readerVerseFontSize(textLength: 200, textSize: 99) == 24)
        #expect(readerVerseFontSize(textLength: 200, textSize: -5) == 16)
    }
}

// Pinned from the bundled data on 2026-11-19. The TKL-838 design showed
// Rom 8:16 → WCF 18.2, WCF 12.1, HC 28, HC 49; the data wins (ticket AC).
private let ROM_8_16_IDS = ["WCoF-18-2", "WLC-80", "HC-1-1", "HC-13-33"]
private let ROM_8_30_IDS = [
    "WSC-32", "WCoF-3-5", "WCoF-3-6", "WCoF-10-1", "WCoF-11-1", "WCoF-11-4", "WLC-69", "HC-21-54",
]

/// The chapter view and the settings sheet's preview line use the design's
/// five sizes (FS = 20/23/26/30/34, less 6 points) (TKL-972).
@Suite struct ChapterFontSizeTests {
    @Test(arguments: [(0, 14.0), (1, 17.0), (2, 20.0), (3, 24.0), (4, 28.0)])
    func followsTheDesignsFiveSteps(textSize: Int, expected: Double) {
        #expect(readerChapterFontSize(textSize: textSize) == expected)
    }

    @Test func clampsOutOfRangeSteps() {
        #expect(readerChapterFontSize(textSize: -2) == 14)
        #expect(readerChapterFontSize(textSize: 12) == 28)
    }

    @Test func sheetButtonsGrowTwoPointsPerStep() {
        #expect((0...4).map(readerSettingsSizeButtonFont) == [12, 14, 16, 18, 20])
    }
}

/// Reader display helpers for the approved v2 design (TKL-972): header pill title,
/// dark override, citation visibility, and clause headings / short topbar labels.
@Suite struct ReaderDisplayHelpersTests {
    @Test func headerTitleUsesQuestionLabelForProofTextAndReferenceForSermon() {
        #expect(readerHeaderTitle(for: proof) == "Q. 32 · proof text")
        #expect(readerHeaderTitle(for: sermon) == "Romans 8:28-30")
    }

    @Test func darkSettingForcesDarkAndOffFollowsSystem() {
        let off = ReaderSettings(dark: false)
        let on = ReaderSettings(dark: true)
        #expect(!readerEffectiveDark(settings: off, systemIsDark: false))
        #expect(readerEffectiveDark(settings: off, systemIsDark: true))
        #expect(readerEffectiveDark(settings: on, systemIsDark: false))
        #expect(readerEffectiveDark(settings: on, systemIsDark: true))
    }

    @Test func turningConfessionMarksOffHidesAllCitations() {
        let on = ReaderSettings(showConfessionMarks: true)
        let off = ReaderSettings(showConfessionMarks: false)
        #expect(readerVisibleCitations(forVerse: "Rom.8.16", settings: on).count == ROM_8_16_IDS.count)
        #expect(readerVisibleCitations(forVerse: "Rom.8.16", settings: off).isEmpty)
        #expect(!readerVisibleCitations(forPassage: "Rom.8.28-Rom.8.30", settings: on).isEmpty)
        #expect(readerVisibleCitations(forPassage: "Rom.8.28-Rom.8.30", settings: off).isEmpty)
    }

    @Test func clauseHeadingUsesChapterTitleForConfessionsAndQuestionForCatechisms() {
        let rom816 = citingEntries(forVerse: "Rom.8.16")
        let wcf = rom816.first { $0.entryId == "WCoF-18-2" }!
        let wlc = rom816.first { $0.entryId == "WLC-80" }!
        let hc = rom816.first { $0.entryId == "HC-1-1" }!

        #expect(readerClauseHeading(for: wcf) == "Of the Assurance of Grace and Salvation")
        #expect(readerClauseHeading(for: wlc)?.hasPrefix("Can true believers be infallibly assured") == true)
        #expect(readerClauseHeading(for: hc) == "What is thy only comfort in life and death?")
    }

    @Test func clauseShortLabelFormatsDocumentAbbreviationAndReference() {
        let rom816 = citingEntries(forVerse: "Rom.8.16")
        let wcf = rom816.first { $0.entryId == "WCoF-18-2" }!
        let wlc = rom816.first { $0.entryId == "WLC-80" }!
        let hc = rom816.first { $0.entryId == "HC-1-1" }!

        #expect(readerClauseShortLabel(for: wcf) == "WCF · Ch. 18.2")
        #expect(readerClauseShortLabel(for: wlc) == "WLC · Q. 80")
        #expect(readerClauseShortLabel(for: hc) == "HC · Q. 1")
    }
}
