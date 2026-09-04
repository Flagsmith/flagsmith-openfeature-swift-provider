import Combine
import FlagsmithClient
import Foundation
import Logging
import OpenFeature

/// OpenFeature provider backed by the Flagsmith iOS client.
///
/// Flags are fetched into memory on `initialize` and `onContextSet`; evaluations resolve
/// synchronously from that snapshot. See the project README for how the evaluation context
/// maps to Flagsmith identities and traits.
public final class FlagsmithProvider: FeatureProvider {
    public let hooks: [any Hook] = []
    public let metadata: ProviderMetadata = FlagsmithProviderMetadata()

    let flagSource: any FlagsmithFlagSource
    let useBooleanConfigValue: Bool
    let returnValueForDisabledFlags: Bool
    let logger: Logger
    let statusTracker = ProviderStatusTracker()
    let state = SnapshotState()
    var flagUpdates: Task<Void, Never>?

    /// - Parameters:
    ///   - flagsmith: the Flagsmith client used to fetch flags
    ///   - useBooleanConfigValue: evaluate booleans from the flag's remote config value instead of its enabled state
    ///   - returnValueForDisabledFlags: return values for disabled flags instead of erroring
    ///   - logger: swift-log destination for provider diagnostics
    public convenience init(
        flagsmith: Flagsmith = .shared,
        useBooleanConfigValue: Bool = false,
        returnValueForDisabledFlags: Bool = false,
        logger: Logger = Logger(label: "com.flagsmith.openfeature")
    ) {
        self.init(
            flagSource: flagsmith,
            useBooleanConfigValue: useBooleanConfigValue,
            returnValueForDisabledFlags: returnValueForDisabledFlags,
            logger: logger
        )
    }

    init(
        flagSource: any FlagsmithFlagSource,
        useBooleanConfigValue: Bool,
        returnValueForDisabledFlags: Bool,
        logger: Logger
    ) {
        self.flagSource = flagSource
        self.useBooleanConfigValue = useBooleanConfigValue
        self.returnValueForDisabledFlags = returnValueForDisabledFlags
        self.logger = logger
    }

    deinit {
        flagUpdates?.cancel()
    }

    public var status: ProviderStatus {
        statusTracker.status
    }

    public func observe() -> AnyPublisher<ProviderEvent, Never> {
        statusTracker.observe()
    }

    public func initialize(initialContext: EvaluationContext?) -> Future<Void, Never> {
        Future { promise in
            self.observeFlagUpdates()
            self.refresh(context: initialContext) { outcome in
                switch outcome {
                case .success:
                    self.statusTracker.send(.ready(nil))
                case .failure(let details):
                    self.statusTracker.send(.error(details))
                case .superseded:
                    break
                }
                promise(.success(()))
            }
        }
    }

    public func onContextSet(oldContext: EvaluationContext?, newContext: EvaluationContext) -> Future<Void, Never> {
        Future { promise in
            self.statusTracker.send(.reconciling(nil))
            self.refresh(context: newContext) { outcome in
                switch outcome {
                case .success:
                    self.statusTracker.send(.contextChanged(nil))
                case .failure(let details):
                    self.statusTracker.send(.error(details))
                case .superseded:
                    break
                }
                promise(.success(()))
            }
        }
    }

    private func refresh(context: EvaluationContext?, completion: @escaping (RefreshOutcome) -> Void) {
        let targetingKey = context?.getTargetingKey() ?? ""
        let identity: String? = targetingKey.isEmpty ? nil : targetingKey
        let traits: [Trait]?
        switch (identity, context) {
        case (.some, .some(let context)):
            switch self.traits(from: context) {
            case .success(let mapped):
                traits = mapped
            case .failure(let error):
                logger.error("Invalid evaluation context", metadata: ["reason": "\(error)"])
                completion(.failure(ProviderEventDetails(message: error.description, errorCode: .invalidContext)))
                return
            }
        default:
            traits = nil
        }
        fetch(identity: identity, traits: traits, completion: completion)
    }

    private func fetch(identity: String?, traits: [Trait]?, completion: @escaping (RefreshOutcome) -> Void) {
        let generation = state.beginRefresh()
        let traitCount: Logger.MetadataValue = "\(traits?.count ?? 0)"
        let metadata: Logger.Metadata =
            identity.map { ["identity": "\($0)", "traits": traitCount] } ?? ["traits": traitCount]
        logger.info("Fetching flags from Flagsmith", metadata: metadata)
        flagSource.getFeatureFlags(forIdentity: identity, traits: traits, transient: false) { result in
            switch result {
            case .success(let flags):
                let byName = flags.byName
                guard self.state.commit(byName, fetchedForIdentity: identity != nil, generation: generation) else {
                    self.logger.debug("Ignored superseded flags fetch from Flagsmith", metadata: metadata)
                    completion(.superseded)
                    return
                }
                self.logger.info("Flags fetched from Flagsmith", metadata: ["count": "\(flags.count)"])
                completion(.success)
            case .failure(let error):
                self.logger.error(
                    "Failed to fetch flags from Flagsmith", metadata: ["error": "\(error.localizedDescription)"])
                completion(
                    .failure(
                        ProviderEventDetails(
                            message: "An error occurred retrieving flags from Flagsmith: \(error.localizedDescription)",
                            errorCode: .general
                        )))
            }
        }
    }
}

struct FlagsmithProviderMetadata: ProviderMetadata {
    let name: String? = "FlagsmithProvider"
}

/// Result of one flags refresh; a refresh is superseded when a newer one began before it completed.
enum RefreshOutcome {
    case success
    case failure(ProviderEventDetails)
    case superseded
}
