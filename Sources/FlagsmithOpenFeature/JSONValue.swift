import Foundation
import OpenFeature

/// Strict JSON tree decoded from a Flagsmith string value, convertible to an OpenFeature `Value`.
indirect enum JSONValue: Decodable {
    case boolean(Bool)
    case integer(Int64)
    case double(Double)
    case string(String)
    case list([JSONValue])
    case object([String: JSONValue])
    case null

    // JSONDecoder rejects `1` as Bool and `1.5` as Int64, so the probe order is lossless.
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let boolean = try? container.decode(Bool.self) {
            self = .boolean(boolean)
        } else if let integer = try? container.decode(Int64.self) {
            self = .integer(integer)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let list = try? container.decode([JSONValue].self) {
            self = .list(list)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    var value: Value {
        switch self {
        case .boolean(let boolean): return .boolean(boolean)
        case .integer(let integer): return .integer(integer)
        case .double(let double): return .double(double)
        case .string(let string): return .string(string)
        case .list(let list): return .list(list.map(\.value))
        case .object(let object): return .structure(object.mapValues(\.value))
        case .null: return .null
        }
    }
}
