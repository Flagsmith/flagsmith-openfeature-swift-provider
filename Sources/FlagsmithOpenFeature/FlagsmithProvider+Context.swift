import FlagsmithClient
import OpenFeature

extension FlagsmithProvider {
    /// Flat attributes become traits; a nested `traits` structure overrides them on conflict.
    func traits(from context: EvaluationContext) -> Result<[Trait]?, ContextError> {
        let attributes = context.asMap()
        var merged = attributes.filter { $0.key != "traits" }
        switch attributes["traits"] {
        case .none:
            break
        case .structure(let nested):
            merged.merge(nested) { _, nested in nested }
        case .some:
            return .failure(.traitsNotStructure)
        }
        var traits: [Trait] = []
        for (key, value) in merged {
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
    case traitsNotStructure
    case unsupportedTraitValue(key: String)

    var description: String {
        switch self {
        case .traitsNotStructure: return "Attribute 'traits' must be a structure"
        case .unsupportedTraitValue(let key): return "Unsupported value for trait '\(key)'"
        }
    }
}
