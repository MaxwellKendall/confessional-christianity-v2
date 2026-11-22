// Glyphs ported from TKL-885's prototype SVGs (24x24 viewBox): a sun for
// Today, an open book for Catechism, a church for the Lord's Day, and the
// avatar's person. Each Shape normalizes to its `rect`, and line widths are in
// viewBox units so they scale with it, as in SVG.
import SwiftUI

private extension CGRect {
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: minX + x * width / 24, y: minY + y * height / 24)
    }
}

private struct TodaySun: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let s = r.width / 24
        p.addEllipse(in: CGRect(x: r.minX + 8 * s, y: r.minY + 8 * s, width: 8 * s, height: 8 * s))
        let rays: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (12, 2, 12, 5), (12, 19, 12, 22), (2, 12, 5, 12), (19, 12, 22, 12),
            (4.9, 4.9, 7, 7), (17, 17, 19.1, 19.1), (4.9, 19.1, 7, 17), (17, 7, 19.1, 4.9),
        ]
        for (x1, y1, x2, y2) in rays {
            p.move(to: r.pt(x1, y1)); p.addLine(to: r.pt(x2, y2))
        }
        return p
    }
}

private struct CatechismBook: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: r.pt(4, 5.5))
        p.addCurve(to: r.pt(5.5, 4), control1: r.pt(4, 4.7), control2: r.pt(4.7, 4))
        p.addLine(to: r.pt(11, 4)); p.addLine(to: r.pt(11, 20)); p.addLine(to: r.pt(5.5, 20))
        p.addQuadCurve(to: r.pt(4, 18.5), control: r.pt(4, 20))
        p.closeSubpath()
        p.move(to: r.pt(20, 5.5))
        p.addCurve(to: r.pt(18.5, 4), control1: r.pt(20, 4.7), control2: r.pt(19.3, 4))
        p.addLine(to: r.pt(13, 4)); p.addLine(to: r.pt(13, 20)); p.addLine(to: r.pt(18.5, 20))
        p.addCurve(to: r.pt(20, 18.5), control1: r.pt(19.3, 20), control2: r.pt(20, 19.3))
        p.closeSubpath()
        return p
    }
}

private struct LordsDayChurch: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: r.pt(12, 3)); p.addLine(to: r.pt(12, 9))
        p.move(to: r.pt(9, 6)); p.addLine(to: r.pt(15, 6))
        p.move(to: r.pt(6, 21)); p.addLine(to: r.pt(6, 12)); p.addLine(to: r.pt(12, 9))
        p.addLine(to: r.pt(18, 12)); p.addLine(to: r.pt(18, 21))
        p.move(to: r.pt(10, 21)); p.addLine(to: r.pt(10, 17)); p.addLine(to: r.pt(14, 17)); p.addLine(to: r.pt(14, 21))
        return p
    }
}

private struct Person: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let s = r.width / 24
        p.addEllipse(in: CGRect(x: r.minX + 8.5 * s, y: r.minY + 5.5 * s, width: 7 * s, height: 7 * s))
        p.move(to: r.pt(5, 20))
        p.addCurve(to: r.pt(12, 15), control1: r.pt(6.5, 16.5), control2: r.pt(9, 15))
        p.addCurve(to: r.pt(19, 20), control1: r.pt(15, 15), control2: r.pt(17.5, 16.5))
        return p
    }
}

private struct Glyph<S: Shape>: View {
    let shape: S
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        GeometryReader { geo in
            shape.stroke(color, style: StrokeStyle(lineWidth: lineWidth * geo.size.width / 24))
        }
        .accessibilityHidden(true)
    }
}

struct TabIcon: View {
    let tab: RootTab
    let color: Color
    var lineWidth: CGFloat = 1.7

    var body: some View {
        switch tab {
        case .today: Glyph(shape: TodaySun(), color: color, lineWidth: lineWidth)
        case .catechism: Glyph(shape: CatechismBook(), color: color, lineWidth: lineWidth)
        case .lordsDay: Glyph(shape: LordsDayChurch(), color: color, lineWidth: lineWidth)
        }
    }
}

struct PersonIcon: View {
    let color: Color

    var body: some View {
        Glyph(shape: Person(), color: color, lineWidth: 1.8)
    }
}
