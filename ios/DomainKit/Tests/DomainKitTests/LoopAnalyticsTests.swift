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

    /// Holds the first send until `open()` (later ones go straight through), and counts sends started.
    private actor Gate {
        private var waiting: [CheckedContinuation<Void, Never>] = []
        private var isOpen = false
        private(set) var started = 0
        func pass() async {
            started += 1
            if isOpen || started > 1 { return }
            await withCheckedContinuation { waiting.append($0) }
        }
        func open() { isOpen = true; waiting.forEach { $0.resume() }; waiting = [] }
    }

    private func waitUntil(_ gate: Gate, started n: Int) async {
        while await gate.started < n { await Task.yield() }
    }

    @Test func overlappingDayOpenedCallsSendOnce() async throws {
        let sent = Sent()
        let gate = Gate()
        let analytics = LoopAnalytics(config: config, defaults: defaults()) { r in
            await gate.pass(); sent.add(r); return 200
        }
        // The first call is still waiting on the network when the feed appears again.
        let first = Task { await analytics.recordDayOpened(now: at, calendar: .current) }
        await waitUntil(gate, started: 1)
        let second = await analytics.recordDayOpened(now: at, calendar: .current)
        await gate.open()
        #expect(await first.value == 200)
        #expect(second == nil)
        #expect(sent.all.count == 1)
        #expect(await gate.started == 1)
    }

    @Test func aFailedOverlappingDayOpenedReleasesTheDay() async {
        struct Offline: Error {}
        let gate = Gate()
        let fails = Sent()
        let analytics = LoopAnalytics(config: config, defaults: defaults()) { r in
            await gate.pass()
            if fails.all.isEmpty { fails.add(r); throw Offline() }
            return 200
        }
        let first = Task { await analytics.recordDayOpened(now: at, calendar: .current) }
        await waitUntil(gate, started: 1)
        #expect(await analytics.recordDayOpened(now: at, calendar: .current) == nil)
        await gate.open()
        #expect(await first.value == nil)
        // The failed send gave the day back, so the next opening counts it.
        #expect(await analytics.recordDayOpened(now: at, calendar: .current) == 200)
    }

    /// Holds each of the first `held` sends until `release(n)` (n counts sends from 0); later ones go
    /// straight through. Lets a test finish overlapping sends in any order.
    private actor Gates {
        private let held: Int
        private var waiting: [Int: CheckedContinuation<Void, Never>] = [:]
        private var released: Set<Int> = []
        private(set) var started = 0
        init(held: Int) { self.held = held }
        func pass() async {
            let n = started
            started += 1
            if n >= held || released.contains(n) { return }
            await withCheckedContinuation { waiting[n] = $0 }
        }
        func release(_ n: Int) { released.insert(n); waiting.removeValue(forKey: n)?.resume() }
    }

    private func waitUntil(_ gates: Gates, started n: Int) async {
        while await gates.started < n { await Task.yield() }
    }

    /// One minute before and one minute after local midnight on 16/17 November 2026.
    private func aroundMidnight() -> (calendar: Calendar, before: Date, after: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 11, day: 17))!
        return (calendar, midnight.addingTimeInterval(-60), midnight.addingTimeInterval(60))
    }

    @Test func aNewerDaySucceedingFirstAcrossMidnightIsNotCountedAgain() async {
        let (calendar, before, after) = aroundMidnight()
        let gates = Gates(held: 2)
        let analytics = LoopAnalytics(config: config, defaults: defaults()) { _ in await gates.pass(); return 200 }
        let older = Task { await analytics.recordDayOpened(now: before, calendar: calendar) }
        await waitUntil(gates, started: 1)
        let newer = Task { await analytics.recordDayOpened(now: after, calendar: calendar) }
        await waitUntil(gates, started: 2)
        // The newer send finishes first, then the older one.
        await gates.release(1)
        #expect(await newer.value == 200)
        await gates.release(0)
        #expect(await older.value == 200)
        // Opening the feed again on the newer date sends nothing.
        #expect(await analytics.recordDayOpened(now: after.addingTimeInterval(3600), calendar: calendar) == nil)
        #expect(await gates.started == 2)
    }

    @Test func aPendingNewerDayIsStillReservedAfterTheOlderSendFinishes() async {
        let (calendar, before, after) = aroundMidnight()
        let gates = Gates(held: 2)
        let analytics = LoopAnalytics(config: config, defaults: defaults()) { _ in await gates.pass(); return 200 }
        let older = Task { await analytics.recordDayOpened(now: before, calendar: calendar) }
        await waitUntil(gates, started: 1)
        let newer = Task { await analytics.recordDayOpened(now: after, calendar: calendar) }
        await waitUntil(gates, started: 2)
        // The older send finishes while the newer one is still pending.
        await gates.release(0)
        #expect(await older.value == 200)
        #expect(await analytics.recordDayOpened(now: after.addingTimeInterval(60), calendar: calendar) == nil)
        await gates.release(1)
        #expect(await newer.value == 200)
        // Exactly one capture per date.
        #expect(await analytics.recordDayOpened(now: after.addingTimeInterval(3600), calendar: calendar) == nil)
        #expect(await analytics.recordDayOpened(now: before, calendar: calendar) == nil)
        #expect(await gates.started == 2)
    }

    @Test func aFailedNewerDayAcrossMidnightIsTriedAgainThatDay() async {
        struct Offline: Error {}
        let (calendar, before, after) = aroundMidnight()
        let gates = Gates(held: 2)
        let analytics = LoopAnalytics(config: config, defaults: defaults()) { r in
            await gates.pass()
            // Only the newer day's first send (00:01 local = 05:01Z) fails.
            if r.httpBody.map({ String(decoding: $0, as: UTF8.self) })?.contains("T05:01:00Z") == true {
                throw Offline()
            }
            return 200
        }
        let older = Task { await analytics.recordDayOpened(now: before, calendar: calendar) }
        await waitUntil(gates, started: 1)
        let newer = Task { await analytics.recordDayOpened(now: after, calendar: calendar) }
        await waitUntil(gates, started: 2)
        await gates.release(1)
        #expect(await newer.value == nil)
        await gates.release(0)
        #expect(await older.value == 200)
        // The newer day's send failed, so the next opening that day sends again.
        #expect(await analytics.recordDayOpened(now: after.addingTimeInterval(60), calendar: calendar) == 200)
        #expect(await analytics.recordDayOpened(now: after.addingTimeInterval(120), calendar: calendar) == nil)
        #expect(await gates.started == 3)
    }

    @Test func aFailedDayOpenedIsTriedAgainThatDay() async {
        struct Offline: Error {}
        let store = defaults()
        let failing = LoopAnalytics(config: config, defaults: store) { _ in throw Offline() }
        #expect(await failing.recordDayOpened(now: at, calendar: .current) == nil)
        let working = LoopAnalytics(config: config, defaults: store) { _ in 200 }
        #expect(await working.recordDayOpened(now: at, calendar: .current) == 200)
    }

    @Test func offlineSkipsAnalyticsTransportWithoutConsumingTheDay() async {
        final class OnlineFlag: @unchecked Sendable {
            private let lock = NSLock()
            private var value = false
            var isOnline: Bool {
                get { lock.lock(); defer { lock.unlock() }; return value }
                set { lock.lock(); value = newValue; lock.unlock() }
            }
        }
        let flag = OnlineFlag()
        let sent = Sent()
        let store = defaults()
        let analytics = LoopAnalytics(config: config, defaults: store, isOnline: { flag.isOnline }) { request in
            sent.add(request)
            return 200
        }
        // Offline launch on a new day: zero requests, and the day stays uncounted.
        #expect(await analytics.recordDayOpened(now: at, calendar: .current) == nil)
        #expect(await analytics.record(.cardShared(kind: .quote), at: at) == nil)
        #expect(sent.all.isEmpty)

        // Back online later the same day: dayOpened now sends once.
        flag.isOnline = true
        #expect(await analytics.recordDayOpened(now: at, calendar: .current) == 200)
        #expect(sent.all.count == 1)
    }
}
