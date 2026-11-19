import CoreGraphics
import CoreText
import Foundation

// Quotation cards for sharing (TKL-839). Matches the approved TKL-840
// prototype's Cards view: Cinzel and Marcellus, a drop cap (or a lead-in for
// Scripture), a hairline double frame, the quote-card house palettes and a
// quiet brand line with the short link.

public enum QuoteCard {
    /// The editor's hard stop: above this many words, Share is disabled.
    public static let maximumWords = 70
    /// What a card shows when it has no public link (Save Image).
    public static let bareDomain = "confessionalchristianity.com"

    /// Words the type is sized from: the quote, plus a verse's lead-in.
    public static func wordCount(_ content: QuoteCardContent) -> Int {
        var n = words(content.text)
        if case .verse(let lead) = content.kind { n += words(lead) }
        return n
    }

    static func words(_ s: String) -> Int { s.split(whereSeparator: \.isWhitespace).count }
}

public enum QuoteCardFormat: String, CaseIterable, Sendable, CustomStringConvertible {
    /// Posts and Messages, 1080 × 1080.
    case square
    /// Instagram and WhatsApp stories, 1080 × 1920.
    case story
    /// The /q/ page's Open Graph image, 1200 × 630 (1.91:1).
    case linkPreview

    public var description: String { rawValue }

    public var size: CGSize {
        switch self {
        case .square: CGSize(width: 1080, height: 1080)
        case .story: CGSize(width: 1080, height: 1920)
        case .linkPreview: CGSize(width: 1200, height: 630)
        }
    }

    /// The editor's "reads well" limit, in words.
    public var legibleWordLimit: Int { self == .story ? 55 : 45 }

    /// Story cards keep all text out of Instagram's UI: the top 250px and bottom 300px.
    public static let storySafeTop: CGFloat = 250
    public static let storySafeBottom: CGFloat = 300

    // Geometry from the prototype (native px). The story's brand line moves
    // up from the prototype's 268px to clear the 300px safe zone, and its
    // body ends 30px higher to keep the prototype's gap above the brand line.
    var bodyTop: CGFloat { switch self { case .square: 96; case .story: 250; case .linkPreview: 60 } }
    var bodyBottom: CGFloat { switch self { case .square: 130; case .story: 362; case .linkPreview: 96 } }
    var bodySide: CGFloat { self == .linkPreview ? 110 : 130 }
    var footerBottom: CGFloat { switch self { case .square: 66; case .story: 304; case .linkPreview: 56 } }
    var brandSize: CGFloat { self == .linkPreview ? 15 : 17 }
    var hasOrnament: Bool { self != .linkPreview }

    /// Starting type size before fitting (the prototype's `baseFs`).
    func baseFontSize(words n: Int) -> CGFloat {
        func clamp(_ lo: Double, _ v: Double, _ hi: Double) -> Double { max(lo, min(hi, v)) }
        let n = Double(n)
        let v: Double = switch self {
        case .story: clamp(40, 98 - n * 1.1, 84)
        case .linkPreview: clamp(28, 66 - n * 0.8, 58)
        case .square: clamp(36, 92 - n * 1.2, 78)
        }
        return CGFloat(v.rounded())
    }
}

/// Colours as 0xRRGGBB. The house palettes from the quote-card skill, unchanged.
public struct QuoteCardPalette: Hashable, Sendable {
    public let name: String
    public let field, edge, ink, accent, muted, frame: UInt32

    public static let vellum = Self(name: "vellum", field: 0xF3EAD8, edge: 0xE6D8BC, ink: 0x2A2119, accent: 0x7B2323, muted: 0x7C6A55, frame: 0xB9A27F)
    public static let psalter = Self(name: "psalter", field: 0x1C2333, edge: 0x121826, ink: 0xECE3CF, accent: 0xC9A45C, muted: 0x9AA3B5, frame: 0x4A5570)
    public static let cloister = Self(name: "cloister", field: 0xE5E8DF, edge: 0xD3D8CB, ink: 0x253029, accent: 0x4B6B50, muted: 0x66756A, frame: 0xA5B2A2)
    public static let vespers = Self(name: "vespers", field: 0x3B1619, edge: 0x280D10, ink: 0xF2E7D6, accent: 0xD8B46A, muted: 0xC9A9A0, frame: 0x6E3A3C)
    public static let hymnal = Self(name: "hymnal", field: 0x1D3529, edge: 0x12241B, ink: 0xECE4CF, accent: 0xC8A65A, muted: 0xA3B2A6, frame: 0x3F5A4B)
    public static let lectern = Self(name: "lectern", field: 0xFBF9F4, edge: 0xEFEBE1, ink: 0x17140F, accent: 0x8A6A3A, muted: 0x80776A, frame: 0xD2C7B3)
    public static let ironstone = Self(name: "ironstone", field: 0xF5F3EE, edge: 0xE6E3DA, ink: 0x1B2640, accent: 0x2C4A80, muted: 0x6A7286, frame: 0xC3C8D4)
    public static let ember = Self(name: "ember", field: 0x262422, edge: 0x1A1817, ink: 0xEEE7DC, accent: 0xD29A4E, muted: 0xA29A8F, frame: 0x4C4640)
    public static let puritan = Self(name: "puritan", field: 0x171615, edge: 0x0D0C0C, ink: 0xECE7DC, accent: 0xC9A45C, muted: 0x8F8A80, frame: 0x3D3A36)

    public static let all: [QuoteCardPalette] = [vellum, psalter, cloister, vespers, hymnal, lectern, ironstone, ember, puritan]

    public static func named(_ name: String) -> QuoteCardPalette? { all.first { $0.name == name } }
}

/// Who said it. Every field is optional; empty fields are left off the card,
/// never replaced with a placeholder.
public struct QuoteCardAttribution: Hashable, Sendable {
    public var preacher, church, passage, date: String?
    /// A source label, e.g. "Westminster Shorter Catechism" or "Thomas Watson".
    public var source: String?
    /// A detail under the source, e.g. "Question 1" or "Chapter 21 · Section 7".
    public var detail: String?

    public init(preacher: String? = nil, church: String? = nil, passage: String? = nil, date: String? = nil,
                source: String? = nil, detail: String? = nil) {
        self.preacher = preacher; self.church = church; self.passage = passage; self.date = date
        self.source = source; self.detail = detail
    }

    /// The lines the card draws: the speaker or source (gilt, with rules), then
    /// the remaining fields joined with " · ". Zero, one or two lines.
    public var lines: [String] {
        func clean(_ s: String?) -> String? {
            guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
            return t
        }
        var rest = [clean(preacher), clean(source), clean(detail), clean(church), clean(passage), clean(date)]
        // The primary line is the first of preacher, source, passage.
        guard let primaryIndex = [0, 1, 4].first(where: { rest[$0] != nil }) else {
            let others = rest.compactMap { $0 }
            return others.isEmpty ? [] : [others.joined(separator: " · ")]
        }
        let primary = rest[primaryIndex]!
        rest[primaryIndex] = nil
        let secondary = rest.compactMap { $0 }
        return secondary.isEmpty ? [primary] : [primary, secondary.joined(separator: " · ")]
    }
}

public enum QuoteCardKind: Hashable, Sendable {
    /// A quotation: opens with a drop cap and a small-caps run-in.
    case quote
    /// A catechism answer: the question sits above it.
    case questionAndAnswer(question: String)
    /// Scripture: opens with a gilt lead-in clause instead of a drop cap.
    case verse(lead: String)
}

public struct QuoteCardContent: Hashable, Sendable {
    public var text: String
    public var kind: QuoteCardKind
    public var attribution: QuoteCardAttribution
    /// The short link shown bottom right, e.g. "confessionalchristianity.com/q/7kd2".
    public var link: String

    public init(text: String, kind: QuoteCardKind = .quote, attribution: QuoteCardAttribution = .init(),
                link: String = QuoteCard.bareDomain) {
        self.text = text; self.kind = kind; self.attribution = attribution; self.link = link
    }
}

/// Cinzel and Marcellus, bundled with DomainKit and loaded without registering
/// them process-wide, so rendering is pure.
enum QuoteCardFonts {
    static let cinzel = load("Cinzel-Regular")
    static let cinzelSemiBold = load("Cinzel-SemiBold")
    static let marcellus = load("Marcellus-Regular")

    static var postScriptNames: [String] {
        [cinzel, cinzelSemiBold, marcellus].compactMap { $0.postScriptName as String? }
    }

    private static func load(_ name: String) -> CGFont {
        guard let url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "QuoteCardFonts"),
              let provider = CGDataProvider(url: url as CFURL),
              let font = CGFont(provider) else {
            fatalError("DomainKit is missing its bundled font \(name).ttf")
        }
        return font
    }

    static func font(_ font: CGFont, _ size: CGFloat) -> CTFont {
        CTFontCreateWithGraphicsFont(font, size, nil, nil)
    }
}
