import FlagsmithClient
import Foundation
import Logging
import OpenFeature

extension FlagsmithProvider {
    public func getBooleanEvaluation(key: String, defaultValue: Bool, context: EvaluationContext?) throws
        -> ProviderEvaluation<Bool>
    {
        try getBooleanEvaluation(key: key, defaultValue: defaultValue, context: context, logger: nil)
    }

    public func getStringEvaluation(key: String, defaultValue: String, context: EvaluationContext?) throws
        -> ProviderEvaluation<String>
    {
        try getStringEvaluation(key: key, defaultValue: defaultValue, context: context, logger: nil)
    }

    public func getIntegerEvaluation(key: String, defaultValue: Int64, context: EvaluationContext?) throws
        -> ProviderEvaluation<Int64>
    {
        try getIntegerEvaluation(key: key, defaultValue: defaultValue, context: context, logger: nil)
    }

    public func getDoubleEvaluation(key: String, defaultValue: Double, context: EvaluationContext?) throws
        -> ProviderEvaluation<Double>
    {
        try getDoubleEvaluation(key: key, defaultValue: defaultValue, context: context, logger: nil)
    }

    public func getObjectEvaluation(key: String, defaultValue: Value, context: EvaluationContext?) throws
        -> ProviderEvaluation<Value>
    {
        try getObjectEvaluation(key: key, defaultValue: defaultValue, context: context, logger: nil)
    }
}

extension FlagsmithProvider {
    public func getBooleanEvaluation(key: String, defaultValue: Bool, context: EvaluationContext?, logger: Logger?)
        throws
        -> ProviderEvaluation<Bool>
    {
        try evaluate(key, logger: logger) { flag in
            guard useBooleanConfigValue else {
                return ProviderEvaluation(
                    value: flag.enabled, flagMetadata: metadata(for: flag), reason: reason(for: flag))
            }
            return try resolve(flag, key: key, as: "Boolean") { value in
                if case .bool(let boolean) = value { return boolean }
                return nil
            }
        }
    }

    public func getStringEvaluation(key: String, defaultValue: String, context: EvaluationContext?, logger: Logger?)
        throws
        -> ProviderEvaluation<String>
    {
        try evaluate(key, logger: logger) { flag in
            try resolve(flag, key: key, as: "String") { value in
                if case .string(let string) = value { return string }
                return nil
            }
        }
    }

    public func getIntegerEvaluation(key: String, defaultValue: Int64, context: EvaluationContext?, logger: Logger?)
        throws
        -> ProviderEvaluation<Int64>
    {
        try evaluate(key, logger: logger) { flag in
            try resolve(flag, key: key, as: "Integer") { value in
                switch value {
                case .int(let integer): return Int64(integer)
                case .float(let float): return Int64(exactly: float)
                default: return nil
                }
            }
        }
    }

    // Flagsmith has no float type; decimal values are stored and returned as strings.
    public func getDoubleEvaluation(key: String, defaultValue: Double, context: EvaluationContext?, logger: Logger?)
        throws
        -> ProviderEvaluation<Double>
    {
        try evaluate(key, logger: logger) { flag in
            try resolve(flag, key: key, as: "Double") { value in
                switch value {
                case .float(let float): return Double(float)
                case .int(let integer): return Double(integer)
                case .string(let string): return Double(string)
                default: return nil
                }
            }
        }
    }

    public func getObjectEvaluation(key: String, defaultValue: Value, context: EvaluationContext?, logger: Logger?)
        throws
        -> ProviderEvaluation<Value>
    {
        try evaluate(key, logger: logger) { flag in
            try resolve(flag, key: key, as: "Object") { value in
                guard case .string(let json) = value else { return nil }
                guard let parsed = try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)) else {
                    throw OpenFeatureError.parseError(message: "Unable to parse object from value for flag '\(key)'")
                }
                return parsed.value
            }
        }
    }
}
