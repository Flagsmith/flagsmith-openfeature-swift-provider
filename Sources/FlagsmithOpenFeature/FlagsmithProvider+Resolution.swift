import FlagsmithClient
import Logging
import OpenFeature

extension FlagsmithProvider {
    func evaluate<T>(_ key: String, logger: Logger?, _ body: (Flag) throws -> ProviderEvaluation<T>) throws
        -> ProviderEvaluation<T>
    {
        do {
            let snapshot = state.read()
            guard let flags = snapshot.flags else { throw OpenFeatureError.providerNotReadyError }
            guard let flag = flags[key] else { throw OpenFeatureError.flagNotFoundError(key: key) }
            return try body(flag)
        } catch {
            (logger ?? self.logger).warning(
                "Flag evaluation failed", metadata: ["flag": "\(key)", "error": "\(error)"])
            throw error
        }
    }

    func resolve<T>(_ flag: Flag, key: String, as typeName: String, _ convert: (TypedValue) throws -> T?) throws
        -> ProviderEvaluation<T>
    {
        if !flag.enabled && !returnValueForDisabledFlags {
            throw OpenFeatureError.generalError(message: "Flag '\(key)' is not enabled.")
        }
        guard let value = try convert(flag.value) else {
            logger.debug(
                "Flag value is not of the requested type", metadata: ["flag": "\(key)", "type": "\(typeName)"])
            throw OpenFeatureError.typeMismatchError
        }
        return ProviderEvaluation(value: value, flagMetadata: metadata(for: flag), reason: reason(for: flag))
    }

    func reason(for flag: Flag) -> String {
        if !flag.enabled && returnValueForDisabledFlags { return Reason.disabled.rawValue }
        return state.read().fetchedForIdentity ? Reason.targetingMatch.rawValue : Reason.staticReason.rawValue
    }

    // The Flagsmith iOS client exposes no feature id, only the name.
    func metadata(for flag: Flag) -> [String: FlagMetadataValue] {
        ["feature_name": .string(flag.feature.name)]
    }
}
