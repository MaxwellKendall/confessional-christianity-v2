import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import DomainKit

/// Snapshot images for every format × palette.
///
/// - `Fixtures/QuoteCard/native/<format>-<palette index>.png`: the renderer's
///   own output, checked in. Re-record with `QUOTE_CARD_RECORD=1 swift test`.
/// - `Fixtures/QuoteCard/prototype/<format>-<palette index>.png`: the approved
///   TKL-840 prototype's card code rendered by headless Chrome
///   (`scripts/quote-card-prototype/render.sh`), same content and palette.
///
/// Card i uses palette i and sample `i % 7`, so every format shows every
/// palette and every kind of card (drop cap, catechism Q&A, verse lead-in).
@Suite(.serialized) struct QuoteCardSnapshotTests {
    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/QuoteCard")
    static let cases: [(QuoteCardFormat, Int)] = QuoteCardFormat.allCases.flatMap { f in
        QuoteCardPalette.all.indices.map { (f, $0) }
    }

    static func render(_ format: QuoteCardFormat, _ i: Int) -> CGImage? {
        QuoteCardRenderer.render(QuoteCardSamples.all[i % QuoteCardSamples.all.count],
                                 palette: QuoteCardPalette.all[i], format: format)
    }

    static func url(_ kind: String, _ format: QuoteCardFormat, _ i: Int) -> URL {
        fixtures.appendingPathComponent("\(kind)/\(format.rawValue)-\(i).png")
    }

    @Test func nativeSnapshotsMatchTheCheckedInImages() throws {
        let record = ProcessInfo.processInfo.environment["QUOTE_CARD_RECORD"] == "1"
        var recorded: [String] = []
        for (format, i) in Self.cases {
            let image = try #require(Self.render(format, i))
            let url = Self.url("native", format, i)
            if record || !FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try #require(QuoteCardRenderer.pngData(image)).write(to: url)
                recorded.append(url.lastPathComponent)
                continue
            }
            let expected = try #require(Pixels(url: url))
            let actual = Pixels(image)
            #expect(actual.width == expected.width && actual.height == expected.height)
            let diff = actual.fractionDiffering(from: expected, threshold: 24)
            #expect(diff < 0.002, "\(url.lastPathComponent): \(diff * 100)% of pixels differ")
        }
        #expect(recorded.isEmpty, "recorded \(recorded.count) snapshots; run again to compare")
    }

    /// Native vs prototype: same size, and a coarse (40px-block) colour
    /// comparison that is sensitive to palette, frame, gradient and where the
    /// type sits, but not to sub-pixel font rasterisation differences.
    @Test func nativeCardsMatchThePrototypeImages() throws {
        var worst = 0.0
        for (format, i) in Self.cases {
            let native = Pixels(try #require(Self.render(format, i)))
            let proto = try #require(Pixels(url: Self.url("prototype", format, i)))
            #expect(native.width == proto.width && native.height == proto.height,
                    "\(format)-\(i): \(native.width)x\(native.height) vs prototype \(proto.width)x\(proto.height)")
            let d = native.blockDistance(to: proto, block: 40)
            worst = max(worst, d)
            print("quote-card: \(format)-\(i) distance \(d)")
            #expect(d < Self.prototypeTolerance, "\(format)-\(i): distance \(d) from the prototype")
        }
        print("quote-card: worst native-vs-prototype block distance \(worst)")
    }

    /// The comparison above must be able to fail: a card in the wrong palette,
    /// or with different words, is far from its prototype.
    @Test func prototypeComparisonRejectsTheWrongCard() throws {
        for format in QuoteCardFormat.allCases {
            let proto = try #require(Pixels(url: Self.url("prototype", format, 0)))
            let wrongPalette = Pixels(try #require(QuoteCardRenderer.render(
                QuoteCardSamples.all[0], palette: .lectern, format: format)))
            let dp = wrongPalette.blockDistance(to: proto, block: 40)
            print("quote-card: \(format) wrong palette distance \(dp)")
            #expect(dp > Self.prototypeTolerance * 1.5, "\(format) palette")
            let wrongWords = Pixels(try #require(QuoteCardRenderer.render(
                QuoteCardSamples.all[3], palette: .vellum, format: format)))
            let dw = wrongWords.blockDistance(to: proto, block: 40)
            print("quote-card: \(format) wrong words distance \(dw)")
            #expect(dw > Self.prototypeTolerance, "\(format) words")
        }
    }

    static let prototypeTolerance = 0.008
}

/// RGBA8 pixels, for comparing images.
struct Pixels {
    let width: Int, height: Int
    let bytes: [UInt8]

    /// Draws `image` into an sRGB buffer, optionally downscaled with
    /// high-quality (area-averaging) interpolation.
    init(_ image: CGImage, width: Int? = nil, height: Int? = nil) {
        let w = width ?? image.width, h = height ?? image.height
        self.width = w; self.height = h
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        buf.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        bytes = buf
        self.image = image
    }

    private let image: CGImage

    init?(url: URL) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        self.init(image)
    }

    func fractionDiffering(from other: Pixels, threshold: Int) -> Double {
        guard bytes.count == other.bytes.count else { return 1 }
        var n = 0
        bytes.withUnsafeBufferPointer { a in
            other.bytes.withUnsafeBufferPointer { b in
                var i = 0
                while i < a.count {
                    if abs(Int(a[i]) - Int(b[i])) > threshold || abs(Int(a[i + 1]) - Int(b[i + 1])) > threshold
                        || abs(Int(a[i + 2]) - Int(b[i + 2])) > threshold { n += 1 }
                    i += 4
                }
            }
        }
        return Double(n) / Double(width * height)
    }

    /// Mean absolute difference (0...1) of RGB after downscaling both images
    /// so each output pixel averages a `block` × `block` area.
    func blockDistance(to other: Pixels, block: Int) -> Double {
        guard width == other.width, height == other.height else { return 1 }
        let w = max(1, width / block), h = max(1, height / block)
        let a = Pixels(image, width: w, height: h).bytes, b = Pixels(other.image, width: w, height: h).bytes
        var total = 0
        for i in stride(from: 0, to: a.count, by: 4) {
            total += abs(Int(a[i]) - Int(b[i])) + abs(Int(a[i + 1]) - Int(b[i + 1])) + abs(Int(a[i + 2]) - Int(b[i + 2]))
        }
        return Double(total) / Double(w * h * 3) / 255
    }
}
