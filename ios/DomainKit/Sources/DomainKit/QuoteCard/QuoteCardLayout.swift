import CoreGraphics
import CoreText
import Foundation

/// Where everything on a card goes, in card pixels with the origin at the top
/// left. Pure: the same content, format and palette always give the same
/// layout. `QuoteCardRenderer` draws it.
///
/// Type sizing follows the prototype: start from a size chosen by word count,
/// then step down 5% at a time until the body (ornament, question, quote and
/// attribution) fits its region with no word split across lines.
public struct QuoteCardLayout {
    public enum Role: Sendable { case question, dropCap, quote, attribution, footer }

    public struct TextItem {
        public let text: String
        public let role: Role
        /// The drawn line's bounds (the drop cap's are its ink bounds).
        public let frame: CGRect
        let line: CTLine
        /// Baseline origin, top-left coordinates.
        let origin: CGPoint
    }

    enum Shape {
        case rule(CGRect, color: UInt32, alpha: CGFloat)
        case diamond(center: CGPoint, side: CGFloat, color: UInt32)
    }

    public let format: QuoteCardFormat
    public let palette: QuoteCardPalette
    /// The quote's final type size, in px.
    public let fontSize: CGFloat
    public let bodyRegion: CGRect
    public let bodyContentHeight: CGFloat
    public let brokeWordMidLine: Bool
    public var fits: Bool { bodyContentHeight <= bodyRegion.height + 0.5 && !brokeWordMidLine }
    public let textItems: [TextItem]
    let shapes: [Shape]

    public init(_ content: QuoteCardContent, format: QuoteCardFormat, palette: QuoteCardPalette = .vellum) {
        let size = format.size
        let region = CGRect(x: format.bodySide, y: format.bodyTop,
                            width: size.width - 2 * format.bodySide,
                            height: size.height - format.bodyTop - format.bodyBottom)
        var fs = format.baseFontSize(words: QuoteCard.wordCount(content))
        var body = Body(content, palette: palette, format: format, fontSize: fs, width: region.width)
        var steps = 0
        while (body.height > region.height + 0.5 || body.brokeWord) && fs > 8 && steps < 80 {
            fs = min(fs - 1, (fs * 0.95).rounded())
            body = Body(content, palette: palette, format: format, fontSize: fs, width: region.width)
            steps += 1
        }
        // Centre the body vertically in its region.
        let dy = region.minY + (region.height - body.height) / 2
        let dx = region.minX
        func move(_ r: CGRect) -> CGRect { r.offsetBy(dx: dx, dy: dy) }
        var items = body.items.map {
            TextItem(text: $0.text, role: $0.role, frame: move($0.frame), line: $0.line,
                     origin: CGPoint(x: $0.origin.x + dx, y: $0.origin.y + dy))
        }
        var shapes: [Shape] = body.shapes.map {
            switch $0 {
            case let .rule(r, c, a): .rule(move(r), color: c, alpha: a)
            case let .diamond(p, s, c): .diamond(center: CGPoint(x: p.x + dx, y: p.y + dy), side: s, color: c)
            }
        }
        let footer = Self.footer(content, format: format, palette: palette)
        items += footer.items
        shapes += footer.shapes

        self.format = format
        self.palette = palette
        self.fontSize = fs
        self.bodyRegion = region
        self.bodyContentHeight = body.height
        self.brokeWordMidLine = body.brokeWord
        self.textItems = items
        self.shapes = shapes
    }

    // MARK: - Footer: mark + "Confessional Christianity" left, short link right

    private static func footer(_ content: QuoteCardContent, format: QuoteCardFormat,
                               palette: QuoteCardPalette) -> (items: [TextItem], shapes: [Shape]) {
        let size = format.size
        let brandFont = QuoteCardFonts.font(QuoteCardFonts.cinzel, format.brandSize)
        let linkFont = QuoteCardFonts.font(QuoteCardFonts.marcellus, 19)
        let brand = Text.line("CONFESSIONAL CHRISTIANITY", brandFont, palette.muted, kern: 0.2 * format.brandSize)
        let link = Text.line(content.link, linkFont, palette.muted, kern: 0.06 * 19)
        let rowHeight = max(Text.normalLineHeight(brandFont), Text.normalLineHeight(linkFont))
        let rowTop = size.height - format.footerBottom - rowHeight
        let left: CGFloat = 64, right = size.width - 64

        func baseline(_ font: CTFont) -> CGFloat {
            let h = Text.normalLineHeight(font)
            return rowTop + (rowHeight - h) / 2 + CTFontGetLeading(font) / 2 + CTFontGetAscent(font)
        }
        let diamondSide: CGFloat = 7, gap: CGFloat = 10
        let brandX = left + diamondSide + gap
        let brandBase = baseline(brandFont)
        let linkWidth = Text.width(link)
        let linkBase = baseline(linkFont)
        let brandItem = TextItem(text: "CONFESSIONAL CHRISTIANITY", role: .footer,
                                 frame: Text.frame(brand, x: brandX, baseline: brandBase),
                                 line: brand, origin: CGPoint(x: brandX, y: brandBase))
        let linkItem = TextItem(text: content.link, role: .footer,
                                frame: Text.frame(link, x: right - linkWidth, baseline: linkBase),
                                line: link, origin: CGPoint(x: right - linkWidth, y: linkBase))
        let brandMid = rowTop + rowHeight / 2
        return ([brandItem, linkItem],
                [.diamond(center: CGPoint(x: left + diamondSide / 2, y: brandMid), side: diamondSide, color: palette.muted)])
    }
}

// MARK: - Body: ornament, question, quote, attribution (laid out from y = 0)

private struct Body {
    struct Item { let text: String; let role: QuoteCardLayout.Role; let frame: CGRect; let line: CTLine; let origin: CGPoint }
    var items: [Item] = []
    var shapes: [QuoteCardLayout.Shape] = []
    var height: CGFloat = 0
    var brokeWord = false

    init(_ content: QuoteCardContent, palette p: QuoteCardPalette, format: QuoteCardFormat, fontSize fs: CGFloat, width w: CGFloat) {
        var y: CGFloat = 0

        // Ornament: rule, diamond, rule, left aligned.
        if format.hasOrnament {
            shapes.append(.rule(CGRect(x: 0, y: 3.75, width: 40, height: 1.5), color: p.accent, alpha: 0.7))
            shapes.append(.diamond(center: CGPoint(x: 54.5, y: 4.5), side: 9, color: p.accent))
            shapes.append(.rule(CGRect(x: 69, y: 3.75, width: 40, height: 1.5), color: p.accent, alpha: 0.7))
            y += 9 + 0.55 * fs
        }

        // Catechism question above the answer.
        if case .questionAndAnswer(let question) = content.kind,
           !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let qs = 0.42 * fs
            let font = QuoteCardFonts.font(QuoteCardFonts.cinzel, qs)
            let s = NSMutableAttributedString()
            s.append(Text.attributed("Q.", font, p.accent, kern: 0.12 * qs))
            s.append(Text.attributed(" ", font, p.accent, kern: 0.25 * qs))
            s.append(Text.attributed(question.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                                     font, p.muted, kern: 0.12 * qs))
            let lh = 1.5 * qs
            let wrapped = Text.wrap(s, width: { _ in w })
            brokeWord = brokeWord || wrapped.brokeWord
            for (i, l) in wrapped.lines.enumerated() {
                let base = y + CGFloat(i) * lh + Text.halfLeadingBaseline(font, lineHeight: lh)
                items.append(Item(text: l.text, role: .question, frame: Text.frame(l.line, x: 0, baseline: base),
                                  line: l.line, origin: CGPoint(x: 0, y: base)))
            }
            y += CGFloat(wrapped.lines.count) * lh + 0.5 * fs
        }

        // The quote.
        let body = QuoteCardFonts.font(QuoteCardFonts.marcellus, fs)
        let lh = 1.36 * fs
        let para = NSMutableAttributedString()
        var indent: CGFloat = 0, floatBottom: CGFloat = 0
        let text = content.text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch content.kind {
        case .verse(let lead):
            let leadText = lead.trimmingCharacters(in: .whitespacesAndNewlines)
            if !leadText.isEmpty {
                let ls = 1.32 * fs
                para.append(Text.attributed(leadText.uppercased(), QuoteCardFonts.font(QuoteCardFonts.cinzel, ls),
                                            p.accent, kern: 0.03 * ls))
                para.append(Text.attributed(" ", body, p.ink))
            }
            para.append(Text.smallCapsLord(text, font: body, size: fs, color: p.ink))
        case .quote, .questionAndAnswer:
            if let split = Text.dropCapSplit(text) {
                let ds = 3.3 * fs
                let dropFont = QuoteCardFonts.font(QuoteCardFonts.cinzel, ds)
                let drop = Text.line(split.drop, dropFont, p.accent)
                let boxTop = y + 0.1 * fs, boxHeight = 0.8 * ds
                let base = boxTop + Text.halfLeadingBaseline(dropFont, lineHeight: boxHeight)
                let x = -0.04 * ds
                let ink = CTLineGetBoundsWithOptions(drop, .useGlyphPathBounds)
                let inkFrame = CGRect(x: x + ink.minX, y: base - ink.maxY, width: ink.width, height: ink.height)
                items.append(Item(text: split.drop, role: .dropCap, frame: inkFrame, line: drop, origin: CGPoint(x: x, y: base)))
                indent = x + Text.width(drop) + 0.16 * fs
                floatBottom = 0.1 * fs + boxHeight
                if !split.runIn.isEmpty {
                    let rs = 0.8 * fs
                    para.append(Text.attributed(split.runIn.uppercased(), QuoteCardFonts.font(QuoteCardFonts.cinzel, rs),
                                                p.ink, kern: 0.06 * rs))
                    para.append(Text.attributed(split.rest, body, p.ink))
                } else {
                    para.append(Text.attributed(String(split.rest.drop(while: \.isWhitespace)), body, p.ink))
                }
            } else {
                para.append(Text.attributed(text, body, p.ink))
            }
        }
        let lineWidth = { (i: Int) in CGFloat(i) * lh < floatBottom ? w - indent : w }
        var wrapped = Text.wrap(para, width: lineWidth)
        // Like CSS `text-wrap: pretty` in the prototype: no single word alone
        // on the last line. Narrow the last one to three lines before it (never
        // adding a line) and keep whichever leaves the least squared slack in
        // those lines, so no line ends up stubby.
        let n = wrapped.lines.count
        if n >= 2, QuoteCard.words(wrapped.lines.last!.text) < 2 {
            var best: (score: CGFloat, wrap: (lines: [Text.WrappedLine], brokeWord: Bool))?
            let scored = max(0, n - 4)..<(n - 1)
            for k in 1...min(3, n - 1) {
                let first = n - 1 - k
                for f in stride(from: 0.98, through: 0.6, by: -0.02) {
                    let t = Text.wrap(para, width: { (first..<(n - 1)).contains($0) ? lineWidth($0) * f : lineWidth($0) })
                    guard t.lines.count == n, !t.brokeWord, QuoteCard.words(t.lines.last!.text) >= 2 else { continue }
                    let score = scored.reduce(CGFloat(0)) { s, i in
                        let slack = 1 - t.lines[i].width / lineWidth(i)
                        return s + slack * slack
                    }
                    if best == nil || score < best!.score { best = (score, t) }
                    break
                }
            }
            if let best { wrapped = best.wrap }
        }
        brokeWord = brokeWord || wrapped.brokeWord
        for (i, l) in wrapped.lines.enumerated() {
            let x = CGFloat(i) * lh < floatBottom ? indent : 0
            let base = y + CGFloat(i) * lh + Text.halfLeadingBaseline(body, lineHeight: lh)
            items.append(Item(text: l.text, role: .quote, frame: Text.frame(l.line, x: x, baseline: base),
                              line: l.line, origin: CGPoint(x: x, y: base)))
        }
        y += max(CGFloat(wrapped.lines.count) * lh, floatBottom)

        // Attribution, centred: the speaker or source in gilt between rules, then the rest.
        let lines = content.attribution.lines
        if !lines.isEmpty {
            y += 0.75 * fs
            let ws = max(22, 0.4 * fs)
            let whoFont = QuoteCardFonts.font(QuoteCardFonts.cinzelSemiBold, ws)
            let ruleW: CGFloat = 46, ruleGap: CGFloat = 22
            let whoAvail = w - 2 * (ruleW + ruleGap)
            let who = Text.wrap(Text.attributed(lines[0].uppercased(), whoFont, p.accent, kern: 0.16 * ws),
                                width: { _ in whoAvail })
            brokeWord = brokeWord || who.brokeWord
            let whoLH = Text.normalLineHeight(whoFont)
            let blockW = who.lines.count > 1 ? whoAvail : (who.lines.first?.width ?? 0)
            for (i, l) in who.lines.enumerated() {
                let x = (w - l.width) / 2
                let base = y + CGFloat(i) * whoLH + Text.halfLeadingBaseline(whoFont, lineHeight: whoLH)
                items.append(Item(text: l.text, role: .attribution, frame: Text.frame(l.line, x: x, baseline: base),
                                  line: l.line, origin: CGPoint(x: x, y: base)))
            }
            let whoH = CGFloat(who.lines.count) * whoLH
            let ruleY = y + whoH / 2 - 0.75
            shapes.append(.rule(CGRect(x: (w - blockW) / 2 - ruleGap - ruleW, y: ruleY, width: ruleW, height: 1.5),
                                color: p.accent, alpha: 0.6))
            shapes.append(.rule(CGRect(x: (w + blockW) / 2 + ruleGap, y: ruleY, width: ruleW, height: 1.5),
                                color: p.accent, alpha: 0.6))
            y += whoH

            if lines.count > 1 {
                y += 0.16 * fs
                let ss = max(17, 0.29 * fs)
                let srcFont = QuoteCardFonts.font(QuoteCardFonts.cinzel, ss)
                let src = Text.wrap(Text.attributed(lines[1].uppercased(), srcFont, p.muted, kern: 0.14 * ss),
                                    width: { _ in w })
                brokeWord = brokeWord || src.brokeWord
                let srcLH = Text.normalLineHeight(srcFont)
                for (i, l) in src.lines.enumerated() {
                    let x = (w - l.width) / 2
                    let base = y + CGFloat(i) * srcLH + Text.halfLeadingBaseline(srcFont, lineHeight: srcLH)
                    items.append(Item(text: l.text, role: .attribution, frame: Text.frame(l.line, x: x, baseline: base),
                                      line: l.line, origin: CGPoint(x: x, y: base)))
                }
                y += CGFloat(src.lines.count) * srcLH
            }
        }
        height = y
    }
}

// MARK: - CoreText helpers

enum Text {
    static func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    static func attributed(_ s: String, _ font: CTFont, _ hex: UInt32, kern: CGFloat = 0) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(hex),
            NSAttributedString.Key(kCTKernAttributeName as String): kern,
        ])
    }

    static func line(_ s: String, _ font: CTFont, _ hex: UInt32, kern: CGFloat = 0) -> CTLine {
        CTLineCreateWithAttributedString(attributed(s, font, hex, kern: kern))
    }

    /// Advance width without trailing whitespace.
    static func width(_ line: CTLine) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) - CGFloat(CTLineGetTrailingWhitespaceWidth(line))
    }

    static func frame(_ line: CTLine, x: CGFloat, baseline: CGFloat) -> CGRect {
        var ascent: CGFloat = 0, descent: CGFloat = 0
        _ = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        return CGRect(x: x, y: baseline - ascent, width: width(line), height: ascent + descent)
    }

    /// CSS `line-height: normal`.
    static func normalLineHeight(_ font: CTFont) -> CGFloat {
        CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
    }

    /// Baseline offset within a CSS line box of the given height (half-leading model).
    static func halfLeadingBaseline(_ font: CTFont, lineHeight: CGFloat) -> CGFloat {
        let a = CTFontGetAscent(font), d = CTFontGetDescent(font)
        return (lineHeight - (a + d)) / 2 + a
    }

    /// The prototype's split: the first letter becomes the drop cap, the rest
    /// of the first word a small-caps run-in. Preserve opening punctuation
    /// with the drop cap so it remains in the quotation.
    static func dropCapSplit(_ text: String) -> (drop: String, runIn: String, rest: String)? {
        func isWord(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }
        guard let first = text.firstIndex(where: isWord) else { return nil }
        let afterDrop = text.index(after: first)
        let runInEnd = text[afterDrop...].firstIndex { !(isWord($0) || $0 == "'" || $0 == "\u{2019}") } ?? text.endIndex
        return (String(text[..<afterDrop]), String(text[afterDrop..<runInEnd]), String(text[runInEnd...]))
    }

    /// Scripture's LORD set in small caps (synthesised: Marcellus has no smcp).
    static func smallCapsLord(_ text: String, font: CTFont, size: CGFloat, color hex: UInt32) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let small = CTFontCreateCopyWithAttributes(font, 0.72 * size, nil, nil)
        var rest = Substring(text)
        while let r = rest.range(of: "LORD") {
            out.append(attributed(String(rest[..<r.lowerBound]), font, hex))
            out.append(attributed("L", font, hex, kern: 0.04 * size))
            out.append(attributed("ORD", small, hex, kern: 0.04 * size))
            rest = rest[r.upperBound...]
        }
        out.append(attributed(String(rest), font, hex))
        return out
    }

    struct WrappedLine { let line: CTLine; let text: String; let width: CGFloat }

    /// Greedy line breaking at word boundaries. `brokeWord` is set when a word
    /// had to be split because it is wider than the line.
    static func wrap(_ s: NSAttributedString, width: (Int) -> CGFloat) -> (lines: [WrappedLine], brokeWord: Bool) {
        let ns = s.string as NSString
        let length = ns.length
        guard length > 0 else { return ([], false) }
        let typesetter = CTTypesetterCreateWithAttributedString(s)
        var lines: [WrappedLine] = []
        var start = 0, broke = false
        func isBreakable(_ c: unichar) -> Bool {
            guard let scalar = Unicode.Scalar(c) else { return false }
            return CharacterSet.whitespacesAndNewlines.contains(scalar) || "-\u{2010}\u{2013}\u{2014}/".unicodeScalars.contains(scalar)
        }
        while start < length {
            let w = width(lines.count)
            var count = CTTypesetterSuggestLineBreak(typesetter, start, Double(w))
            if count <= 0 { count = 1 }
            let end = start + count
            if end < length && !isBreakable(ns.character(at: end - 1)) && !isBreakable(ns.character(at: end)) {
                broke = true
            }
            let line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
            let lw = Self.width(line)
            if lw > w + 0.5 { broke = true }
            let text = ns.substring(with: NSRange(location: start, length: count)).trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append(WrappedLine(line: line, text: text, width: lw))
            start = end
        }
        return (lines, broke)
    }
}
