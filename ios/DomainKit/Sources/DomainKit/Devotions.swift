// Ported from src/lib/devotions.ts. A devotion is a fixed, addressable
// liturgy grounded in something specific (Scripture, a topic, a catechism
// entry, or a season) — its steps are the same typed WorshipStep elements
// Family Worship renders, just pre-resolved (no rotation). Only the browse
// axes actually reachable from the WSC devotion-run card are ported here —
// the full devotions hub (scripture-by-book, topic browse) is out of scope
// until that hub itself is built.
import Foundation

public enum GroundingKind: String, Sendable {
    case scripture, topic, catechism, season
}

public enum DevotionGrounding: Equatable, Sendable {
    case scripture(osis: String, citation: String)
    case topic(topic: String)
    case catechism(entryIds: [String])
    case season(season: String, day: Int)
}

extension DevotionGrounding: Decodable {
    private enum CodingKeys: String, CodingKey {
        case kind, osis, citation, topic, entryIds, season, day
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "scripture":
            self = .scripture(
                osis: try container.decode(String.self, forKey: .osis),
                citation: try container.decode(String.self, forKey: .citation)
            )
        case "topic":
            self = .topic(topic: try container.decode(String.self, forKey: .topic))
        case "catechism":
            self = .catechism(entryIds: try container.decode([String].self, forKey: .entryIds))
        case "season":
            self = .season(
                season: try container.decode(String.self, forKey: .season),
                day: try container.decode(Int.self, forKey: .day)
            )
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown grounding kind \(kind)")
        }
    }

    public var kind: GroundingKind {
        switch self {
        case .scripture: return .scripture
        case .topic: return .topic
        case .catechism: return .catechism
        case .season: return .season
        }
    }
}

public struct Devotion: Decodable, Equatable, Sendable {
    public let slug: String
    public let title: String
    public let summary: String
    public let description: String
    public let grounding: DevotionGrounding
    public let steps: [WorshipStep]
}

public struct DevotionTopic: Sendable {
    public let slug: String
    public let name: String
}

public let TOPICS: [DevotionTopic] = [
    DevotionTopic(slug: "repentance", name: "Repentance"),
    DevotionTopic(slug: "gratitude", name: "Gratitude"),
    DevotionTopic(slug: "suffering", name: "Suffering"),
    DevotionTopic(slug: "anxiety", name: "Anxiety"),
    DevotionTopic(slug: "vocation", name: "Vocation"),
]

public struct DevotionSeason: Sendable {
    public let slug: String
    public let name: String
    public let days: Int
}

public let SEASONS: [DevotionSeason] = [
    DevotionSeason(slug: "advent", name: "Advent", days: 24),
    DevotionSeason(slug: "lent", name: "Lent", days: 40),
]

private func devotionResourceURL(_ path: String) -> URL {
    let full = "BundledContent/content/devotions/" + path
    let dir = (full as NSString).deletingLastPathComponent
    let name = (full as NSString).lastPathComponent
    guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: dir) else {
        fatalError("DomainKit: missing bundled devotion \(full).json")
    }
    return url
}

func loadDevotion(_ slug: String) -> Devotion {
    let url = devotionResourceURL(slug)
    do {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Devotion.self, from: data)
    } catch {
        fatalError("DomainKit: failed to decode devotion \(slug).json: \(error)")
    }
}

// Every authored devotion — mirrors the manifest in devotions.ts (one entry
// per content/devotions/<slug>.json). Numbers not listed here (41, 44, 46,
// 48, 50, 52, 54, 56, 58, 60, 62, 64) are questions paired into the devotion
// before them (e.g. wsc-40 covers WSC Q. 40-41) — deliberate skips, not gaps.
private let authoredWscDevotions = Array(1...40) + [42, 43, 45, 47, 49, 51, 53, 55, 57, 59, 61, 63, 65]

private let devotionSlugs = ["psalm-130", "advent-1", "advent-2", "advent-3"]
    + authoredWscDevotions.map { "wsc-\($0)" }

private let devotionsBySlug: [String: Devotion] = Dictionary(
    uniqueKeysWithValues: devotionSlugs.map { ($0, loadDevotion($0)) }
)

public func getAllDevotions() -> [Devotion] { Array(devotionsBySlug.values) }

public func getDevotion(_ slug: String) -> Devotion? { devotionsBySlug[slug] }

public func devotionsGroundedIn(_ kind: GroundingKind) -> [Devotion] {
    devotionsBySlug.values.filter { $0.grounding.kind == kind }
}

/// What a devotion is grounded in, for the "Grounded in …" line — degrades
/// to the raw value when a registry lookup misses.
public func groundingLabel(_ grounding: DevotionGrounding) -> String {
    switch grounding {
    case .scripture(_, let citation):
        return citation
    case .topic(let topic):
        return TOPICS.first { $0.slug == topic }?.name ?? topic
    case .catechism(let entryIds):
        guard let first = entryIds.first, let documentId = first.split(separator: "-").first else {
            return entryIds.joined(separator: ", ")
        }
        let doc = getDocumentById(String(documentId))
        let items = entryIds.map { String($0.dropFirst(documentId.count + 1)) }
        guard let doc, !items.contains(where: { $0.isEmpty }) else {
            return entryIds.joined(separator: ", ")
        }
        return items.count == 1
            ? "\(doc.shortName) Q. \(items[0])"
            : "\(doc.shortName) Q. \(items[0])\u{2013}\(items[items.count - 1])"
    case .season(let season, let day):
        let name = SEASONS.first { $0.slug == season }?.name ?? season
        return "\(name) \u{00B7} Day \(day)"
    }
}
