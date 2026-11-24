import Foundation
import Testing
@testable import DomainKit

/// TKL-947: the Lord's Day loop's three events, and nothing else, reach PostHog.
/// Each event's body is asserted byte for byte, so no note text, card text,
/// photo, reference, preacher, church or email can ever ride along.
@Suite struct LoopAnalyticsTests {
    private let config = LoopAnalyticsConfig(apiKey: "phc_test", host: URL(string: "https://us.i.posthog.com")!, environment: "release")
    private let installId = "0F8B7C1E-2D3A-4B5C-9D8E-7F6A5B4C3D2E"
    /// 15 Nov 2026 14:00 UTC.
    private let at = Date(timeIntervalSince1970: 1_794_751_200)

    private func body(_ event: LoopEvent) throws -> String {
        let request = try #require(LoopAnalytics.captureRequest(event, config: config, installId: installId, at: at))
        let data = try #require(request.httpBody)
        return String(decoding: data, as: UTF8.self)
    }

    /// Keys are sorted, so `before` lands ahead of "env" and `after` behind it.
    private func expected(_ event: String, before: String = "", after: String = "") -> String {
        #"{"api_key":"phc_test","distinct_id":"\#(installId)","event":"\#(event)","properties":{"$geoip_disable":true,"$lib":"cc-ios","$process_person_profile":false,\#(before)"env":"release"\#(after)},"timestamp":"2026-11-15T14:00:00Z"}"#
    }

    @Test func sermonKeptSendsOnlyTheCardCount() throws {
        #expect(try body(.sermonKept(cardCount: 5)) == expected("lords_day_sermon_kept", before: #""card_count":5,"#))
    }

    @Test func dayOpenedSendsNoProperties() throws {
        #expect(try body(.dayOpened) == expected("lords_day_day_opened"))
    }

    @Test(arguments: [(CardKind.keyPoint, "key_point"), (.quote, "quote"), (.verse, "verse")])
    func cardSharedSendsOnlyTheKind(kind: CardKind, raw: String) throws {
        #expect(try body(.cardShared(kind: kind)) == expected("lords_day_card_shared", after: #","kind":"\#(raw)""#))
    }

    @Test func requestPostsJSONToTheCaptureEndpoint() throws {
        let request = try #require(LoopAnalytics.captureRequest(.dayOpened, config: config, installId: installId, at: at))
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://us.i.posthog.com/i/v0/e/")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        // No cookies, no account token.
        #expect(request.httpShouldHandleCookies == false)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func configNeedsAKeyAndAnHTTPSHost() {
        #expect(LoopAnalyticsConfig(info: ["PostHogKey": "phc_x", "PostHogHost": "https://us.i.posthog.com"], environment: "debug") != nil)
        #expect(LoopAnalyticsConfig(info: ["PostHogKey": "", "PostHogHost": "https://us.i.posthog.com"], environment: "debug") == nil)
        #expect(LoopAnalyticsConfig(info: ["PostHogKey": "$(POSTHOG_KEY)", "PostHogHost": "https://us.i.posthog.com"], environment: "debug") == nil)
        #expect(LoopAnalyticsConfig(info: ["PostHogKey": "phc_x", "PostHogHost": "http://us.i.posthog.com"], environment: "debug") == nil)
        #expect(LoopAnalyticsConfig(info: [:], environment: "debug") == nil)
    }

    // MARK: The recorder

    private final class Sent: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [URLRequest] = []
        func add(_ r: URLRequest) { lock.lock(); items.append(r); lock.unlock() }
        var all: [URLRequest] { lock.lock(); defer { lock.unlock() }; return items }
    }

    private func defaults() -> UserDefaults {
        let name = "LoopAnalyticsTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func decoded(_ r: URLRequest) throws -> [String: Any] {
        let data = try #require(r.httpBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func oneRandomInstallIdIsKeptAcrossEvents() async throws {
        let sent = Sent()
        let store = defaults()
        let analytics = LoopAnalytics(config: config, defaults: store) { sent.add($0); return 200 }
        #expect(await analytics.record(.sermonKept(cardCount: 3)) == 200)
        #expect(await analytics.record(.cardShared(kind: .quote)) == 200)
        let ids = try sent.all.map { try decoded($0)["distinct_id"] as? String }
        #expect(ids.count == 2)
        #expect(ids[0] == ids[1])
        #expect(UUID(uuidString: ids[0] ?? "") != nil)
        // A second recorder on the same install sends the same id.
        let again = LoopAnalytics(config: config, defaults: store) { sent.add($0); return 200 }
        _ = await again.record(.dayOpened)
        #expect(try decoded(sent.all[2])["distinct_id"] as? String == ids[0])
    }

    @Test func withoutAConfigNothingIsSent() async {
        let sent = Sent()
        let analytics = LoopAnalytics(config: nil, defaults: defaults()) { sent.add($0); return 200 }
        #expect(await analytics.record(.dayOpened) == nil)
        #expect(sent.all.isEmpty)
    }

    @Test func aFailedSendIsSwallowed() async {
        struct Offline: Error {}
        let analytics = LoopAnalytics(config: config, defaults: defaults()) { _ in throw Offline() }
        #expect(await analytics.record(.cardShared(kind: .verse)) == nil)
    }

    @Test func dayOpenedIsCountedOncePerLocalDay() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        func local(_ d: Int, _ h: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h))! }
        let sent = Sent()
        let analytics = LoopAnalytics(config: config, defaults: defaults()) { sent.add($0); return 200 }
        #expect(await analytics.recordDayOpened(now: local(16, 7), calendar: calendar) == 200)
        #expect(await analytics.recordDayOpened(now: local(16, 21), calendar: calendar) == nil)
        #expect(await analytics.recordDayOpened(now: local(17, 0), calendar: calendar) == 200)
        #expect(sent.all.count == 2)
    }

    @Test func aFailedDayOpenedIsTriedAgainThatDay() async {
        struct Offline: Error {}
        let store = defaults()
        let failing = LoopAnalytics(config: config, defaults: store) { _ in throw Offline() }
        #expect(await failing.recordDayOpened(now: at, calendar: .current) == nil)
        let working = LoopAnalytics(config: config, defaults: store) { _ in 200 }
        #expect(await working.recordDayOpened(now: at, calendar: .current) == 200)
    }
}
