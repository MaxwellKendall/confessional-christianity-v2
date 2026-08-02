// Ported from src/lib/devotionSeries.ts. A series is an ordering over
// devotions — the seasonal and catechism runs both open onto genuine,
// cumulative arcs. Order is suggested, never enforced: every authored part
// stays reachable regardless of completion state.
import Foundation

public enum SeriesSource: Equatable, Sendable {
    case season(season: String)
    case catechism(documentId: String)
}

extension SeriesSource: Decodable {
    private enum CodingKeys: String, CodingKey {
        case kind, season, documentId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "season":
            self = .season(season: try container.decode(String.self, forKey: .season))
        case "catechism":
            self = .catechism(documentId: try container.decode(String.self, forKey: .documentId))
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown series source kind \(kind)")
        }
    }
}

public struct SeriesPart: Decodable, Equatable, Sendable {
    public let day: Int
    public let title: String
    public let citation: String
    /// absent while the part is still in preparation.
    public let devotionSlug: String?
}

public struct DevotionSeries: Decodable, Equatable, Sendable {
    public let slug: String
    public let source: SeriesSource
    public let title: String
    public let tagline: String
    public let description: String
    public let parts: [SeriesPart]
}

private func seriesResourceURL(_ slug: String) -> URL {
    let dir = "BundledContent/content/devotions/series"
    guard let url = Bundle.module.url(forResource: slug, withExtension: "json", subdirectory: dir) else {
        fatalError("DomainKit: missing bundled series \(slug).json")
    }
    return url
}

private func loadSeries(_ slug: String) -> DevotionSeries {
    let url = seriesResourceURL(slug)
    do {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(DevotionSeries.self, from: data)
    } catch {
        fatalError("DomainKit: failed to decode series \(slug).json: \(error)")
    }
}

// Add an entry here for each authored series, same shape as advent/wsc.
private let SERIES: [DevotionSeries] = [
    loadSeries("advent"),
    loadSeries("wsc"),
]

public func getAllSeries() -> [DevotionSeries] { SERIES }

public func getSeries(_ slug: String) -> DevotionSeries? { SERIES.first { $0.slug == slug } }

public func seriesForSeason(_ season: String) -> DevotionSeries? {
    SERIES.first {
        if case .season(let s) = $0.source { return s == season }
        return false
    }
}

public func seriesForCatechism(_ documentId: String) -> DevotionSeries? {
    SERIES.first {
        if case .catechism(let d) = $0.source { return d == documentId }
        return false
    }
}

/// What the hub/landing calls this run's source: the season's name, or the
/// catechism document's name. Falls back to the series' own title.
public func seriesSourceLabel(_ series: DevotionSeries) -> String {
    switch series.source {
    case .season(let season):
        return SEASONS.first { $0.slug == season }?.name ?? series.title
    case .catechism(let documentId):
        return getDocumentById(documentId)?.name ?? series.title
    }
}

/// How many catechism questions this run has actually authored so far —
/// summed off each part's devotion, since a part can profess more than one
/// question. Zero for a season-sourced run.
public func catechismQuestionsAuthored(_ series: DevotionSeries) -> Int {
    series.parts.reduce(0) { sum, part in
        guard let slug = part.devotionSlug, let devotion = getDevotion(slug) else { return sum }
        if case .catechism(let entryIds) = devotion.grounding { return sum + entryIds.count }
        return sum
    }
}

/// The devotion carrying a part's authored content — nil while the part is
/// still in preparation.
public func partDevotion(_ series: DevotionSeries, _ day: Int) -> Devotion? {
    guard let part = series.parts.first(where: { $0.day == day }), let slug = part.devotionSlug else { return nil }
    return getDevotion(slug)
}

public struct SeriesMembership: Equatable, Sendable {
    public let series: DevotionSeries
    public let part: SeriesPart
}

/// Which series a devotion is a part of, and where in the order — nil for
/// standalone devotions.
public func seriesMembership(_ devotion: Devotion) -> SeriesMembership? {
    for series in SERIES {
        if let part = series.parts.first(where: { $0.devotionSlug == devotion.slug }) {
            return SeriesMembership(series: series, part: part)
        }
    }
    return nil
}
