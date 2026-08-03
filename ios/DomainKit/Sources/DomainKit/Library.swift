// Read-side accessors for the Library surface, ported from src/lib/library.ts
// and src/lib/confessionContent.ts. Every document is bundled JSON, so
// lookups are synchronous and local, unlike the web version's static-import
// build step.
import Foundation

/// Editorial metadata for the library index and document pages. The blurbs
/// are the design handoff's copy (mockup 1f), carried over verbatim.
public struct LibraryDocument: Equatable, Sendable {
    public let slug: String
    public let documentId: String
    public let name: String
    public let blurb: String
}

public let LIBRARY_DOCUMENTS: [LibraryDocument] = [
    LibraryDocument(
        slug: "westminster-shorter-catechism", documentId: "WSC",
        name: "Westminster Shorter Catechism",
        blurb: "A 1647 primer in question-and-answer form, still used to teach the faith."
    ),
    LibraryDocument(
        slug: "westminster-confession-of-faith", documentId: "WCoF",
        name: "Westminster Confession of Faith",
        blurb: "The 1646 confession underlying Presbyterian doctrine."
    ),
    LibraryDocument(
        slug: "westminster-larger-catechism", documentId: "WLC",
        name: "Westminster Larger Catechism",
        blurb: "The 1647 companion catechism, fuller in both doctrine and duty."
    ),
    LibraryDocument(
        slug: "heidelberg-catechism", documentId: "HC",
        name: "Heidelberg Catechism",
        blurb: "A 1563 catechism prized for its pastoral warmth."
    ),
    LibraryDocument(
        slug: "the-belgic-confession-of-faith", documentId: "TBCoF",
        name: "Belgic Confession",
        blurb: "A 1561 statement of Reformed belief, Dutch tradition."
    ),
    LibraryDocument(
        slug: "canons-of-dort", documentId: "CoD",
        name: "Canons of Dort",
        blurb: "The 1619 Synod\u{2019}s judgment on grace and election."
    ),
    LibraryDocument(
        slug: "thirty-nine-articles-of-religion", documentId: "TAoR",
        name: "Thirty-Nine Articles",
        blurb: "The doctrinal basis of the Church of England, settled 1571."
    ),
    LibraryDocument(
        slug: "martin-luthers-95-theses", documentId: "ML9t",
        name: "Luther\u{2019}s Ninety-Five Theses",
        blurb: "The 1517 propositions that opened the Reformation."
    ),
]

public func getLibraryDocument(_ slug: String) -> LibraryDocument? {
    LIBRARY_DOCUMENTS.first { $0.slug == slug }
}

private func libraryResourceURL(_ path: String) -> URL? {
    let full = "BundledContent/" + path
    let dir = (full as NSString).deletingLastPathComponent
    let name = (full as NSString).lastPathComponent
    return Bundle.module.url(forResource: name, withExtension: "json", subdirectory: dir)
}

private func loadLibraryDocumentJson(_ resourcePath: String) -> ConfessionDocumentJson? {
    guard let url = libraryResourceURL(resourcePath) else { return nil }
    return try? JSONDecoder().decode(ConfessionDocumentJson.self, from: try Data(contentsOf: url))
}

// Keys must match LIBRARY_DOCUMENTS' slugs.
private let confessionDataBySlug: [String: ConfessionDocumentJson] = [
    "westminster-confession-of-faith": loadLibraryDocumentJson("normalized-data/westminster/wcf"),
    "westminster-larger-catechism": loadLibraryDocumentJson("normalized-data/westminster/wlc"),
    "westminster-shorter-catechism": loadLibraryDocumentJson("normalized-data/westminster/wsc"),
    "heidelberg-catechism": loadLibraryDocumentJson("normalized-data/three-forms-of-unity/heidelberg-catechism"),
    "canons-of-dort": loadLibraryDocumentJson("normalized-data/three-forms-of-unity/canons-of-dort"),
    "the-belgic-confession-of-faith": loadLibraryDocumentJson("normalized-data/three-forms-of-unity/belgic-confession"),
    "thirty-nine-articles-of-religion": loadLibraryDocumentJson("normalized-data/anglican/39-articles"),
    "martin-luthers-95-theses": loadLibraryDocumentJson("normalized-data/reformation/95-theses"),
].compactMapValues { $0 }

/// A single confession/catechism's content keyed by id, plus its canonical
/// document id (derived from any entry whose parent is the document itself).
public struct ConfessionContent: Sendable {
    public let contentById: ContentById
    public let documentId: String
}

public func loadConfessionContent(_ slug: String) -> ConfessionContent? {
    guard let parsed = confessionDataBySlug[slug] else { return nil }
    let contentById = Dictionary(uniqueKeysWithValues: parsed.content.map { ($0.id, $0) })
    guard let documentId = contentById.values.first(where: { !$0.parent.contains("-") })?.parent else { return nil }
    return ConfessionContent(contentById: contentById, documentId: documentId)
}

/// Leaf entries of a document, in canonical document order.
public func getOrderedLeafEntries(_ slug: String) -> [ConfessionEntry] {
    guard let content = loadConfessionContent(slug) else { return [] }
    return content.contentById.values
        .filter { !$0.isParent }
        .sorted { compareEntryIds($0.id, $1.id) }
}

/// Every entry (parents included), in canonical document order — for TOCs.
public func getOrderedEntries(_ slug: String) -> [ConfessionEntry] {
    guard let content = loadConfessionContent(slug) else { return [] }
    return content.contentById.values.sorted { compareEntryIds($0.id, $1.id) }
}

public struct AdjacentEntry: Equatable, Sendable {
    public let entryId: String
    public let title: String
}

public struct EntryPage: Sendable {
    public let item: ConfessionEntry
    public let documentTitle: String
    public let slug: String
    public let prevEntry: AdjacentEntry?
    public let nextEntry: AdjacentEntry?
}

// Short leaf title for prev/next links: "Article 3", "Q. 4", "Thesis 12".
private func shortEntryTitle(_ entry: ConfessionEntry) -> String {
    let title = entry.title ?? ""
    let head = title.range(of: ":").map { String(title[..<$0.lowerBound]) } ?? title
    if head.hasPrefix("Question") {
        return "Q." + head.dropFirst("Question".count)
    }
    return head
}

/// Resolves a document slug + entry id to the entry plus its adjacent leaf
/// entries. Returns nil for unknown documents, unknown ids, or parent ids
/// (chapters/sections don't get their own reading page).
public func getEntryPage(_ slug: String, entryId: String) -> EntryPage? {
    guard let doc = getLibraryDocument(slug), let content = loadConfessionContent(slug) else { return nil }
    guard let item = content.contentById[entryId], !item.isParent else { return nil }

    let leaves = getOrderedLeafEntries(slug)
    guard let index = leaves.firstIndex(where: { $0.id == entryId }) else { return nil }
    func adjacent(_ entry: ConfessionEntry?) -> AdjacentEntry? {
        entry.map { AdjacentEntry(entryId: $0.id, title: shortEntryTitle($0)) }
    }

    return EntryPage(
        item: item, documentTitle: doc.name, slug: slug,
        prevEntry: adjacent(index > 0 ? leaves[index - 1] : nil),
        nextEntry: adjacent(index + 1 < leaves.count ? leaves[index + 1] : nil)
    )
}
