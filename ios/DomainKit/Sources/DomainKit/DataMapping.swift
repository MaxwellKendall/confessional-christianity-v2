// Document-alias vocabularies, ported from src/lib/dataMapping.ts (itself
// ported from v1 dataMapping/index.js). See docs/DOMAIN.md (in the Next.js
// repo) before touching anything keyed by these maps. facetNamesByCanonicalDocId
// isn't ported — nothing consumes it (Search's parseFacets doesn't need it).

/// [document title, ...locator labels, "Scripture Citation"], keyed by every
/// alias a document id can appear under.
public let confessionCitationByIndex: [String: [String]] = [
    "WCF": ["Westminster Confession of Faith", "Chapter", "Article", "Scripture Citation"],
    "WCoF": ["Westminster Confession of Faith", "Chapter", "Article", "Scripture Citation"],
    "WCOF": ["Westminster Confession of Faith", "Chapter", "Article", "Scripture Citation"],
    "HC": ["Heidelberg Catechism", "LORD's Day", "Question and Answer", "Scripture Citation"],
    "WSC": ["Westminster Shorter Catechism", "Question and Answer", "Scripture Citation"],
    "WLC": ["Westminster Larger Catechism", "Question and Answer", "Scripture Citation"],
    "39A": ["Thirty-nine Articles of Religion", "Chapter"],
    "TAR": ["Thirty-nine Articles of Religion", "Chapter"],
    "TAOR": ["Thirty-nine Articles of Religion", "Chapter"],
    "CD": ["Canons of Dort", "Chapter"],
    "COD": ["Canons of Dort", "Chapter"],
    "BCF": ["The Belgic Confession of Faith", "Chapter"],
    "TBCoF": ["The Belgic Confession of Faith", "Chapter"],
    "TBCOF": ["The Belgic Confession of Faith", "Chapter"],
    "BC": ["The Belgic Confession of Faith", "Chapter"],
    "95T": ["Martin Luther's 95 theses"],
    "ML9T": ["Martin Luther's 95 theses"],
    "CFYC": ["Catechism for Young Children"],
    "ALL": ["ALL"],
]

/// maps each document's true canonical id (as it appears as the id prefix in
/// contentById, e.g. "WCoF-1-2") to the URL slug used for its library pages.
public let slugByDocumentId: [String: String] = [
    "WCoF": "westminster-confession-of-faith",
    "WLC": "westminster-larger-catechism",
    "WSC": "westminster-shorter-catechism",
    "HC": "heidelberg-catechism",
    "CoD": "canons-of-dort",
    "TBCoF": "the-belgic-confession-of-faith",
    "TAoR": "thirty-nine-articles-of-religion",
    "ML9t": "martin-luthers-95-theses",
]

/// inverse of slugByDocumentId: URL slug -> canonical document id.
public let documentIdBySlug: [String: String] = Dictionary(
    uniqueKeysWithValues: slugByDocumentId.map { ($1, $0) }
)

/// canonical docIds in algolia (kept verbatim from the TS comment).
public let parentIdByAbbreviation: [String: String] = [
    "WCF": "WCoF",
    "WCOF": "WCoF",
    "HC": "HC",
    "WLC": "WLC",
    "WSC": "WSC",
    "CD": "CoD",
    "COD": "CoD",
    "BCF": "TBCoF",
    "TAR": "TAoR",
    "39A": "TAoR",
    "95T": "ML9t",
    "ML9T": "ML9t",
    "CFYC": "CfYC",
]

public let documentsWithoutArticles: Set<String> = [
    "ML9T", "BCF", "TBCoF", "TAR", "WLC", "WSC", "CFYC", "CfYC",
]

public let confessionIdsWithoutTitles: Set<String> = [
    "WSC", "WLC", "BCoF", "TBCoF", "TAoR", "ML9t", "CfYC",
]

public let excludedWordsInDocumentId: Set<String> = ["OF", "THE"]
