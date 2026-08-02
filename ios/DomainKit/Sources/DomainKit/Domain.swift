// Domain types, ported from src/lib/domain.ts. See docs/DOMAIN.md (in the
// Next.js repo) for the id grammar and document-alias vocabularies these
// shapes are keyed by.
import Foundation

/// A single node in a confession/catechism, as stored in
/// normalized-data/**.json. Ids are dash-delimited paths, e.g. "WCoF-1"
/// (chapter), "WCoF-1-2" (article), "CoD-1-articles-3" (Canons of Dort).
public struct ConfessionEntry: Codable, Sendable, Hashable {
    public let id: String
    public let parent: String
    public let title: String?
    public let isParent: Bool
    public let number: Int?
    public let text: String?
    /// Proof-text scripture citations (OSIS refs), keyed by footnote label.
    public let verses: [String: [String]]?

    public init(
        id: String,
        parent: String,
        title: String?,
        isParent: Bool,
        number: Int? = nil,
        text: String? = nil,
        verses: [String: [String]]? = nil
    ) {
        self.id = id
        self.parent = parent
        self.title = title
        self.isParent = isParent
        self.number = number
        self.text = text
        self.verses = verses
    }
}

/// The flat id -> entry map most consumers work against.
public typealias ContentById = [String: ConfessionEntry]

/// Shape of one normalized-data/**.json document file.
public struct ConfessionDocumentJson: Codable, Sendable {
    public let title: String
    public let type: String
    public let content: [ConfessionEntry]
}

/// Document metadata (the single source of truth in Catechisms.swift).
public struct CreedalDocument: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let shortName: String
    public let totalItems: Int
    public let itemLabel: String
    public let itemLabelPlural: String
    public let type: DocumentType
    public let tradition: String
    public let description: String

    public enum DocumentType: String, Codable, Sendable {
        case catechism, confession, theses
    }
}

/// Children-tracking view of a catechism, derived from CreedalDocument.
public struct Catechism: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let shortName: String
    public let totalQuestions: Int
    public let description: String
    /// Suggested age range, e.g. "8-12".
    public let ageRange: String
}
