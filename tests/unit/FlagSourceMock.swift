import FlagsmithClient
import Foundation

@testable import FlagsmithOpenFeature

/// Scripted stand-in for the Flagsmith client, recording fetches and pushing realtime updates on demand.
final class FlagSourceMock: FlagsmithFlagSource, @unchecked Sendable {
    struct Fetch {
        let identity: String?
        let traits: [String: TypedValue]?
    }

    var result: Result<[Flag], any Error>
    var holdCompletions = false
    private var held: [() -> Void] = []
    private(set) var fetches: [Fetch] = []
    let flagStream: AsyncStream<[Flag]>
    let push: AsyncStream<[Flag]>.Continuation

    init(_ result: Result<[Flag], any Error>) {
        self.result = result
        (flagStream, push) = AsyncStream.makeStream()
    }

    func getFeatureFlags(
        forIdentity identity: String?,
        traits: [Trait]?,
        transient: Bool,
        completion: @Sendable @escaping (Result<[Flag], any Error>) -> Void
    ) {
        let traitsByKey = traits.map { Dictionary(uniqueKeysWithValues: $0.map { ($0.key, $0.typedValue) }) }
        fetches.append(Fetch(identity: identity, traits: traitsByKey))
        guard holdCompletions else { return completion(result) }
        let outcome = result
        held.append { completion(outcome) }
    }

    /// Completes held fetches in the order they were requested, each with the result scripted at request time.
    func completeHeldFetches() {
        let pending = held
        held = []
        pending.forEach { $0() }
    }
}
