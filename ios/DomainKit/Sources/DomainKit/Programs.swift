// The programs domain, ported from src/lib/programs.ts. A program is an
// authored, ordered walk through a catechism.
import Foundation

public struct ProgramDefinition: Equatable, Sendable {
    public let slug: String
    /// loose grouping on /programs: family catechesis, scripture, devotional
    public let kind: String
    public let title: String
    /// conversational short name used in CTAs ("Continue the {shortTitle}")
    public let shortTitle: String
    /// confessional tradition shown as the landing eyebrow; nil when the
    /// document belongs to no standard grouping
    public let tradition: String?
    public let description: String
    /// the catechism the program traverses
    public let contentId: ContentId
    public let totalQuestions: Int
    public let estimatedMinutes: Int
}

public let PROGRAMS: [ProgramDefinition] = [
    ProgramDefinition(
        slug: "catechizing-shorter-catechism",
        kind: "Family Catechesis",
        title: "Westminster Shorter Catechism",
        shortTitle: "Shorter Catechism",
        tradition: "Westminster Standards",
        description: "The Westminster Shorter Catechism paired with Scripture, prayer, and progress for family teaching.",
        contentId: .wsc,
        totalQuestions: 107,
        estimatedMinutes: 15
    ),
    ProgramDefinition(
        slug: "catechism-for-young-children",
        kind: "Family Catechesis",
        title: "Catechism for Young Children",
        shortTitle: "Catechism for Young Children",
        tradition: nil,
        description: "A simple, memorable introduction to the faith for the youngest learners.",
        contentId: .cfyc,
        totalQuestions: 145,
        estimatedMinutes: 10
    ),
    ProgramDefinition(
        slug: "catechizing-larger-catechism",
        kind: "Family Catechesis",
        title: "Westminster Larger Catechism",
        shortTitle: "Larger Catechism",
        tradition: "Westminster Standards",
        description: "A more comprehensive walk through the Westminster Larger Catechism, paired with Scripture, prayer, and progress.",
        contentId: .wlc,
        totalQuestions: 196,
        estimatedMinutes: 20
    ),
    ProgramDefinition(
        slug: "catechizing-heidelberg-catechism",
        kind: "Family Catechesis",
        title: "Heidelberg Catechism",
        shortTitle: "Heidelberg Catechism",
        tradition: "Three Forms of Unity",
        description: "The Heidelberg Catechism paired with Scripture, prayer, and progress for family teaching.",
        contentId: .hc,
        totalQuestions: 129,
        estimatedMinutes: 15
    ),
]

public func getProgram(_ slug: String) -> ProgramDefinition? {
    PROGRAMS.first { $0.slug == slug }
}
