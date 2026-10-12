import Foundation

/// The bounded subset of JSON used by Codex's newline-delimited RPC transport.
public indirect enum ExecutionJSON: Codable, Sendable, Equatable {
    case object([String: ExecutionJSON]), array([ExecutionJSON]), string(String), number(Double), bool(Bool), null

    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let result = try? value.decode(Bool.self) { self = .bool(result) }
        else if let result = try? value.decode(String.self) { self = .string(result) }
        else if let result = try? value.decode(Double.self) { self = .number(result) }
        else if let result = try? value.decode([String: ExecutionJSON].self) { self = .object(result) }
        else { self = .array(try value.decode([ExecutionJSON].self)) }
    }
    public func encode(to encoder: any Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .object(let result): try value.encode(result)
        case .array(let result): try value.encode(result)
        case .string(let result): try value.encode(result)
        case .number(let result): try value.encode(result)
        case .bool(let result): try value.encode(result)
        case .null: try value.encodeNil()
        }
    }
    public subscript(_ key: String) -> ExecutionJSON { if case .object(let value) = self { value[key] ?? .null } else { .null } }
    public var string: String? { if case .string(let value) = self { value } else { nil } }
    public var array: [ExecutionJSON] { if case .array(let value) = self { value } else { [] } }
    public var integer: Int? { if case .number(let value) = self, value.isFinite, value.rounded() == value,
                               value >= Double(Int.min), value < Double(Int.max) { Int(value) } else { nil } }
}
