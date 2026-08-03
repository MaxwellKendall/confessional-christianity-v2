// Reflections are the long-form essays (v1 "commentary"), authored as
// content/commentary/<entryId>.md and surfaced at /reflections/[slug] on
// web — ported from src/lib/reflections.ts and src/lib/commentary.ts. Unlike
// most bundled content here, the set of essays is genuinely open-ended (new
// files land over time), so this reads the whole bundled directory rather
// than working off a fixed manifest.
import Foundation

public struct Reflection: Equatable, Sendable {
    /// URL slug for /reflections/[slug]; frontmatter `slug` or kebab-cased title.
    public let slug: String
    /// The library entry the essay is written on, e.g. "WSC-1".
    public let entryId: String
    public let title: String
    public let subtitle: String?
    public let author: String?
    public let authorSlug: String?
    /// ISO date string (YYYY-MM-DD) or nil.
    public let date: String?
    /// Optional series name + part for grouped essays.
    public let series: String?
    public let part: Int?
    /// Markdown body.
    public let body: String
}

public struct Author: Equatable, Sendable {
    public let slug: String
    public let name: String
    public let reflections: [Reflection]
}

public func slugify(_ value: String) -> String {
    let lowered = value.lowercased().replacingOccurrences(of: "['\u{2019}]", with: "", options: .regularExpression)
    let dashed = lowered.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
    return dashed.replacingOccurrences(of: "^-+|-+$", with: "", options: .regularExpression)
}

// Minimal frontmatter parser: flat `key: value` lines between a pair of
// `---` delimiters, then the remaining markdown body. No nested structures
// are needed for this content (title/subtitle/author/date/slug/series/part).
private func parseFrontmatter(_ raw: String) -> (fields: [String: String], body: String) {
    var lines = raw.components(separatedBy: .newlines)
    guard lines.first == "---" else { return ([:], raw) }
    lines.removeFirst()
    var fields: [String: String] = [:]
    var i = 0
    while i < lines.count, lines[i] != "---" {
        let line = lines[i]
        if let colon = line.firstIndex(of: ":") {
            let key = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            fields[key] = value
        }
        i += 1
    }
    let body = i + 1 < lines.count ? lines[(i + 1)...].joined(separator: "\n") : ""
    return (fields, body.trimmingCharacters(in: .newlines))
}

private func parseReflection(entryId: String, raw: String) -> Reflection {
    let (fields, body) = parseFrontmatter(raw)
    let title = fields["title"] ?? entryId
    let author = fields["author"]
    let part = fields["part"].flatMap(Int.init)
    return Reflection(
        slug: fields["slug"] ?? slugify(title),
        entryId: entryId,
        title: title,
        subtitle: fields["subtitle"],
        author: author,
        authorSlug: author.map(slugify),
        date: fields["date"],
        series: fields["series"],
        part: part,
        body: body
    )
}

private func loadReflectionsFromBundle() -> [Reflection] {
    guard let urls = Bundle.module.urls(forResourcesWithExtension: "md", subdirectory: "BundledContent/content/commentary") else {
        return []
    }
    let posts = urls.compactMap { url -> Reflection? in
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let entryId = url.deletingPathExtension().lastPathComponent
        return parseReflection(entryId: entryId, raw: raw)
    }
    // newest first, the reflections-index order.
    return posts.sorted { ($0.date ?? "") > ($1.date ?? "") }
}

private let allReflections: [Reflection] = loadReflectionsFromBundle()

public func loadReflections() -> [Reflection] { allReflections }

public func getReflectionBySlug(_ slug: String) -> Reflection? {
    allReflections.first { $0.slug == slug }
}

public func getReflectionByEntryId(_ entryId: String) -> Reflection? {
    allReflections.first { $0.entryId == entryId }
}

/// Entry ids that have a commentary post, for the Library TOC's "†" marker.
public func listCommentaryIds() -> Set<String> {
    Set(allReflections.map { $0.entryId })
}

public func listAuthors() -> [Author] {
    var order: [String] = []
    var bySlug: [String: (name: String, reflections: [Reflection])] = [:]
    for post in allReflections {
        guard let author = post.author, let authorSlug = post.authorSlug else { continue }
        if bySlug[authorSlug] != nil {
            bySlug[authorSlug]?.reflections.append(post)
        } else {
            bySlug[authorSlug] = (author, [post])
            order.append(authorSlug)
        }
    }
    return order.map { slug in
        let entry = bySlug[slug]!
        return Author(slug: slug, name: entry.name, reflections: entry.reflections)
    }
}
