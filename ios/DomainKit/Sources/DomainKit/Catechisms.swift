// All creedal documents. This is the single source of truth for every
// document's shared metadata (name, shortName, item count, description,
// tradition). The children-tracking CATECHISMS registry below is *derived*
// from this map rather than duplicated, so the two can't drift out of sync.
// Ported from src/lib/catechisms.ts. See docs/DOMAIN.md (in the Next.js repo).
import Foundation

public let CREEDAL_DOCUMENTS: [String: CreedalDocument] = [
    "WSC": CreedalDocument(
        id: "WSC", name: "Westminster Shorter Catechism", shortName: "WSC",
        totalItems: 107, itemLabel: "Question", itemLabelPlural: "Questions",
        type: .catechism, tradition: "Westminster Standards",
        description: "A summary of doctrine intended for those beginning their Christian education"
    ),
    "WLC": CreedalDocument(
        id: "WLC", name: "Westminster Larger Catechism", shortName: "WLC",
        totalItems: 196, itemLabel: "Question", itemLabelPlural: "Questions",
        type: .catechism, tradition: "Westminster Standards",
        description: "A more comprehensive catechism for those who have profited by the Shorter Catechism"
    ),
    "CFYC": CreedalDocument(
        id: "CfYC", name: "Catechism for Young Children", shortName: "CfYC",
        totalItems: 145, itemLabel: "Question", itemLabelPlural: "Questions",
        type: .catechism, tradition: "Other",
        description: "An introductory catechism designed for young children"
    ),
    "HC": CreedalDocument(
        id: "HC", name: "Heidelberg Catechism", shortName: "HC",
        totalItems: 129, itemLabel: "Question", itemLabelPlural: "Questions",
        type: .catechism, tradition: "Three Forms of Unity",
        description: "A Protestant catechism taking the form of a series of questions and answers"
    ),
    "WCF": CreedalDocument(
        id: "WCF", name: "Westminster Confession of Faith", shortName: "WCF",
        totalItems: 33, itemLabel: "Chapter", itemLabelPlural: "Chapters",
        type: .confession, tradition: "Westminster Standards",
        description: "The principal confessional standard of Presbyterian churches worldwide"
    ),
    "BCF": CreedalDocument(
        id: "BCF", name: "Belgic Confession of Faith", shortName: "BCF",
        totalItems: 37, itemLabel: "Article", itemLabelPlural: "Articles",
        type: .confession, tradition: "Three Forms of Unity",
        description: "One of the Three Forms of Unity, a confession of the Reformed churches"
    ),
    "CD": CreedalDocument(
        id: "CD", name: "Canons of Dort", shortName: "CD",
        totalItems: 4, itemLabel: "Head of Doctrine", itemLabelPlural: "Heads of Doctrine",
        type: .confession, tradition: "Three Forms of Unity",
        description: "The judgment of the Synod of Dort on the Five Articles of the Remonstrants"
    ),
    "TAR": CreedalDocument(
        id: "TAR", name: "Thirty-Nine Articles", shortName: "39A",
        totalItems: 39, itemLabel: "Article", itemLabelPlural: "Articles",
        type: .confession, tradition: "Anglican",
        description: "The defining statements of Anglican doctrine"
    ),
    "95T": CreedalDocument(
        id: "95T", name: "Ninety-Five Theses", shortName: "95T",
        totalItems: 95, itemLabel: "Thesis", itemLabelPlural: "Theses",
        type: .theses, tradition: "Reformation",
        description: "Martin Luther's propositions that sparked the Protestant Reformation"
    ),
]

/// Catechisms available for children's progress tracking. Derived from
/// CREEDAL_DOCUMENTS so name/count/description stay in one place; the only
/// catechism-specific field is the suggested ageRange overlay below.
private let catechismAgeRanges: [String: String] = [
    "WSC": "8-12",
    "WLC": "12+",
    "CFYC": "4-8",
    "HC": "10+",
]

public let CATECHISMS: [String: Catechism] = Dictionary(
    uniqueKeysWithValues: catechismAgeRanges.compactMap { key, ageRange -> (String, Catechism)? in
        guard let doc = CREEDAL_DOCUMENTS[key] else { return nil }
        return (key, Catechism(
            id: doc.id, name: doc.name, shortName: doc.shortName,
            totalQuestions: doc.totalItems, description: doc.description, ageRange: ageRange
        ))
    }
)

public func getCatechismById(_ id: String) -> Catechism? {
    let upper = id.uppercased()
    if upper == "CFYC" { return CATECHISMS["CFYC"] }
    return CATECHISMS[upper]
}

public func getDocumentById(_ id: String) -> CreedalDocument? {
    guard !id.isEmpty else { return nil }
    let upper = id.uppercased()
    if upper == "CFYC" { return CREEDAL_DOCUMENTS["CFYC"] }
    return CREEDAL_DOCUMENTS[upper]
}

public func getCatechismList() -> [Catechism] { Array(CATECHISMS.values) }

public func getDocumentList() -> [CreedalDocument] { Array(CREEDAL_DOCUMENTS.values) }

public struct TraditionGroup: Equatable, Sendable {
    public let tradition: String
    public let documents: [CreedalDocument]
}

public func getDocumentsByTradition() -> [TraditionGroup] {
    let documents = Array(CREEDAL_DOCUMENTS.values)
    var grouped: [String: [CreedalDocument]] = [:]
    for doc in documents {
        grouped[doc.tradition, default: []].append(doc)
    }
    let order = ["Westminster Standards", "Three Forms of Unity", "Anglican", "Reformation", "Other"]
    return order.compactMap { tradition in
        guard let docs = grouped[tradition], !docs.isEmpty else { return nil }
        return TraditionGroup(tradition: tradition, documents: docs)
    }
}

/// Resolves a document abbreviation + item number to the canonical library
/// entry page, e.g. ("WSC", 12) -> /library/westminster-shorter-catechism/12.
public func generateDocumentLink(_ documentId: String, itemNumber: Int) -> String {
    let canonicalId = parentIdByAbbreviation[documentId.uppercased()] ?? documentId
    guard let slug = slugByDocumentId[canonicalId] else {
        let query = "\(documentId).\(itemNumber)"
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return "/search?q=\(encoded)"
    }
    return "/library/\(slug)/\(itemNumber)"
}

public func generateCatechismLink(_ catechismId: String, questionNumber: Int) -> String {
    generateDocumentLink(catechismId, itemNumber: questionNumber)
}

public func calculateProgress(_ currentQuestion: Int?, _ totalQuestions: Int?) -> Int {
    guard let currentQuestion, currentQuestion != 0, let totalQuestions, totalQuestions != 0 else { return 0 }
    return Int((Double(currentQuestion) / Double(totalQuestions) * 100).rounded())
}
