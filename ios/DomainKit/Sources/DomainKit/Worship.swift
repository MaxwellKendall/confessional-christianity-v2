// Ported from src/lib/worship.ts's element/step types (the daypart rotation
// machinery itself — dayIndexOf, getService — is Family Worship's own and
// out of scope here; a Devotion's steps are always pre-resolved, no
// rotation elements).
import Foundation

public struct ElementSource: Codable, Equatable, Sendable {
    public let label: String
    public let href: String
    /// true renders "leaves the app"; false/absent stays in it.
    public let external: Bool?
}

public struct PromptItem: Codable, Equatable, Sendable {
    public let label: String
    public let text: String
}

public enum WorshipElement: Equatable, Sendable {
    case scripture(lede: String?, citation: String, osis: String, text: String, source: ElementSource?)
    case prayer(lede: String?, text: String, amen: Bool, source: ElementSource?)
    case song(lede: String?, title: String, lyrics: String, source: ElementSource?)
    case creed(lede: String?, title: String, text: String, source: ElementSource?)
    case catechism(lede: String?)
    case instruction(text: String)
    case prompts(lede: String?, items: [PromptItem])

    public var typeName: String {
        switch self {
        case .scripture: return "scripture"
        case .prayer: return "prayer"
        case .song: return "song"
        case .creed: return "creed"
        case .catechism: return "catechism"
        case .instruction: return "instruction"
        case .prompts: return "prompts"
        }
    }
}

extension WorshipElement: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type, lede, citation, osis, text, amen, title, lyrics, source, items
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let lede = try container.decodeIfPresent(String.self, forKey: .lede)
        let source = try container.decodeIfPresent(ElementSource.self, forKey: .source)
        switch type {
        case "scripture":
            self = .scripture(
                lede: lede,
                citation: try container.decode(String.self, forKey: .citation),
                osis: try container.decode(String.self, forKey: .osis),
                text: try container.decode(String.self, forKey: .text),
                source: source
            )
        case "prayer":
            self = .prayer(
                lede: lede,
                text: try container.decode(String.self, forKey: .text),
                amen: try container.decodeIfPresent(Bool.self, forKey: .amen) ?? false,
                source: source
            )
        case "song":
            self = .song(
                lede: lede,
                title: try container.decode(String.self, forKey: .title),
                lyrics: try container.decode(String.self, forKey: .lyrics),
                source: source
            )
        case "creed":
            self = .creed(
                lede: lede,
                title: try container.decode(String.self, forKey: .title),
                text: try container.decode(String.self, forKey: .text),
                source: source
            )
        case "catechism":
            self = .catechism(lede: lede)
        case "instruction":
            self = .instruction(text: try container.decode(String.self, forKey: .text))
        case "prompts":
            self = .prompts(lede: lede, items: try container.decode([PromptItem].self, forKey: .items))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown element type \(type)")
        }
    }
}

public struct WorshipStep: Decodable, Equatable, Sendable {
    public let role: String
    public let elements: [WorshipElement]
}

/// The order-of-service preview line (15c/16a): a step's lead element's
/// citation/title, or nil when nothing worth previewing leads it.
public func stepDetail(_ step: WorshipStep) -> String? {
    guard let lead = step.elements.first else { return nil }
    switch lead {
    case .scripture(_, let citation, _, _, _): return citation
    case .song(_, let title, _, _): return title
    case .creed(_, let title, _, _): return title
    default: return nil
    }
}
