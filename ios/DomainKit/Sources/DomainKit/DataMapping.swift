// Document-alias vocabularies, ported from src/lib/dataMapping.ts (itself
// ported from v1 dataMapping/index.js). See docs/DOMAIN.md (in the Next.js
// repo) before touching anything keyed by these maps. Only the tables
// Programs/Library need in this phase are ported here — confessionCitationByIndex,
// facetNamesByCanonicalDocId, and KEYWORDS are Search-phase only.

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
