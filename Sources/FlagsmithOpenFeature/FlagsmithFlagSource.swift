import FlagsmithClient
import Foundation

/// The subset of the Flagsmith client the provider depends on; `Flagsmith` has no public initializer.
protocol FlagsmithFlagSource: AnyObject {
    var flagStream: AsyncStream<[Flag]> { get }

    func getFeatureFlags(
        forIdentity identity: String?,
        traits: [Trait]?,
        transient: Bool,
        completion: @Sendable @escaping (Result<[Flag], any Error>) -> Void
    )
}

extension Flagsmith: FlagsmithFlagSource {}

extension [Flag] {
    /// Flags keyed by feature name. Flagsmith guarantees feature names are unique within an environment.
    var byName: [String: Flag] {
        Dictionary(uniqueKeysWithValues: map { ($0.feature.name, $0) })
    }
}
