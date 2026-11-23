// The call that drafts cards from Sunday's notes (TKL-863): `POST
// /api/lords-day/cards` on the website (contract in src/lib/lordsDay/handler.ts),
// read as an NDJSON stream so cards appear as each page is read. The model key
// lives on the server; the app sends the photos (or typed notes) and an
// account token, and gets drafts back. Nothing here stores anything: the
// review (DomainKit's LordsDayReview) decides what is kept.
import Foundation
import DomainKit

enum CardsGeneratorError: Error, Equatable {
    /// The endpoint needs a signed-in account's token, and there is none.
    case accountNeeded
    case rateLimited
    case offline
    case failed
}

protocol CardsGenerator: Sendable {
    func draft(_ request: LordsDayCardsRequest) -> AsyncThrowingStream<LordsDayCardsEvent, Error>
}

struct LiveCardsGenerator: CardsGenerator {
    static let endpoint = URL(string: "\(WebLinks.base)/api/lords-day/cards")!

    /// The account's Cognito access token. Not wired to AuthService yet
    /// (TKL-940), so this returns nil and drafting says it needs an account.
    var accessToken: @Sendable () async -> String? = { nil }
    var session: URLSession = .shared

    func draft(_ request: LordsDayCardsRequest) -> AsyncThrowingStream<LordsDayCardsEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    #if DEBUG
                    if UserDefaults.standard.bool(forKey: "EsvOffline") { throw CardsGeneratorError.offline }
                    #endif
                    guard let token = await accessToken() else { throw CardsGeneratorError.accountNeeded }
                    var http = URLRequest(url: Self.endpoint, timeoutInterval: 120)
                    http.httpMethod = "POST"
                    http.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    http.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    http.httpBody = try request.body()
                    let (bytes, response) = try await session.bytes(for: http)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    switch status {
                    case 200: break
                    case 401: throw CardsGeneratorError.accountNeeded
                    case 429: throw CardsGeneratorError.rateLimited
                    default: throw CardsGeneratorError.failed
                    }
                    for try await line in bytes.lines {
                        if let event = try? LordsDayCardsEvent.parse(line: line) { continuation.yield(event) }
                    }
                    continuation.finish()
                } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost].contains(error.code) {
                    continuation.finish(throwing: CardsGeneratorError.offline)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

#if DEBUG
/// Screenshot hook: replays a sample sermon's drafts with a pause between
/// pages. `stopsAfter` ends the stream there and never finishes, to show the
/// review mid-fill.
struct FixtureCardsGenerator: CardsGenerator {
    var stopsAfter: Int?
    var delay: Duration = .milliseconds(450)

    static let sample: [[DraftCardPayload]] = [
        [
            DraftCardPayload(kind: "key_point", page: 0, order: 0, text: "God's purpose, not my circumstances, decides what is good."),
            DraftCardPayload(kind: "verse", page: 0, order: 1, reference: "Romans 8:28", osis: "Rom.8.28"),
        ],
        [
            DraftCardPayload(kind: "quote", page: 1, order: 0, text: "The golden chain has no weak link, because God forged every one.", attribution: "Rev. [your pastor]"),
            DraftCardPayload(kind: "key_point", page: 1, order: 1, text: "“Glorified” is in the past tense. Worship like it is already settled."),
        ],
        [
            DraftCardPayload(kind: "quote", page: 2, order: 0, text: "Your worst day is not outside his purpose.", attribution: "Rev. [your pastor]"),
        ],
    ]

    func draft(_ request: LordsDayCardsRequest) -> AsyncThrowingStream<LordsDayCardsEvent, Error> {
        let pages = Self.sample
        let stopsAfter = stopsAfter
        let delay = delay
        return AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.started(pages: pages.count))
                for (index, cards) in pages.enumerated() {
                    try? await Task.sleep(for: delay)
                    if let stopsAfter, index >= stopsAfter {
                        // Mid-fill: stay open, as a slow page would.
                        try? await Task.sleep(for: .seconds(3600))
                        return
                    }
                    continuation.yield(.page(index))
                    for card in cards { continuation.yield(.card(card)) }
                }
                continuation.yield(.done(failedPages: []))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
#endif
