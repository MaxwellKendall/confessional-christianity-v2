// Geometric glyphs ported point-for-point from the design handoff's inline
// SVGs (18x18 viewBox) — not a stock icon set, per that handoff's "Assets"
// note. Each Shape normalizes to its `rect` so it scales cleanly at the
// mockup's 17x17 point size.
import SwiftUI

private struct CatechismsDot: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 18
        let r = 7 * s
        let center = CGPoint(x: rect.minX + 9 * s, y: rect.minY + 9 * s)
        var p = Path()
        p.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        return p
    }
}

/// `M9 2 C9 2 4 6 4 11 A5 5 0 0 0 14 11 C14 6 9 2 9 2 Z` — a pointed-top,
/// rounded-bottom dome/arch silhouette.
private struct DevotionsDome: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 18
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * s, y: rect.minY + y * s)
        }
        var p = Path()
        p.move(to: pt(9, 2))
        p.addCurve(to: pt(4, 11), control1: pt(9, 2), control2: pt(4, 6))
        p.addArc(center: pt(9, 11), radius: 5 * s, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addCurve(to: pt(9, 2), control1: pt(14, 6), control2: pt(9, 2))
        p.closeSubpath()
        return p
    }
}

/// Two quadrilaterals meeting at a center spine — an open book viewed from above.
private struct ReflectionsBook: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 18
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * s, y: rect.minY + y * s)
        }
        var p = Path()
        p.move(to: pt(2, 5)); p.addLine(to: pt(9, 2)); p.addLine(to: pt(9, 15)); p.addLine(to: pt(2, 12))
        p.closeSubpath()
        p.move(to: pt(16, 5)); p.addLine(to: pt(9, 2)); p.addLine(to: pt(9, 15)); p.addLine(to: pt(16, 12))
        p.closeSubpath()
        return p
    }
}

/// Three vertical spines/bars.
private struct LibraryBars: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 18
        func bar(_ x: CGFloat) -> CGRect {
            CGRect(x: rect.minX + x * s, y: rect.minY + 2 * s, width: 3 * s, height: 14 * s)
        }
        var p = Path()
        p.addRect(bar(3))
        p.addRect(bar(7.5))
        p.addRect(bar(12))
        return p
    }
}

struct TabIcon: View {
    let tab: RootTab
    let color: Color

    var body: some View {
        switch tab {
        case .catechisms:
            CatechismsDot().fill(color)
        case .devotions:
            DevotionsDome().stroke(color, lineWidth: 1.5)
        case .reflections:
            ReflectionsBook().stroke(color, lineWidth: 1.4)
        case .library:
            LibraryBars().stroke(color, lineWidth: 1.4)
        }
    }
}
