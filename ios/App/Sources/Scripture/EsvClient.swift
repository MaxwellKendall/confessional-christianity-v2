// Fetches proof-text scripture, checking DomainKit's bundled bible-text.json
// (baked in at content-sync time for every osis ref the app can reach — see
// scripts/ios/sync-esv-text.mjs) before falling back to the deployed web
// app's /api/esv proxy — mirrors src/lib/esvClient.ts. The ESV_API_KEY stays
// server-side there (see src/app/api/esv/route.ts's own comment on v1's
// mistake of shipping the key to a client); the app calls the same proxy
// rather than api.esv.org directly. Live fetches are in-memory cached,
// deduped per osis ref for the app's lifetime — the bundled lookup is
// already a synchronous dictionary read, so it isn't cached separately.
import Foundation
import DomainKit

actor EsvClient {
    static let shared = EsvClient()

    private static let baseURL = "https://confessional-christianity-v2.vercel.app/api/esv"

    static let copyrightNotice = "Scripture quotations are from the ESV® Bible (The Holy Bible, English Standard Version®), copyright © 2001 by Crossway, a publishing ministry of Good News Publishers. Used by permission. All rights reserved."

    private static let readerSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()
    private var verseCache: [String: Task<[ReaderVerse]?, Never>] = [:]

    func verses(for osis: String) async -> [ReaderVerse]? {
        if let existing = verseCache[osis] {
            return await existing.value
        }
        let task = Task<[ReaderVerse]?, Never> {
            let verses = await Self.fetchVerses(osis: osis)
            if verses == nil { verseCache[osis] = nil }
            return verses
        }
        verseCache[osis] = task
        return await task.value
    }

    private static func fetchVerses(osis: String) async -> [ReaderVerse]? {
        #if DEBUG
        // Screenshot hook: `-EsvOffline YES` simulates no network for the reader.
        if UserDefaults.standard.bool(forKey: "EsvOffline") { return nil }
        #endif
        guard var components = URLComponents(string: baseURL) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "osis", value: osis),
            URLQueryItem(name: "verses", value: "true")
        ]
        guard let url = components.url else { return nil }
        do {
            let (data, response) = try await readerSession.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let verses = try JSONDecoder().decode(VerseResponse.self, from: data).verses,
                  !verses.isEmpty else { return nil }
            return verses
        } catch {
            return nil
        }
    }

    private struct VerseResponse: Decodable {
        let verses: [ReaderVerse]?
    }

    private var chapterCache: [String: Task<ReaderChapter?, Never>] = [:]

    func chapter(for osis: String) async -> ReaderChapter? {
        if let existing = chapterCache[osis] {
            return await existing.value
        }
        let task = Task<ReaderChapter?, Never> {
            let chapter = await Self.fetchChapter(osis: osis)
            if chapter == nil { chapterCache[osis] = nil }
            return chapter
        }
        chapterCache[osis] = task
        return await task.value
    }

    private static func fetchChapter(osis: String) async -> ReaderChapter? {
        guard var components = URLComponents(string: baseURL) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "osis", value: ReaderChapter.queryOSIS(for: osis)),
            URLQueryItem(name: "formatted", value: "true"),
            URLQueryItem(name: "anchors", value: "true")
        ]
        guard let url = components.url else { return nil }
        do {
            let (data, response) = try await readerSession.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let chapter = try JSONDecoder().decode(ReaderChapter.self, from: data)
            return chapter.matches(osis) ? chapter : nil
        } catch {
            return nil
        }
    }

    private var cache: [String: Task<String?, Never>] = [:]

    func text(for osis: String) async -> String? {
        if let bundled = bundledEsvText(for: osis) {
            return bundled
        }
        if let existing = cache[osis] {
            return await existing.value
        }
        let task = Task<String?, Never> { await Self.fetch(osis: osis) }
        cache[osis] = task
        return await task.value
    }

    private static func fetch(osis: String) async -> String? {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "EsvOffline") { return nil }
        #endif
        guard let encoded = osis.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)?osis=\(encoded)") else {
            return nil
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(EsvResponse.self, from: data).text
        } catch {
            return nil
        }
    }

    private struct EsvResponse: Decodable {
        let citation: String
        let text: String?
    }
}
