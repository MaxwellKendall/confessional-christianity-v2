// Sign-out flush (TKL-1084): before a confirmed sign-out clears this iPhone's
// account data, try one push of the outbox with a short timeout so changes
// made offline or just before the debounced push reach the account. When the
// push can't finish, the confirmation sheet says those changes will be removed
// instead of promising that everything is kept.
import Foundation

/// What the pre-sign-out push achieved.
public enum SignOutFlushOutcome: Equatable, Sendable {
    /// The outbox was already empty.
    case nothingPending
    /// Every queued change reached the account.
    case pushed
    /// The push failed, timed out or was permanently rejected by the server;
    /// `count` changes are still only on this iPhone.
    case unsynced(count: Int)
}

@MainActor
public enum SignOutFlush {
    /// Long enough for one AppSync round trip on a slow connection, short
    /// enough that sign-out still feels immediate.
    nonisolated public static let defaultTimeout: Duration = .seconds(4)

    /// Pushes `engine`'s outbox once. Never throws and never waits longer
    /// than `timeout`: on timeout the push is cancelled, and the engine drops
    /// any late acknowledgement, so the outbox is left as it was. Changes the
    /// server rejects for good stay in the outbox and count as unsynced.
    public static func run(_ engine: SyncEngine, timeout: Duration = defaultTimeout) async -> SignOutFlushOutcome {
        guard let before = try? engine.pendingChanges().count else { return .unsynced(count: 0) }
        if before == 0 { return .nothingPending }

        let gate = Gate()
        let pushTask = Task { @MainActor in
            do {
                try await engine.push(keepingRejected: true)
                gate.finish(true)
            } catch {
                gate.finish(false)
            }
        }
        let timer = Task { @MainActor in
            try? await Task.sleep(for: timeout)
            if !Task.isCancelled {
                pushTask.cancel()
                gate.finish(false)
            }
        }
        let succeeded = await gate.wait()
        timer.cancel()
        pushTask.cancel()

        let remaining = (try? engine.pendingChanges().count) ?? before
        if succeeded && remaining == 0 { return .pushed }
        return .unsynced(count: remaining)
    }

    /// Resolves once with the first result, from either the push or the timer.
    @MainActor
    private final class Gate {
        private var result: Bool?
        private var continuation: CheckedContinuation<Bool, Never>?

        func finish(_ value: Bool) {
            guard result == nil else { return }
            result = value
            continuation?.resume(returning: value)
            continuation = nil
        }

        func wait() async -> Bool {
            if let result { return result }
            return await withCheckedContinuation { continuation = $0 }
        }
    }
}

/// The sign-out confirmation sheet's words, by flush outcome (nil: no attempt yet).
public enum SignOutConfirmationCopy {
    public static let kept = "Everything is kept in your account. This iPhone goes back to using the app without an account, and your synced children, catechism progress and Lord’s Day notes are removed from it until you sign in again."

    public static func body(for outcome: SignOutFlushOutcome?) -> String {
        guard case .unsynced(let count) = outcome else { return kept }
        let changes = count == 1
            ? "1 change on this iPhone hasn’t synced yet"
            : count > 1 ? "\(count) changes on this iPhone haven’t synced yet" : "Some changes on this iPhone haven’t synced yet"
        return "\(changes) and will be removed if you sign out now. Everything else is kept in your account. Connect to the internet and try again to keep them."
    }

    public static func confirmTitle(for outcome: SignOutFlushOutcome?) -> String {
        if case .unsynced = outcome { return "Sign out anyway" }
        return "Sign out"
    }
}
