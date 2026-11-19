import CoreGraphics
import CoreText
import Foundation
import ImageIO

/// Draws a quotation card. Pure: no UI, no global font registration, no I/O;
/// the same input gives the same pixels.
public enum QuoteCardRenderer {
    /// The card as an sRGB image at the format's exact pixel size.
    public static func render(_ content: QuoteCardContent, palette: QuoteCardPalette,
                              format: QuoteCardFormat) -> CGImage? {
        draw(QuoteCardLayout(content, format: format, palette: palette))
    }

    /// The card as PNG data, ready for the share sheet or Save Image.
    public static func pngData(_ content: QuoteCardContent, palette: QuoteCardPalette,
                               format: QuoteCardFormat) -> Data? {
        render(content, palette: palette, format: format).flatMap(pngData)
    }

    public static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    public static func draw(_ layout: QuoteCardLayout) -> CGImage? {
        let size = layout.format.size
        let w = Int(size.width), h = Int(size.height)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let p = layout.palette
        let H = size.height
        func flip(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: H - r.maxY, width: r.width, height: r.height) }

        // Background: radial-gradient(ellipse at 50% 38%, field 0, edge 120%), farthest-corner.
        ctx.setFillColor(Text.color(p.edge))
        ctx.fill(CGRect(origin: .zero, size: size))
        if let gradient = CGGradient(colorsSpace: space, colors: [Text.color(p.field), Text.color(p.edge)] as CFArray,
                                     locations: [0, 1]) {
            ctx.saveGState()
            ctx.translateBy(x: size.width / 2, y: H - 0.38 * H)
            ctx.scaleBy(x: 2.0.squareRoot() * size.width / 2, y: 2.0.squareRoot() * 0.62 * H)
            ctx.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1.2,
                                   options: [.drawsAfterEndLocation])
            ctx.restoreGState()
        }

        // Hairline double frame: 1.5px at 34px, and a fainter one 8px inside it.
        ctx.setLineWidth(1.5)
        ctx.setStrokeColor(Text.color(p.frame))
        ctx.stroke(CGRect(origin: .zero, size: size).insetBy(dx: 34.75, dy: 34.75))
        ctx.setStrokeColor(Text.color(p.frame, alpha: 0.55))
        ctx.stroke(CGRect(origin: .zero, size: size).insetBy(dx: 44.25, dy: 44.25))

        for shape in layout.shapes {
            switch shape {
            case let .rule(r, color, alpha):
                ctx.setFillColor(Text.color(color, alpha: alpha))
                ctx.fill(flip(r))
            case let .diamond(c, side, color):
                let r = side / 2.0.squareRoot()
                let cy = H - c.y
                ctx.setFillColor(Text.color(color))
                ctx.beginPath()
                ctx.move(to: CGPoint(x: c.x, y: cy + r))
                ctx.addLine(to: CGPoint(x: c.x + r, y: cy))
                ctx.addLine(to: CGPoint(x: c.x, y: cy - r))
                ctx.addLine(to: CGPoint(x: c.x - r, y: cy))
                ctx.closePath()
                ctx.fillPath()
            }
        }

        ctx.textMatrix = .identity
        for item in layout.textItems {
            ctx.textPosition = CGPoint(x: item.origin.x, y: H - item.origin.y)
            CTLineDraw(item.line, ctx)
        }
        return ctx.makeImage()
    }
}
