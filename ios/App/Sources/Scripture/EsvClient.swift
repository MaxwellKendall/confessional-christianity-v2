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
