import FlagsmithClient
import Foundation

/// In-memory flags shared between lifecycle refreshes, realtime updates, and evaluations.
final class SnapshotState: @unchecked Sendable {
    struct Snapshot {
        let flags: [String: Flag]?
        let fetchedForIdentity: Bool
    }

    private let lock = NSLock()
    private var flags: [String: Flag]?
    private var fetchedForIdentity = false
    private var generation = 0

    func read() -> Snapshot {
        lock.withLock { Snapshot(flags: flags, fetchedForIdentity: fetchedForIdentity) }
    }

    /// Marks a new refresh; completions carrying an older generation are stale.
    func beginRefresh() -> Int {
        lock.withLock {
            generation += 1
            return generation
        }
    }

    /// Stores a refresh result unless a newer refresh has begun since `generation` was issued.
    func commit(_ fetched: [String: Flag], fetchedForIdentity: Bool, generation: Int) -> Bool {
        lock.withLock {
            guard generation == self.generation else { return false }
            flags = fetched
            self.fetchedForIdentity = fetchedForIdentity
            return true
        }
    }

    /// Replaces the snapshot with a pushed update and returns the names whose flags differ, or nil when nothing changed.
    /// An update arriving before the first fetch completes counts every pushed flag as changed.
    func apply(update: [String: Flag]) -> Set<String>? {
        lock.withLock {
            let previous = flags ?? [:]
            guard update != previous else { return nil }
            flags = update
            return Set(previous.keys).union(update.keys).filter { previous[$0] != update[$0] }
        }
    }
}
