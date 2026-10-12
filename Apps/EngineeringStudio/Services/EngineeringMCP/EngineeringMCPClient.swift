import Foundation
import MCP

/// Read-only MCP adapter. A closed instance cannot reconnect: create a fresh one
/// for a new session/account and supply a separately owned transport/authorizer.
/// No Foundation Models tool or subscription executor is enabled by this service.
public actor EngineeringMCPClient {
    public nonisolated let identity: MCPConnectionIdentity
    public private(set) var initialization: MCPInitializationReceipt?
    public private(set) var isClosed = false
    public private(set) var catalogRevision: UInt64 = 0

    private let client: Client
    private let transport: any Transport
    private let policy: MCPToolPolicy
    private let limits: MCPClientLimits
    private var operationInProgress = false
    private var cachedCatalog: MCPToolCatalog?

    /// Injected transports are for tests or explicitly trusted composition code.
    /// Production HTTP construction uses the fixed-endpoint factory below.
    public init(policy: MCPToolPolicy, transport: any Transport,
                appVersion: String, limits: MCPClientLimits = .init()) throws {
        try limits.validate()
        self.identity = policy.identity
        self.policy = policy
        self.transport = transport
        self.limits = limits
        client = Client(name: "Engineering Studio", version: appVersion, configuration: .strict)
    }

    deinit {
        // The upstream client owns a receive-loop task. Explicit disconnect is preferred;
        // dropping this adapter must also release that loop and its URLSession resources.
        let client = client
        Task { @concurrent in await client.disconnect() }
    }

    @discardableResult
    public func initialize() async throws -> MCPInitializationReceipt {
        guard !isClosed else { throw MCPClientError.connectionClosed }
        if let initialization { return initialization }
        try beginOperation()
        defer { operationInProgress = false }

        await client.onNotification(ToolListChangedNotification.self) { [weak self] _ in
            await self?.invalidateCatalog()
        }
        let cancellation = MCPRequestCancellation(client: client)
        do {
            let observed = try await MCPRequestDeadline.run(
                duration: limits.initializationDeadline, cancellation: cancellation
            ) { [client, transport] in
                try await client.connect(transport: transport)
            }
            try Task.checkCancellation()
            guard !isClosed else { throw MCPClientError.connectionClosed }
            guard Version.supported.contains(observed.protocolVersion) else {
                throw MCPClientError.unsupportedProtocol(observed.protocolVersion)
            }
            guard let tools = observed.capabilities.tools else {
                throw MCPClientError.toolsUnavailable
            }
            let receipt = MCPInitializationReceipt(
                identity: identity, protocolVersion: observed.protocolVersion,
                serverName: observed.serverInfo.name, serverVersion: observed.serverInfo.version,
                supportsToolListChanges: tools.listChanged == true, initializedAt: Date()
            )
            initialization = receipt
            return receipt
        } catch {
            await disconnect()
            throw error
        }
    }

    public func catalog() async throws -> MCPToolCatalog {
        try requireInitialized()
        try beginOperation()
        defer { operationInProgress = false }
        return try await loadCatalog()
    }

    /// Only explicitly reviewed reads with a matching current schema can be sent.
    /// The supplied policy's validator enforces concrete repository/project arguments.
    public func callRead(named name: String, arguments: [String: Value]) async throws -> MCPToolReceipt {
        try requireInitialized()
        let reviewed = try policy.reviewedRead(named: name, arguments: arguments)
        guard try JSONEncoder().encode(Value.object(arguments)).count <= limits.maximumArgumentsBytes else {
            throw MCPClientError.argumentsTooLarge
        }
        try beginOperation()
        defer { operationInProgress = false }

        let catalog = try await loadCatalog()
        guard let tool = catalog.tools.first(where: { $0.name == name }) else {
            throw MCPClientError.toolUnavailable(name)
        }
        guard tool.inputSchema == reviewed.inputSchema else {
            throw MCPClientError.schemaChanged(name)
        }
        try requireInitialized()
        guard catalog.revision == catalogRevision else { throw MCPClientError.catalogChanged }
        let request = CallTool.request(.init(name: name, arguments: arguments))
        let result = try await performRequest(request)
        guard try JSONEncoder().encode(result).count <= limits.maximumResponseBytes else {
            throw MCPClientError.responseTooLarge
        }
        return MCPToolReceipt(identity: identity, requestID: request.id, toolName: name,
                              catalogRevision: catalog.revision, completedAt: Date(), result: result)
    }

    /// Invalidates all cached capabilities. Cancellation/deadline also closes this instance.
    public func disconnect() async {
        isClosed = true
        initialization = nil
        invalidateCatalog()
        await client.disconnect()
    }

    private func loadCatalog() async throws -> MCPToolCatalog {
        if let cachedCatalog { return cachedCatalog }
        let expectedRevision = catalogRevision
        var tools: [MCP.Tool] = []
        var names: Set<String> = []
        var cursors: Set<String> = []
        var cursor: String?
        var pageCount = 0
        repeat {
            guard pageCount < limits.maximumCatalogPages else { throw MCPClientError.catalogPageLimit }
            pageCount += 1
            let parameters = cursor.map(ListTools.Parameters.init(cursor:)) ?? .init()
            let page = try await performRequest(ListTools.request(parameters))
            guard expectedRevision == catalogRevision else { throw MCPClientError.catalogChanged }
            guard tools.count + page.tools.count <= limits.maximumCatalogTools else {
                throw MCPClientError.catalogToolLimit
            }
            for tool in page.tools {
                guard names.insert(tool.name).inserted else { throw MCPClientError.duplicateTool(tool.name) }
                tools.append(tool)
            }
            cursor = page.nextCursor
            if let cursor, !cursors.insert(cursor).inserted { throw MCPClientError.repeatedCursor }
        } while cursor != nil
        let catalog = MCPToolCatalog(identity: identity, revision: expectedRevision, tools: tools)
        cachedCatalog = catalog
        return catalog
    }

    private func performRequest<Operation: MCP.Method>(
        _ request: Request<Operation>
    ) async throws -> Operation.Result {
        // The ID exists before any SDK actor hop. One deadline covers request setup,
        // transport/auth I/O and response waiting; cancellation can target it throughout.
        let cancellation = MCPRequestCancellation(client: client, requestID: request.id)
        do {
            let result = try await MCPRequestDeadline.run(
                duration: limits.requestDeadline, cancellation: cancellation
            ) { [client] in
                try Task.checkCancellation()
                let context = try await client.send(request)
                return try await context.value
            }
            try requireInitialized()
            return result
        } catch {
            if error is CancellationError || (error as? MCPClientError) == .deadlineExceeded {
                await disconnect()
            }
            throw error
        }
    }

    private func requireInitialized() throws {
        guard !isClosed else { throw MCPClientError.connectionClosed }
        guard initialization != nil else { throw MCPClientError.notInitialized }
    }

    private func beginOperation() throws {
        try Task.checkCancellation()
        guard !operationInProgress else { throw MCPClientError.operationInProgress }
        operationInProgress = true
    }

    private func invalidateCatalog() {
        catalogRevision &+= 1
        cachedCatalog = nil
    }
}
