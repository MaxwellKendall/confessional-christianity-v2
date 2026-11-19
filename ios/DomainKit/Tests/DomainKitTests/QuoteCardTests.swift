import CoreGraphics
import Foundation
import Testing
@testable import DomainKit

/// Sample cards mirroring the TKL-840 prototype's examples (`EX` in the
/// prototype). The sermon note uses a clearly sample preacher, never a real one.
enum QuoteCardSamples {
    static let all: [QuoteCardContent] = [
        QuoteCardContent(
            text: "The good of Romans 8:28 is not first our comfort but our conformity to Christ. God wastes nothing he puts in his children's hands.",
            attribution: .init(preacher: "Rev. J. Sample", church: "Sample Presbyterian Church", passage: "Romans 8:28", date: "15 Nov 2026"),
            link: "confessionalchristianity.com/q/7kd2"),
        QuoteCardContent(
            text: "Man's chief end is to glorify God, and to enjoy him for ever.",
            kind: .questionAndAnswer(question: "What is the chief end of man?"),
            attribution: .init(source: "Westminster Shorter Catechism", detail: "Question 1"),
            link: "confessionalchristianity.com/q/w1q1"),
        QuoteCardContent(
            text: "That I with body and soul, both in life and death, am not my own, but belong unto my faithful Saviour Jesus Christ.",
            kind: .questionAndAnswer(question: "What is thy only comfort in life and death?"),
            attribution: .init(source: "Heidelberg Catechism", detail: "Lord's Day 1 · Question 1"),
            link: "confessionalchristianity.com/q/hc01"),
        QuoteCardContent(
            text: "He hath particularly appointed one day in seven, for a Sabbath, to be kept holy unto him.",
            attribution: .init(source: "Westminster Confession of Faith", detail: "Chapter 21 · Section 7"),
            link: "confessionalchristianity.com/q/wcf7"),
        QuoteCardContent(
            text: "all who labor and are heavy laden, and I will give you rest.",
            kind: .verse(lead: "Come to me,"),
            attribution: .init(source: "Matthew 11:28", detail: "ESV"),
            link: "confessionalchristianity.com/q/mt28"),
        QuoteCardContent(
            text: "O God, from whom all holy desires, all good counsels, and all just works do proceed: Give unto thy servants that peace which the world cannot give.",
            attribution: .init(source: "Collect for Peace", detail: "Book of Common Prayer, 1662"),
            link: "confessionalchristianity.com/q/bcp3"),
        QuoteCardContent(
            text: "In creation, God gave us ourselves; in the redemption, he gave us himself.",
            attribution: .init(source: "Thomas Watson", detail: "A Body of Divinity"),
            link: "confessionalchristianity.com/q/tw01"),
    ]

    /// Public-domain text (WCF 1.1) to cut quotes of any length from.
    static let source = """
    Although the light of nature, and the works of creation and providence do so far manifest the goodness, wisdom, \
    and power of God, as to leave men inexcusable; yet are they not sufficient to give that knowledge of God, and of \
    his will, which is necessary unto salvation. Therefore it pleased the Lord, at sundry times, and in divers manners, \
    to reveal himself, and to declare that his will unto his church; and afterwards, for the better preserving and \
    propagating of the truth, and for the more sure establishment and comfort of the church against the corruption of \
    the flesh, and the malice of Satan and of the world, to commit the same wholly unto writing.
    """

    static func words(_ n: Int) -> String {
        let all = source.split(whereSeparator: \.isWhitespace)
        precondition(n <= all.count)
        return all.prefix(n).joined(separator: " ")
    }

    /// Every length the editor allows, in every kind of card.
    static func lengthMatrix(for format: QuoteCardFormat) -> [(String, QuoteCardContent)] {
        let lengths = [("1 word", 1), ("long", format.legibleWordLimit), ("max", QuoteCard.maximumWords)]
        var out: [(String, QuoteCardContent)] = []
        for (name, n) in lengths {
            let attr = QuoteCardAttribution(preacher: "Rev. J. Sample", church: "Sample Presbyterian Church",
                                            passage: "Romans 8:28", date: "15 Nov 2026")
            out.append(("quote \(name)", QuoteCardContent(text: words(n), attribution: attr)))
            out.append(("qa \(name)", QuoteCardContent(
                text: words(n), kind: .questionAndAnswer(question: "What is the chief end of man?"),
                attribution: .init(source: "Westminster Shorter Catechism", detail: "Question 1"))))
            out.append(("verse \(name)", QuoteCardContent(
                text: n > 2 ? words(n - 2) : words(1), kind: .verse(lead: n > 2 ? "Come to" : ""),
                attribution: .init(source: "Matthew 11:28", detail: "ESV"))))
        }
        // A single long word must shrink rather than break mid-word.
        out.append(("one long word", QuoteCardContent(text: "Incomprehensibleness", attribution: .init(source: "Sample"))))
        return out
    }
}

@Suite struct QuoteCardRendererTests {
    @Test(arguments: QuoteCardFormat.allCases)
    func rendersAtTheExactPixelSizeOfEachFormat(format: QuoteCardFormat) throws {
        let expected: (Int, Int) = switch format {
        case .square: (1080, 1080)
        case .story: (1080, 1920)
        case .linkPreview: (1200, 630)
        }
        let image = try #require(QuoteCardRenderer.render(QuoteCardSamples.all[0], palette: .vellum, format: format))
        #expect(image.width == expected.0)
        #expect(image.height == expected.1)
        let png = try #require(QuoteCardRenderer.pngData(QuoteCardSamples.all[0], palette: .vellum, format: format))
        #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test func offersThePrototypesNinePalettes() {
        #expect(QuoteCardPalette.all.map(\.name) ==
            ["vellum", "psalter", "cloister", "vespers", "hymnal", "lectern", "ironstone", "ember", "puritan"])
        #expect(QuoteCardPalette.vellum.field == 0xF3EAD8)
        #expect(QuoteCardPalette.puritan.accent == 0xC9A45C)
    }

    @Test func bundledTypefacesAreCinzelAndMarcellus() {
        #expect(QuoteCardFonts.postScriptNames.sorted() == ["Cinzel-Regular", "Cinzel-SemiBold", "Marcellus-Regular"])
    }

    @Test(arguments: QuoteCardFormat.allCases)
    func textFitsItsRegionFromOneWordToTheMaximum(format: QuoteCardFormat) {
        let size = format.size
        for (name, content) in QuoteCardSamples.lengthMatrix(for: format) {
            let layout = QuoteCardLayout(content, format: format)
            #expect(layout.fits, "\(format) \(name): does not fit at \(layout.fontSize)pt")
            #expect(!layout.brokeWordMidLine, "\(format) \(name): a word was split across lines")
            #expect(layout.bodyContentHeight <= layout.bodyRegion.height + 0.5, "\(format) \(name): overflows vertically")
            let frameInterior = CGRect(origin: .zero, size: size).insetBy(dx: 46, dy: 46)
            for item in layout.textItems {
                #expect(frameInterior.contains(item.frame), "\(format) \(name): '\(item.text)' \(item.frame) leaves the frame")
            }
            // Body text stays inside the body region; the drop cap may hang
            // into the margin by its optical overhang only: the prototype's
            // -0.04em margin (0.132 × type size) plus the glyph's own side bearing.
            let allowed = layout.bodyRegion.insetBy(dx: -0.2 * layout.fontSize, dy: -0.5)
            for item in layout.textItems where item.role != .footer {
                #expect(allowed.contains(item.frame), "\(format) \(name): '\(item.text)' \(item.frame) leaves \(layout.bodyRegion)")
            }
        }
    }

    @Test(arguments: QuoteCardFormat.allCases)
    func shortQuotesAreSetLargerThanLongOnes(format: QuoteCardFormat) {
        let short = QuoteCardLayout(QuoteCardContent(text: QuoteCardSamples.words(4)), format: format)
        let long = QuoteCardLayout(QuoteCardContent(text: QuoteCardSamples.words(QuoteCard.maximumWords)), format: format)
        #expect(short.fontSize > long.fontSize * 1.4)
    }

    @Test func storyKeepsAllTextOutOfTheSafeZones() {
        var contents = QuoteCardSamples.all
        contents += QuoteCardSamples.lengthMatrix(for: .story).map(\.1)
        for content in contents {
            let layout = QuoteCardLayout(content, format: .story)
            #expect(!layout.textItems.isEmpty)
            for item in layout.textItems {
                #expect(item.frame.minY >= 250, "'\(item.text)' starts at y=\(item.frame.minY), inside the top 250px")
                #expect(item.frame.maxY <= 1920 - 300, "'\(item.text)' ends at y=\(item.frame.maxY), inside the bottom 300px")
            }
        }
    }

    @Test(arguments: QuoteCardFormat.allCases)
    func brandLineAndShortLinkAreOnEveryCard(format: QuoteCardFormat) {
        let layout = QuoteCardLayout(QuoteCardSamples.all[0], format: format)
        let footer = layout.textItems.filter { $0.role == .footer }
        #expect(footer.map(\.text) == ["CONFESSIONAL CHRISTIANITY", "confessionalchristianity.com/q/7kd2"])
        #expect(footer[0].frame.maxX < footer[1].frame.minX)
        // Without a link the card carries the bare domain (Save Image publishes nothing).
        let saved = QuoteCardLayout(QuoteCardContent(text: "Grace."), format: format)
        #expect(saved.textItems.last?.text == "confessionalchristianity.com")
    }

    @Test func dropCapAndRunInOpenAQuote() {
        let layout = QuoteCardLayout(QuoteCardSamples.all[0], format: .square)
        let drop = layout.textItems.first { $0.role == .dropCap }
        #expect(drop?.text == "T")
        let first = layout.textItems.first { $0.role == .quote }
        #expect(first?.text.hasPrefix("HE good") == true)
        // Lines beside the drop cap are indented past it; later ones are not.
        let quoteLines = layout.textItems.filter { $0.role == .quote }
        #expect(quoteLines[0].frame.minX > drop!.frame.maxX)
        #expect(quoteLines.last!.frame.minX < drop!.frame.maxX)
    }

    @Test(arguments: QuoteCardFormat.allCases)
    func noSingleWordIsLeftAloneOnTheLastLine(format: QuoteCardFormat) {
        for content in QuoteCardSamples.all {
            let lines = QuoteCardLayout(content, format: format).textItems.filter { $0.role == .quote }
            if lines.count >= 2 {
                #expect(QuoteCard.words(lines.last!.text) >= 2, "\(format): orphan '\(lines.last!.text)'")
            }
        }
    }

    @Test(arguments: ["'Tis grace that brought me safe thus far.", "−12 degrees of mercy.", "“Grace upon grace.”"])
    func openingPunctuationIsPreserved(text: String) {
        for format in QuoteCardFormat.allCases {
            let layout = QuoteCardLayout(QuoteCardContent(text: text), format: format)
            let drawn = layout.textItems.filter { [.dropCap, .quote].contains($0.role) }.map(\.text).joined()
            func normalized(_ value: String) -> String { value.lowercased().filter { !$0.isWhitespace } }
            #expect(normalized(drawn) == normalized(text), "\(format): \(drawn)")
        }
    }

    @Test func verseOpensWithALeadInNotADropCap() {
        let layout = QuoteCardLayout(QuoteCardSamples.all[4], format: .square)
        #expect(!layout.textItems.contains { $0.role == .dropCap })
        #expect(layout.textItems.first { $0.role == .quote }?.text.hasPrefix("COME TO ME,") == true)
    }

    @Test func catechismCardCarriesTheQuestionAboveTheAnswer() {
        let layout = QuoteCardLayout(QuoteCardSamples.all[1], format: .square)
        let question = layout.textItems.first { $0.role == .question }
        let drop = layout.textItems.first { $0.role == .dropCap }
        #expect(question?.text == "Q. WHAT IS THE CHIEF END OF MAN?")
        #expect(question!.frame.maxY < drop!.frame.minY)
    }

    @Test(arguments: [0, 1, 4, 5])
    func quoteTextIsNeverDroppedOrInvented(sample: Int) {
        let content = QuoteCardSamples.all[sample]
        for format in QuoteCardFormat.allCases {
            let layout = QuoteCardLayout(content, format: format)
            let drawn = layout.textItems.filter { [.dropCap, .quote].contains($0.role) }.map(\.text).joined()
            var expected = content.text
            if case .verse(let lead) = content.kind { expected = lead + expected }
            func norm(_ s: String) -> String { s.lowercased().filter { !$0.isWhitespace } }
            #expect(norm(drawn) == norm(expected), "\(format)")
        }
    }
}

@Suite struct QuoteCardAttributionTests {
    @Test func emptyFieldsAreLeftOutNotFilledIn() {
        let a = QuoteCardAttribution(preacher: "Rev. J. Sample", church: "", passage: nil, date: "   ")
        #expect(a.lines == ["Rev. J. Sample"])
        let layout = QuoteCardLayout(QuoteCardContent(text: "Grace upon grace.", attribution: a), format: .square)
        let attr = layout.textItems.filter { $0.role == .attribution }.map(\.text)
        #expect(attr == ["REV. J. SAMPLE"])
        for text in layout.textItems.map(\.text) {
            #expect(!text.contains("·"), "dangling separator in '\(text)'")
            for placeholder in ["UNKNOWN", "N/A", "CHURCH", "PREACHER", "UNTITLED", "ANONYMOUS"] {
                #expect(!text.uppercased().contains(placeholder), "placeholder '\(placeholder)' in '\(text)'")
            }
        }
    }

    @Test func noAttributionAtAllDrawsNoAttributionText() {
        let layout = QuoteCardLayout(QuoteCardContent(text: "Grace upon grace.",
                                                      attribution: .init(preacher: " ", source: "")), format: .square)
        #expect(layout.textItems.filter { $0.role == .attribution }.isEmpty)
    }

    @Test func everyGivenFieldIsDrawnInOrder() {
        let a = QuoteCardAttribution(preacher: "Rev. J. Sample", church: "Sample Presbyterian Church",
                                     passage: "Romans 8:28", date: "15 Nov 2026")
        #expect(a.lines == ["Rev. J. Sample", "Sample Presbyterian Church · Romans 8:28 · 15 Nov 2026"])
        for format in QuoteCardFormat.allCases {
            let layout = QuoteCardLayout(QuoteCardContent(text: QuoteCardSamples.words(QuoteCard.maximumWords),
                                                          attribution: a), format: format)
            let drawn = layout.textItems.filter { $0.role == .attribution }.map(\.text).joined(separator: " ")
            for field in ["REV. J. SAMPLE", "SAMPLE PRESBYTERIAN CHURCH", "ROMANS 8:28", "15 NOV 2026"] {
                #expect(drawn.contains(field), "\(format): '\(field)' missing from '\(drawn)'")
            }
        }
    }

    @Test func sourceLabelLeadsWhenThereIsNoPreacher() {
        #expect(QuoteCardAttribution(source: "Westminster Shorter Catechism, Q.1").lines == ["Westminster Shorter Catechism, Q.1"])
        #expect(QuoteCardAttribution(source: "Westminster Shorter Catechism", detail: "Question 1").lines
            == ["Westminster Shorter Catechism", "Question 1"])
        #expect(QuoteCardAttribution(passage: "Matthew 11:28").lines == ["Matthew 11:28"])
        #expect(QuoteCardAttribution(preacher: "Rev. J. Sample", source: "Lord's Day sermon").lines
            == ["Rev. J. Sample", "Lord's Day sermon"])
    }
}
