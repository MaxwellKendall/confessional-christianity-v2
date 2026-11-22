// The Chapel design system (TKL-938): the approved home and navigation
// prototype (TKL-885, committed at ios/scripts/prototype-shots/prototype.html)
// and the Linear document "Design tokens: Chapel (app 1.1)". Where they
// disagree the prototype wins. Every colour follows the light or dark
// setting; screens take colours, type and shapes from here, never a hex.
// Corners are circular, as the prototype draws them.
// scripts/ios/chapel-design.test.mjs holds the values to the prototype's.
// Also compiled into the widget, so nothing here may use app-only types.
import SwiftUI
import UIKit

// MARK: - Colour

extension Color {
    /// app background
    static let ccPaper = Color(light: 0xf5f5f1, dark: 0x121513)
    /// cards, sheets
    static let ccSurface = Color(light: 0xfcfcfa, dark: 0x1a1e1b)
    /// inputs, icon wells, quiet buttons
    static let ccFill = Color(light: 0xecede7, dark: 0x232823)
    /// hairlines
    static let ccLine = Color(light: 0xd9dbd2, dark: 0x2e342f)
    /// primary text
    static let ccInk = Color(light: 0x1c1f1c, dark: 0xebece6)
    /// secondary text
    static let ccInk2 = Color(light: 0x545a53, dark: 0xaeb4ac)
    /// labels, meta
    static let ccInk3 = Color(light: 0x858b83, dark: 0x7d847c)
    /// the primary action, Today's hero, the selected tab
    static let ccChapel = Color(light: 0x2e4a3e, dark: 0xa8c6b6)
    /// text on chapel
    static let ccOnChapel = Color(light: 0xf2f4ef, dark: 0x102019)
    /// progress and done marks only
    static let ccGilt = Color(light: 0xa67a2c, dark: 0xd3a654)
    /// destructive text
    static let ccDanger = Color(light: 0x9b3328, dark: 0xec8a7c)
    /// destructive button fill, error notes
    static let ccDangerFill = Color(light: 0xf6e9e6, dark: 0x2c1b18)

    // Only for the parts of the prototype's components that aren't palette colours.
    static let ccOnGilt = Color(hex: 0xffffff)
    static let ccShadow = Color(hex: 0x000000).opacity(0.08)
    static let ccHeroTrack = Color(light: 0xffffff, dark: 0x000000, lightAlpha: 0.18, darkAlpha: 0.15)

    // Names from before Chapel, for the screens that haven't had their pass yet.
    static let ccCard = ccPaper // screen backgrounds
    static let ccHairline = ccLine // borders
    static let ccOchre = ccGilt // progress
    static let ccMuted = ccInk3.opacity(0.55) // disabled and dotted marks, also drawn as text
    static let ccHeartReviewing = ccGilt.opacity(0.65)

    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255
        )
    }

    /// Resolves against the colour scheme where it's drawn, so a screen that
    /// forces dark (the camera, the reader's night setting) gets the dark value.
    init(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) {
        self.init(uiColor: UIColor { @Sendable traits in
            let isDark = traits.userInterfaceStyle == .dark
            let hex = isDark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xff) / 255,
                green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255,
                alpha: isDark ? darkAlpha : lightAlpha
            )
        })
    }
}

// Re-declared as ShapeStyle statics (Self == Color) so implicit-member
// syntax resolves in generic ShapeStyle contexts too — e.g.
// `.foregroundStyle(.ccInk)`, `.fill(.ccGilt)`. Without this, only the
// concrete `Color.ccInk` spelling would type-check (the same reason
// SwiftUI's own `.red`/`.blue` work in both contexts).
extension ShapeStyle where Self == Color {
    static var ccPaper: Color { .ccPaper }
    static var ccSurface: Color { .ccSurface }
    static var ccFill: Color { .ccFill }
    static var ccLine: Color { .ccLine }
    static var ccInk: Color { .ccInk }
    static var ccInk2: Color { .ccInk2 }
    static var ccInk3: Color { .ccInk3 }
    static var ccChapel: Color { .ccChapel }
    static var ccOnChapel: Color { .ccOnChapel }
    static var ccGilt: Color { .ccGilt }
    static var ccDanger: Color { .ccDanger }
    static var ccDangerFill: Color { .ccDangerFill }
    static var ccOnGilt: Color { .ccOnGilt }
    static var ccHeroTrack: Color { .ccHeroTrack }
    static var ccCard: Color { .ccCard }
    static var ccHairline: Color { .ccHairline }
    static var ccOchre: Color { .ccOchre }
    static var ccMuted: Color { .ccMuted }
    static var ccHeartReviewing: Color { .ccHeartReviewing }
}

// MARK: - Space and shape

enum ChapelSpace {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
    static let gutter: CGFloat = 20
}

enum ChapelRadius {
    static let sheet: CGFloat = 22
    static let card: CGFloat = 14
    static let control: CGFloat = 12
    static let tabBar: CGFloat = 26
    /// the square behind a row's initial or icon
    static let well: CGFloat = 10
}

enum ChapelSize {
    static let buttonHeight: CGFloat = 50
    static let avatar: CGFloat = 38
    static let rowWell: CGFloat = 34
    static let tick: CGFloat = 22
    static let tabBarHeight: CGFloat = 64
    /// measured from the screen's bottom edge, not the safe area
    static let tabBarBottom: CGFloat = 24
}

// MARK: - Type

// Cinzel: titles and caps labels. Marcellus: anything read. The system font:
// inputs, buttons, lists and numbers.
extension Font {
    static func ccDisplay(_ size: CGFloat, semibold: Bool = false) -> Font {
        .custom(semibold ? "Cinzel-SemiBold" : "Cinzel-Regular", size: size)
    }

    static func ccBody(_ size: CGFloat) -> Font {
        .custom("Marcellus-Regular", size: size)
    }

    /// display.title
    static let ccTitle = ccDisplay(25, semibold: true)
    /// display.h2
    static let ccH2 = ccDisplay(19, semibold: true)
    /// label.caps: use it through `.chapelCaps()`, which adds case and tracking
    static let ccLabelCaps = ccDisplay(10.5)
    /// reading: use it through `.chapelReading()`, which adds the line height
    static let ccReading = ccBody(16.5)
    /// ui: 15.5 rows, 16.5 buttons, 17 inputs, 13 meta
    static func ccUI(_ size: CGFloat = 15.5, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static let ccRowInitial = ccDisplay(13, semibold: true)
    /// The tab bar has a fixed height, so its labels don't grow with Dynamic Type.
    static let ccTabLabel = Font.custom("Cinzel-Regular", fixedSize: 10.5)
}

private struct ChapelReading: ViewModifier {
    /// Marcellus's own line height, as a multiple of the point size (hhea).
    private static let naturalLineHeight: CGFloat = 1.254

    let size: CGFloat
    let lineHeight: CGFloat

    func body(content: Content) -> some View {
        let extra = size * max(lineHeight - Self.naturalLineHeight, 0)
        // Like CSS line-height: the extra space is between lines and half of it
        // above the first and below the last.
        content
            .font(size == 16.5 ? .ccReading : .ccBody(size))
            .lineSpacing(extra)
            .padding(.vertical, extra / 2)
            .fixedSize(horizontal: false, vertical: true)
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

    /// label.caps
    func chapelCaps(color: Color = .ccInk3) -> some View {
        font(.ccLabelCaps)
            .tracking(10.5 * 0.16)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }

    /// reading
    func chapelReading(size: CGFloat = 16.5, lineHeight: CGFloat = 1.5) -> some View {
        modifier(ChapelReading(size: size, lineHeight: lineHeight))
    }

    /// The quiet dotted-underline treatment used for tertiary actions and
    /// links (Prev/Next, "Back to the Question", "See Milestones →"...).
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

// MARK: - Components

extension View {
    /// A bordered card on surface: pillar cards and lists.
    func chapelCard() -> some View {
        let shape = RoundedRectangle(cornerRadius: ChapelRadius.card, style: .circular)
        return padding(1) // the border takes space, as in the prototype
            .background(Color.ccSurface, in: shape)
            .overlay(shape.strokeBorder(Color.ccLine, lineWidth: 1))
    }

    /// The floating tab bar's shell.
    func chapelTabBar() -> some View {
        let shape = RoundedRectangle(cornerRadius: ChapelRadius.tabBar, style: .circular)
        return frame(height: ChapelSize.tabBarHeight)
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill(Color.ccSurface.opacity(0.88)))
                    .shadow(color: .ccShadow, radius: 12, y: 8)
            }
            .overlay(shape.strokeBorder(Color.ccLine, lineWidth: 1))
            .contentShape(shape)
    }
}

/// The screen's one filled button. On the hero it is inverted.
struct ChapelPrimaryButtonStyle: ButtonStyle {
    var onHero = false

    func makeBody(configuration: Configuration) -> some View {
        ChapelButtonLabel(
            configuration: configuration,
            ink: onHero ? .ccChapel : .ccOnChapel,
            fill: onHero ? .ccOnChapel : .ccChapel
        )
    }
}

struct ChapelQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ChapelButtonLabel(configuration: configuration, ink: .ccInk, fill: .ccFill)
    }
}

private struct ChapelButtonLabel: View {
    let configuration: ButtonStyle.Configuration
    let ink: Color
    let fill: Color

    var body: some View {
        configuration.label
            .font(.ccUI(16.5, weight: .semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, minHeight: ChapelSize.buttonHeight)
            .background(fill, in: RoundedRectangle(cornerRadius: ChapelRadius.control, style: .circular))
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// The one thing to do now.
struct ChapelHeroCard: View {
    let eyebrow: String
    let text: String
    let progress: Double?
    let detail: String?
    let button: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(eyebrow)
                .chapelCaps(color: .ccOnChapel.opacity(0.75))
            Text(text)
                .chapelReading(size: 21, lineHeight: 1.35)
                .foregroundStyle(.ccOnChapel)
                .padding(.top, 10)
                .padding(.bottom, ChapelSpace.l)
            if let progress {
                GeometryReader { geo in
                    Rectangle().fill(Color.ccHeroTrack)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Color.ccGilt).frame(width: geo.size.width * min(max(progress, 0), 1))
                        }
                }
                .frame(height: 4)
                .clipShape(Capsule())
                .padding(.bottom, 6)
            }
            if let detail {
                Text(detail)
                    .font(.ccUI(13))
                    .foregroundStyle(.ccOnChapel.opacity(0.8))
                    .padding(.bottom, ChapelSpace.l)
            }
            Button(button, action: action)
                .buttonStyle(ChapelPrimaryButtonStyle(onHero: true))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ccChapel, in: RoundedRectangle(cornerRadius: ChapelRadius.card, style: .circular))
    }
}

/// A row in a list card: an initial or icon, a title over one line of detail,
/// then a chevron, or a gilt tick when it's done.
struct ChapelListRow<Lead: View>: View {
    let title: String
    let detail: String
    let done: Bool
    @ViewBuilder let lead: Lead

    var body: some View {
        HStack(spacing: ChapelSpace.m) {
            lead
                .font(.ccRowInitial)
                .foregroundStyle(.ccInk)
                .frame(width: ChapelSize.rowWell, height: ChapelSize.rowWell)
                .background(Color.ccFill, in: RoundedRectangle(cornerRadius: ChapelRadius.well, style: .circular))
                .accessibilityHidden(true) // the title says it
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.ccUI())
                    .foregroundStyle(done ? Color.ccInk3 : Color.ccInk)
                Text(detail)
                    .font(.ccUI(13))
                    .foregroundStyle(.ccInk2)
                    .lineLimit(1)
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if done {
                Text("✓")
                    .font(.ccUI(12))
                    .foregroundStyle(.ccOnGilt)
                    .frame(width: ChapelSize.tick, height: ChapelSize.tick)
                    .background(Color.ccGilt, in: Circle())
                    .accessibilityLabel("Done")
            } else {
                Text("›")
                    .font(.ccUI(18))
                    .foregroundStyle(.ccInk3)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, ChapelSpace.l)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}
