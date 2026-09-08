import FlagsmithClient
import OpenFeature

extension FlagsmithProvider {
    /// Every context attribute becomes a trait.
    func traits(from context: EvaluationContext) -> Result<[Trait]?, ContextError> {
        var traits: [Trait] = []
        for (key, value) in context.asMap() {
            switch value {
            case .string(let string): traits.append(Trait(key: key, value: string))
            case .boolean(let boolean): traits.append(Trait(key: key, value: boolean))
            case .integer(let integer): traits.append(Trait(key: key, value: Int(integer)))
            case .double(let double): traits.append(Trait(key: key, value: Float(double)))
            default: return .failure(.unsupportedTraitValue(key: key))
            }
        }
        return .success(traits.isEmpty ? nil : traits)
    }
}

enum ContextError: Error, CustomStringConvertible {
    case unsupportedTraitValue(key: String)

    var description: String {
        switch self {
        case .unsupportedTraitValue(let key): return "Unsupported value for trait '\(key)'"
        }
    }
}
