// Network reachability and debug request auditing (TKL-940).
// Keeps offline launches strictly local (no analytics POSTs, ESV fetches or
// card-drafting calls when offline) and lets UI tests observe every URLRequest
// attempted by the app during a cold offline relaunch.
import Foundation
import Network
import OSLog
#if DEBUG
import ObjectiveC
#endif

final class NetworkConnectivity: @unchecked Sendable {
    static let shared = NetworkConnectivity()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.confessionalchristianity.app.connectivity")
    private let lock = NSLock()
    private var status: NWPath.Status?
    private var waiters: [CheckedContinuation<Bool, Never>] = []
    private var listeners: [UUID: AsyncStream<Bool>.Continuation] = [:]

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handleUpdate(path.status)
        }
        monitor.start(queue: queue)
    }

    private func effectiveOnline(_ pathStatus: NWPath.Status) -> Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "OfflineMode") { return false }
        #endif
        return pathStatus == .satisfied
    }

    private func handleUpdate(_ newStatus: NWPath.Status) {
        let (pending, activeListeners, shouldNotify): ([CheckedContinuation<Bool, Never>], [AsyncStream<Bool>.Continuation], Bool) = lock.withLock {
            let changed = status == nil || (status == .satisfied) != (newStatus == .satisfied)
            status = newStatus
            let copy = waiters
            waiters = []
            return (copy, Array(listeners.values), changed)
        }
        let online = effectiveOnline(newStatus)
        for waiter in pending { waiter.resume(returning: online) }
        if shouldNotify {
            for listener in activeListeners { listener.yield(online) }
        }
    }

    private func currentStatus() -> NWPath.Status? {
        lock.withLock { status }
    }

    private func enqueueWaiter(_ continuation: CheckedContinuation<Bool, Never>) {
        let resolved: Bool? = lock.withLock {
            if let status { return effectiveOnline(status) }
            waiters.append(continuation)
            return nil
        }
        if let resolved { continuation.resume(returning: resolved) }
    }

    func isOnline() async -> Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "OfflineMode") { return false }
        #endif
        if let status = currentStatus() {
            return status == .satisfied
        }
        return await withCheckedContinuation { continuation in
            enqueueWaiter(continuation)
        }
    }

    /// Emits the current connectivity state (once known) and each subsequent offline/online transition.
    func onlineUpdates() -> AsyncStream<Bool> {
        let id = UUID()
        return AsyncStream { continuation in
            let current: Bool? = lock.withLock {
                listeners[id] = continuation
                return status.map { effectiveOnline($0) }
            }
            if let current {
                continuation.yield(current)
            }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { _ = self?.listeners.removeValue(forKey: id) }
            }
        }
    }
}

#if DEBUG
enum NetworkAudit {
    private static let logger = Logger(subsystem: "com.confessionalchristianity.app", category: "network-audit")

    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var auditURL: URL?
        private var swizzled = false

        func arm(url: URL) -> Bool {
            lock.withLock {
                auditURL = url
                let shouldSwizzle = !swizzled
                swizzled = true
                return shouldSwizzle
            }
        }

        var isActive: Bool { lock.withLock { auditURL != nil } }

        func append(_ line: String) {
            lock.withLock {
                guard let url = auditURL else { return }
                if let handle = try? FileHandle(forWritingTo: url) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: Data(line.utf8))
                } else {
                    try? Data(line.utf8).write(to: url, options: .atomic)
                }
            }
        }
    }

    private static let state = State()

    /// Arms request logging when launched with `-NetworkAuditFile <host path>`.
    /// Writes `<path>.armed` and clears `<path>` so UI tests can verify both
    /// that auditing was active and that zero requests were attempted.
    /// Installs `NetworkAuditProtocol` on `URLSession.shared` and swizzles
    /// `URLSessionConfiguration.default` / `.ephemeral` so SDK sessions (including
    /// Amplify/Cognito) are observed too.
    static func installIfConfigured() {
        guard let raw = UserDefaults.standard.string(forKey: "NetworkAuditFile")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return }
        let url = URL(fileURLWithPath: raw)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? Data().write(to: url, options: .atomic)
        let armed = url.appendingPathExtension("armed")
        try? Data("armed\n".utf8).write(to: armed, options: .atomic)
        let shouldSwizzle = state.arm(url: url)
        URLProtocol.registerClass(NetworkAuditProtocol.self)
        if shouldSwizzle {
            if let orig = class_getClassMethod(URLSessionConfiguration.self, #selector(getter: URLSessionConfiguration.default)),
               let repl = class_getClassMethod(URLSessionConfiguration.self, #selector(URLSessionConfiguration.cc_auditDefault)) {
                method_exchangeImplementations(orig, repl)
            }
            if let orig = class_getClassMethod(URLSessionConfiguration.self, #selector(getter: URLSessionConfiguration.ephemeral)),
               let repl = class_getClassMethod(URLSessionConfiguration.self, #selector(URLSessionConfiguration.cc_auditEphemeral)) {
                method_exchangeImplementations(orig, repl)
            }
        }
        logger.notice("network audit armed at \(raw, privacy: .public)")
    }

    /// Attaches the audit protocol to non-shared URLSession configurations
    /// (such as ephemeral sessions used by LoopCounter and EsvClient).
    static func configure(_ configuration: URLSessionConfiguration) {
        guard state.isActive else { return }
        var classes = configuration.protocolClasses ?? []
        if !classes.contains(where: { $0 == NetworkAuditProtocol.self }) {
            classes.insert(NetworkAuditProtocol.self, at: 0)
            configuration.protocolClasses = classes
        }
    }

    fileprivate static func record(_ request: URLRequest) {
        guard state.isActive else { return }
        let method = request.httpMethod ?? "GET"
        let target = request.url?.absoluteString ?? "unknown"
        let line = "\(method) \(target)\n"
        logger.notice("network request: \(line, privacy: .public)")
        state.append(line)
    }
}

final class NetworkAuditProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        NetworkAudit.record(request)
        return false
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {}
    override func stopLoading() {}
}

private extension URLSessionConfiguration {
    @objc class func cc_auditDefault() -> URLSessionConfiguration {
        let config = cc_auditDefault()
        NetworkAudit.configure(config)
        return config
    }

    @objc class func cc_auditEphemeral() -> URLSessionConfiguration {
        let config = cc_auditEphemeral()
        NetworkAudit.configure(config)
        return config
    }
}
#endif
