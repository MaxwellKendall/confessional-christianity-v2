// The call that drafts cards from Sunday's notes (TKL-863, wired to Cognito in
// TKL-940): `POST /api/lords-day/cards` on the website (contract in
// src/lib/lordsDay/handler.ts), read as an NDJSON stream so cards appear as each
// page is read. The model key lives on the server; the app sends the photos (or
// typed notes) and a refreshed Cognito access token, and gets drafts back.
// Nothing here stores anything: the review (DomainKit's LordsDayReview) decides
// what is kept.
import Foundation
import OSLog
import DomainKit

enum CardsGeneratorError: Error, Equatable {
    /// The endpoint needs a signed-in account's token, and there is none.
    case accountNeeded
    case rateLimited
    case offline
    case failed
    /// The model had nothing usable to offer for this card; the original stays.
    case noCard
}

protocol CardsGenerator: Sendable {
    func draft(_ request: LordsDayCardsRequest) -> AsyncThrowingStream<LordsDayCardsEvent, Error>
    /// One replacement card, drafted from text already transcribed (TKL-1053).
    func redraft(_ request: LordsDayRedraftRequest) async throws -> DraftCardPayload
}

struct LiveCardsGenerator: CardsGenerator {
    private static let logger = Logger(subsystem: "com.confessionalchristianity.app", category: "lords-day")

    /// Release always hits the hosted endpoint; DEBUG allows `-LordsDayCardsEndpoint <url>`
    /// to point the simulator at a local dev server configured for the dev Cognito pool.
    static var endpoint: URL {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "LordsDayCardsEndpoint")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty, let url = URL(string: raw) {
            return url
        }
        #endif
        return URL(string: "\(WebLinks.base)/api/lords-day/cards")!
    }

    static var redraftEndpoint: URL {
        URL(string: "\(endpoint.absoluteString)/redraft")!
    }

    /// Provides the signed-in session's Cognito access token (`forceRefresh` requests a fresh token after a 401).
    var accessToken: @Sendable (_ forceRefresh: Bool) async -> String? = { _ in nil }
    var session: URLSession = .shared

    func draft(_ request: LordsDayCardsRequest) -> AsyncThrowingStream<LordsDayCardsEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    #if DEBUG
                    if UserDefaults.standard.bool(forKey: "EsvOffline") { throw CardsGeneratorError.offline }
                    #endif
                    guard await NetworkConnectivity.shared.isOnline() else { throw CardsGeneratorError.offline }
                    guard let initialToken = await accessToken(false) else { throw CardsGeneratorError.accountNeeded }
                    let body = try request.body()
                    let startedAt = ContinuousClock.now
                    var (bytes, status) = try await post(body: body, token: initialToken)
                    if status == 401, let refreshed = await accessToken(true) {
                        (bytes, status) = try await post(body: body, token: refreshed)
                    }
                    switch status {
                    case 200: break
                    case 401: throw CardsGeneratorError.accountNeeded
                    case 429: throw CardsGeneratorError.rateLimited
                    default: throw CardsGeneratorError.failed
                    }
                    var firstCardSeconds: Double?
                    var cardCount = 0
                    for try await line in bytes.lines {
                        guard let event = try? LordsDayCardsEvent.parse(line: line) else { continue }
                        if case .card = event {
                            cardCount += 1
                            if firstCardSeconds == nil {
                                firstCardSeconds = Self.seconds(since: startedAt)
                            }
                        }
                        if case .done(let failedPages) = event {
                            let doneSeconds = Self.seconds(since: startedAt)
                            let cost = Self.parseCostUsd(from: line)
                            Self.logger.notice("draft done cards=\(cardCount) failedPages=\(failedPages.count) firstCardSec=\(firstCardSeconds ?? -1, format: .fixed(precision: 2)) doneSec=\(doneSeconds, format: .fixed(precision: 2)) costUsd=\(cost ?? -1, format: .fixed(precision: 5))")
                        }
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost].contains(error.code) {
                    continuation.finish(throwing: CardsGeneratorError.offline)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func redraft(_ request: LordsDayRedraftRequest) async throws -> DraftCardPayload {
        guard await NetworkConnectivity.shared.isOnline() else { throw CardsGeneratorError.offline }
        guard let initial = await accessToken(false) else { throw CardsGeneratorError.accountNeeded }
        let body = try request.body()
        var (data, status) = try await postJSON(body: body, token: initial)
        if status == 401, let refreshed = await accessToken(true) {
            (data, status) = try await postJSON(body: body, token: refreshed)
        }
        switch status {
        case 200: break
        case 401: throw CardsGeneratorError.accountNeeded
        case 422: throw CardsGeneratorError.noCard
        case 429: throw CardsGeneratorError.rateLimited
        default: throw CardsGeneratorError.failed
        }
        struct Reply: Decodable { let card: DraftCardPayload }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { throw CardsGeneratorError.failed }
        return reply.card
    }

    private func postJSON(body: Data, token: String) async throws -> (Data, Int) {
        var http = URLRequest(url: Self.redraftEndpoint, timeoutInterval: 90)
        http.httpMethod = "POST"
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        http.httpBody = body
        let (data, response) = try await session.data(for: http)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private func post(body: Data, token: String) async throws -> (URLSession.AsyncBytes, Int) {
        var http = URLRequest(url: Self.endpoint, timeoutInterval: 120)
        http.httpMethod = "POST"
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        http.httpBody = body
        let (bytes, response) = try await session.bytes(for: http)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (bytes, status)
    }

    private static func seconds(since start: ContinuousClock.Instant) -> Double {
        let d = start.duration(to: ContinuousClock.now)
        return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }

    private static func parseCostUsd(from line: String) -> Double? {
        struct DoneCost: Decodable { let costUsd: Double? }
        return (try? JSONDecoder().decode(DoneCost.self, from: Data(line.utf8)))?.costUsd
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

    /// A fixture redraft: the next sample card of the same kind, so the review
    /// screen can be exercised without the network.
    func redraft(_ request: LordsDayRedraftRequest) async throws -> DraftCardPayload {
        try? await Task.sleep(for: delay)
        let all = Self.sample.flatMap { $0 }
        let candidates = request.kind.map { kind in all.filter { $0.kind == kind.rawValue } } ?? all
        guard let card = candidates.first(where: { card in
            !request.avoid.contains(card.text ?? card.reference ?? "")
        }) else { throw CardsGeneratorError.noCard }
        return card
    }

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
                    continuation.yield(.page(index, cardCount: cards.count))
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
