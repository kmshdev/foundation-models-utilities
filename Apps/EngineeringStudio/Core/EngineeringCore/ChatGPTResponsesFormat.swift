import Foundation

/// Responses JSON-schema enforcement; this never falls back to prompt-only JSON.
public struct ChatGPTResponsesFormat: Encodable, Sendable {
    public let name: String
    private let schema: ChatGPTModelJSONValue

    public init(name: String, schemaJSON: Data) throws {
        guard !name.isEmpty, name.count <= 64,
              name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "_-".contains($0)) }),
              schemaJSON.count <= 1_000_000,
              let decoded = try? JSONDecoder().decode(ChatGPTModelJSONValue.self, from: schemaJSON),
              case .object(let root) = decoded, root["type"] == .string("object") else {
            throw ChatGPTResponsesError.unsupportedSchema
        }
        self.name = name
        schema = try Self.strictSchema(decoded)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("json_schema", forKey: .type)
        try container.encode(name, forKey: .name)
        try container.encode(true, forKey: .strict)
        try container.encode(schema, forKey: .schema)
    }

    private enum CodingKeys: String, CodingKey { case type, name, strict, schema }

    private static func strictSchema(_ value: ChatGPTModelJSONValue, depth: Int = 0) throws -> ChatGPTModelJSONValue {
        guard depth < 64 else { throw ChatGPTResponsesError.unsupportedSchema }
        switch value {
        case .object(var object):
            if object["type"] == .string("object") {
                guard case .object(let properties) = object["properties"],
                      case .array(let required) = object["required"],
                      required.allSatisfy({ if case .string = $0 { true } else { false } }),
                      Set(required.compactMap { if case .string(let value) = $0 { value } else { nil } }) == Set(properties.keys),
                      object["additionalProperties"] == nil || object["additionalProperties"] == .bool(false) else {
                    throw ChatGPTResponsesError.unsupportedSchema
                }
                object["additionalProperties"] = .bool(false)
            }
            for key in ["properties", "$defs", "definitions"] {
                if case .object(let children) = object[key] {
                    object[key] = .object(try children.mapValues { try strictSchema($0, depth: depth + 1) })
                }
            }
            for key in ["items", "anyOf"] {
                if let child = object[key] { object[key] = try strictSchema(child, depth: depth + 1) }
            }
            return .object(object)
        case .array(let children): return .array(try children.map { try strictSchema($0, depth: depth + 1) })
        default: return value
        }
    }
}
