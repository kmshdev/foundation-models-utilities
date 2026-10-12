import MCP

/// A developer-reviewed remote operation, including its exact schema and argument boundary.
/// The validator must enforce the configured repository/project scope and accepted keys/values.
/// A remote server's `readOnlyHint` is deliberately not used as authorization.
public struct MCPReviewedOperation: Sendable {
    public let toolName: String
    public let access: MCPToolAccess
    public let inputSchema: Value
    private let validateArguments: @Sendable ([String: Value]) throws -> Void

    public init(toolName: String, access: MCPToolAccess, inputSchema: Value,
                validateArguments: @escaping @Sendable ([String: Value]) throws -> Void) throws {
        guard !toolName.isEmpty, toolName.utf8.count <= 128,
              toolName.utf8.allSatisfy({ byte in
                  (65...90).contains(byte) || (97...122).contains(byte) ||
                  (48...57).contains(byte) || [45, 46, 95].contains(byte)
              }) else {
            throw MCPClientError.invalidOperationName
        }
        self.toolName = toolName
        self.access = access
        self.inputSchema = inputSchema
        self.validateArguments = validateArguments
    }

    func validate(_ arguments: [String: Value]) throws {
        try validateArguments(arguments)
    }
}
