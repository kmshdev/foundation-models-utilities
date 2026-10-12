import MCP

/// Immutable, explicit operations reviewed for one provider/account. Discovery cannot expand it.
public struct MCPToolPolicy: Sendable {
    public let identity: MCPConnectionIdentity
    private let operations: [String: MCPReviewedOperation]

    public init(identity: MCPConnectionIdentity, operations: [MCPReviewedOperation]) throws {
        var indexed: [String: MCPReviewedOperation] = [:]
        for operation in operations {
            guard indexed.updateValue(operation, forKey: operation.toolName) == nil else {
                throw MCPClientError.duplicateReviewedOperation(operation.toolName)
            }
        }
        self.identity = identity
        self.operations = indexed
    }

    func reviewedRead(named name: String, arguments: [String: Value]) throws -> MCPReviewedOperation {
        guard let operation = operations[name] else {
            throw MCPClientError.operationNotReviewed(name)
        }
        guard case .read = operation.access else {
            throw MCPClientError.mutationsDisabled(name)
        }
        try operation.validate(arguments)
        return operation
    }
}
