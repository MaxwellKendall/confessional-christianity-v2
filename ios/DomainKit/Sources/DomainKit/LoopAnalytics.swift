// Counting the Lord's Day loop (TKL-947): a sermon kept, a day of the week
// opened, a card shared. Three events and nothing else go to PostHog's capture
// endpoint, straight over HTTPS with no SDK, so nothing is collected
// automatically (no device model, no screen views, no session replay).
//
// What is sent is fixed by `captureRequest`, and the tests assert every
// event's body byte for byte: the event name, a card count or a card kind,
// a random per-install id that is never tied to the account, and flags that
// turn off PostHog's person profiles and IP geolocation. Never note text,
// card text, photos, references, the preacher, the church or an email.
import Foundation

public enum LoopEvent: Equatable, Sendable {
    /// "Add N cards to my week" succeeded.
    case sermonKept(cardCount: Int)
    /// The week's card feed was on screen; counted once per local day.
    case dayOpened
    /// The share sheet was opened from a card in the feed.
    case cardShared(kind: CardKind)

    public var name: String {
        switch self {
        case .sermonKept: "lords_day_sermon_kept"
        case .dayOpened: "lords_day_day_opened"
        case .cardShared: "lords_day_card_shared"
        }
    }
}

public struct LoopAnalyticsConfig: Equatable, Sendable {
    public let apiKey: String
    public let host: URL
    /// "debug" or "release", so simulator and development runs can be filtered out.
    public let environment: String

    public init(apiKey: String, host: URL, environment: String) {
        self.apiKey = apiKey
        self.host = host
        self.environment = environment
    }

    /// From the app's Info.plist (`PostHogKey`, `PostHogHost`); nil when either is
    /// missing, unexpanded, or the host isn't HTTPS, so nothing is ever sent.
    public init?(info: [String: Any], environment: String) {
        guard let key = (info["PostHogKey"] as? String)?.trimmingCharacters(in: .whitespaces),
              !key.isEmpty, !key.hasPrefix("$("),
              let hostString = info["PostHogHost"] as? String,
              let host = URL(string: hostString), host.scheme == "https", host.host != nil
        else { return nil }
        self.init(apiKey: key, host: host, environment: environment)
    }
}

public actor LoopAnalytics {
    /// Sends a request and returns its HTTP status.
    public typealias Transport = @Sendable (URLRequest) async throws -> Int

    static let installIdKey = "LoopAnalyticsInstallId"
    static let lastDayOpenedKey = "LoopAnalyticsLastDayOpened"

    private let config: LoopAnalyticsConfig?
    private let defaults: UserDefaults
    private let transport: Transport
    /// The day whose `dayOpened` send is in flight. The actor can take another call while a
    /// send awaits the network, so the day is reserved before the await, not saved after it.
    private var dayOpenedInFlight: String?

    public init(config: LoopAnalyticsConfig?, defaults: UserDefaults = .standard, transport: @escaping Transport = LoopAnalytics.urlSession) {
        self.config = config
        self.defaults = defaults
        self.transport = transport
    }

    public static let urlSession: Transport = { request in
        let (_, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }

    /// Sends the event. Returns the HTTP status, or nil when nothing was sent or the send failed.
    /// Never throws: counting must never get in the way of the person using the app.
    @discardableResult
    public func record(_ event: LoopEvent, at date: Date = Date()) async -> Int? {
        guard let config,
              let request = Self.captureRequest(event, config: config, installId: installId(), at: date)
        else { return nil }
        return try? await transport(request)
    }

    /// `dayOpened`, at most once per local calendar day; a failed send is tried again the next time.
    @discardableResult
    public func recordDayOpened(now: Date = Date(), calendar: Calendar = .current) async -> Int? {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        let day = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        guard config != nil, dayOpenedInFlight != day,
              defaults.string(forKey: Self.lastDayOpenedKey) != day else { return nil }
        dayOpenedInFlight = day
        defer { dayOpenedInFlight = nil }
        guard let status = await record(.dayOpened, at: now), (200..<300).contains(status) else { return nil }
        defaults.set(day, forKey: Self.lastDayOpenedKey)
        return status
    }

    /// A random id made on this install, not derived from the device, the account or anything else.
    private func installId() -> String {
        if let id = defaults.string(forKey: Self.installIdKey), UUID(uuidString: id) != nil { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: Self.installIdKey)
        return id
    }

    // MARK: The request

    private enum Value: Encodable, Equatable {
        case bool(Bool), int(Int), string(String)
        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .bool(let b): try c.encode(b)
            case .int(let i): try c.encode(i)
            case .string(let s): try c.encode(s)
            }
        }
    }

    private struct Body: Encodable {
        let api_key: String
        let distinct_id: String
        let event: String
        let properties: [String: Value]
        let timestamp: String
    }

    /// The one place an event becomes bytes. Every key it can send is listed here.
    public static func captureRequest(_ event: LoopEvent, config: LoopAnalyticsConfig, installId: String, at date: Date) -> URLRequest? {
        var properties: [String: Value] = [
            "$process_person_profile": .bool(false),
            "$geoip_disable": .bool(true),
            "$lib": .string("cc-ios"),
            "env": .string(config.environment),
        ]
        switch event {
        case .sermonKept(let count): properties["card_count"] = .int(count)
        case .dayOpened: break
        case .cardShared(let kind): properties["kind"] = .string(kind.rawValue)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let body = Body(api_key: config.apiKey, distinct_id: installId, event: event.name,
                        properties: properties, timestamp: formatter.string(from: date))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(body) else { return nil }

        var request = URLRequest(url: config.host.appendingPathComponent("i/v0/e/"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpShouldHandleCookies = false
        request.timeoutInterval = 15
        request.httpBody = data
        return request
    }
}
