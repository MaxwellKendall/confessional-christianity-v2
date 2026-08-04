// Design tokens ported verbatim from the web app's src/app/globals.css
// ("Design tokens from the design handoff... final values, not
// placeholders — every screen draws from this theme; nothing hardcodes
// hex."). Keep this file in lockstep with globals.css if the web theme
// changes — nothing here should drift into an invented palette.
import SwiftUI

extension Color {
    // canvas is the page background only, never app chrome. Native app
    // chrome uses plain white here rather than the web's tan canvas — an
    // explicit on-device call, not a porting slip.
    static let ccCanvas = Color(hex: 0xffffff)
    // app/card background
    static let ccCard = Color(hex: 0xfaf9f6)
    // ink: primary / secondary-meta / tertiary-label text
    static let ccInk = Color(hex: 0x211e19)
    static let ccInk2 = Color(hex: 0x5c574c)
    static let ccInk3 = Color(hex: 0x8a8378)
    // hairline borders
    static let ccHairline = Color(hex: 0xddd8cd)
    static let ccHairline2 = Color(hex: 0xe2ddd0)
    // subtle fill (cards, active rows)
    static let ccFill = Color(hex: 0xf4f2ea)
    // muted border / dotted accents
    static let ccMuted = Color(hex: 0xc9c4b6)
    // ochre: the app's one departure from monochrome, scoped strictly to
    // progress bars and the "mastered" heart state.
    static let ccOchre = Color(hex: 0xab7e2e)
    // the "reviewing" heart tone sits between muted and ochre
    static let ccHeartReviewing = Color(hex: 0xc9a468)
    // the devotions library's one deep accent
    static let ccFeatured = Color(hex: 0x3d4f47)
    static let ccFeaturedInk = Color(hex: 0xd8ddd8)
    // the floating tab bar's selected-pill fill
    static let ccTabSelected = Color(hex: 0xede7d8)

    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255
        )
    }
}

// Re-declared as ShapeStyle statics (Self == Color) so implicit-member
// syntax resolves in generic ShapeStyle contexts too — e.g.
// `.foregroundStyle(.ccInk)`, `.fill(.ccOchre)`. Without this, only the
// concrete `Color.ccInk` spelling would type-check (the same reason
// SwiftUI's own `.red`/`.blue` work in both contexts).
extension ShapeStyle where Self == Color {
    static var ccCanvas: Color { .ccCanvas }
    static var ccCard: Color { .ccCard }
    static var ccInk: Color { .ccInk }
    static var ccInk2: Color { .ccInk2 }
    static var ccInk3: Color { .ccInk3 }
    static var ccHairline: Color { .ccHairline }
    static var ccHairline2: Color { .ccHairline2 }
    static var ccFill: Color { .ccFill }
    static var ccMuted: Color { .ccMuted }
    static var ccOchre: Color { .ccOchre }
    static var ccHeartReviewing: Color { .ccHeartReviewing }
    static var ccFeatured: Color { .ccFeatured }
    static var ccFeaturedInk: Color { .ccFeaturedInk }
    static var ccTabSelected: Color { .ccTabSelected }
}

// Cinzel: display/labels (tracked uppercase). Marcellus: body/reading.
extension Font {
    static func ccDisplay(_ size: CGFloat, semibold: Bool = false) -> Font {
        .custom(semibold ? "Cinzel-SemiBold" : "Cinzel-Regular", size: size)
    }

    static func ccBody(_ size: CGFloat) -> Font {
        .custom("Marcellus-Regular", size: size)
    }
}

// Tracked small-caps label — the recurring Cinzel treatment used
// everywhere as section eyebrows, footer buttons, and metadata.
struct LabelCaps: ViewModifier {
    var size: CGFloat = 10
    var tracking: CGFloat = 0.12
    var color: Color = .ccInk3

    func body(content: Content) -> some View {
        content
            .font(.ccDisplay(size))
            .tracking(size * tracking)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

extension View {
    func labelCaps(size: CGFloat = 10, tracking: CGFloat = 0.12, color: Color = .ccInk3) -> some View {
        modifier(LabelCaps(size: size, tracking: tracking, color: color))
    }

    /// The quiet dotted-underline treatment used for tertiary actions and
    /// links (Prev/Next, "Back to the Question", "See Milestones →"...) —
    /// mirrors `border-bottom: 1px dotted` from globals.css.
    func dottedUnderline(_ color: Color, offset: CGFloat = 3) -> some View {
        overlay(alignment: .bottom) {
            DottedLine(color: color).offset(y: offset)
        }
    }
}

private struct DottedLine: View {
    var color: Color

    var body: some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: geo.size.width, y: 0))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1, dash: [1.5, 2.5]))
        }
        .frame(height: 1)
    }
}

// Shared display scale: page title > section title.
struct HeadingPage: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.ccDisplay(19, semibold: true)).foregroundStyle(.ccInk)
    }
}

struct HeadingSection: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.ccDisplay(17, semibold: true)).foregroundStyle(.ccInk)
    }
}

extension View {
    func headingPage() -> some View { modifier(HeadingPage()) }
    func headingSection() -> some View { modifier(HeadingSection()) }
}
