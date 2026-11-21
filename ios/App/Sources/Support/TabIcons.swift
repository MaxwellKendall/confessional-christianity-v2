// Tab glyphs ported from TKL-885's prototype SVGs (24x24 viewBox, 1.8pt
// stroke): a sun for Today, an open book for Catechism, a church for the
// Lord's Day. Each Shape normalizes to its `rect`.
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
        p.move(to: r.pt(4, 5.5)); p.addLine(to: r.pt(4, 18.5)); p.addLine(to: r.pt(5.5, 20))
        p.addLine(to: r.pt(11, 20)); p.addLine(to: r.pt(11, 4)); p.addLine(to: r.pt(5.5, 4)); p.closeSubpath()
        p.move(to: r.pt(20, 5.5)); p.addLine(to: r.pt(20, 18.5)); p.addLine(to: r.pt(18.5, 20))
        p.addLine(to: r.pt(13, 20)); p.addLine(to: r.pt(13, 4)); p.addLine(to: r.pt(18.5, 4)); p.closeSubpath()
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

struct TabIcon: View {
    let tab: RootTab
    let color: Color

    var body: some View {
        let style = StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
        switch tab {
        case .today: TodaySun().stroke(color, style: style)
        case .catechism: CatechismBook().stroke(color, style: style)
        case .lordsDay: LordsDayChurch().stroke(color, style: style)
        }
    }
}
