import Testing
@testable import DomainKit

@Suite struct BibleTests {
    @Test(arguments: [
        ("Acts 2:31", "Acts.2.31"),
        ("Acts 2:24–27", "Acts.2.24-Acts.2.27"),
        ("1 Corinthians 15:3–4", "1Cor.15.3-1Cor.15.4"),
        ("Psalm 16:10", "Ps.16.10"),
        ("Acts 1:1–2:4", "Acts.1.1-Acts.2.4"),
        ("Romans 8:1-4", "Rom.8.1-Rom.8.4"),
        ("Psalm 73", "Ps.73"),
        ("Hebrews 8–10", "Heb.8-Heb.10"),
        ("Jude 4", "Jude.1.4"),
        ("Jude 20–21", "Jude.1.20-Jude.1.21"),
    ])
    func citationToOsisParsesKnownShapes(input: String, expected: String) {
        #expect(citationToOsis(input) == expected)
    }

    @Test func citationToOsisFailsSoftOnUnknownBook() {
        #expect(citationToOsis("Maccabees 1:1") == nil)
    }

    @Test func citationToOsisFailsSoftOnNonCitation() {
        #expect(citationToOsis("chief end of man") == nil)
    }

    @Test func citationToOsisRoundTripsStoredRefs() {
        let refs = ["Ps.73.24-Ps.73.28", "2Tim.3.15-2Tim.3.17", "Matt.12.40", "Song.2.16"]
        for osis in refs {
            #expect(citationToOsis(parseOsisBibleReference(osis)) == osis)
        }
    }

    @Test func bundledEsvTextFindsAKnownRef() {
        #expect(bundledEsvText(for: "1Chr.21.1") != nil)
    }

    @Test func bundledEsvTextFailsSoftOnUnknownRef() {
        #expect(bundledEsvText(for: "Not.a.ref") == nil)
    }
}
