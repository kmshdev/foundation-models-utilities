import Foundation
import MCP

actor MCPServerFixture {
    static let schema: Value = ["type": "object", "properties": ["repository": ["type": "string"]],
                                "required": ["repository"], "additionalProperties": false]
    let server: Server
    private var pages: [String?: ListTools.Result]
    private let toolResult: CallTool.Result
    private let delayCalls: Bool
    private let callError: MCPError?
    private var notifyDuringNextList: Bool
    private(set) var listCount = 0
    private(set) var callCount = 0
    private var callWaiters: [CheckedContinuation<Void, Never>] = []
    private var delayedCalls: [CheckedContinuation<Void, any Error>] = []
    private var initializationStarted = false
    private var initializationWaiters: [CheckedContinuation<Void, Never>] = []

    init(pages: [String?: ListTools.Result], result: CallTool.Result = .init(content: [.text(text: "Found", annotations: nil, _meta: nil)]),
         supportsTools: Bool = true, delayCalls: Bool = false, callError: MCPError? = nil,
         notifyDuringNextList: Bool = false) {
        server = Server(name: "Fixture", version: "1.0",
                        capabilities: .init(tools: supportsTools ? .init(listChanged: true) : nil))
        self.pages = pages
        self.toolResult = result
        self.delayCalls = delayCalls
        self.callError = callError
        self.notifyDuringNextList = notifyDuringNextList
    }

    static func tool(_ name: String, schema: Value = schema) -> MCP.Tool {
        MCP.Tool(name: name, description: "Fixture tool", inputSchema: schema,
                 annotations: .init(readOnlyHint: true))
    }

    func start() async throws -> InMemoryTransport {
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
        await server.withMethodHandler(ListTools.self) { [weak self] parameters in
            guard let self else { throw MCPError.connectionClosed }
            return try await self.list(parameters.cursor)
        }
        await server.withMethodHandler(CallTool.self) { [weak self] _ in
            guard let self else { throw MCPError.connectionClosed }
            return try await self.call()
        }
        try await server.start(transport: serverTransport)
        return clientTransport
    }

    func stop() async {
        let pending = delayedCalls
        delayedCalls.removeAll()
        pending.forEach { $0.resume(throwing: CancellationError()) }
        await server.stop()
    }

    func overrideInitialization(protocolVersion: String? = nil, neverRespond: Bool = false) async {
        await server.withMethodHandler(Initialize.self) { [weak self] _ in
            guard let self else { throw MCPError.connectionClosed }
            await self.markInitializationStarted()
            if neverRespond {
                try await self.delayResponse()
            }
            return .init(protocolVersion: protocolVersion ?? Version.latest,
                         capabilities: .init(tools: .init()),
                         serverInfo: .init(name: "Fixture", version: "1.0"))
        }
    }

    func waitForInitialization() async {
        guard !initializationStarted else { return }
        await withCheckedContinuation { initializationWaiters.append($0) }
    }

    private func markInitializationStarted() {
        initializationStarted = true
        let pending = initializationWaiters
        initializationWaiters.removeAll()
        pending.forEach { $0.resume() }
    }

    func changeCatalog(to pages: [String?: ListTools.Result]) async throws {
        self.pages = pages
        try await server.notify(ToolListChangedNotification.message())
    }

    func setCatalogWithoutNotification(to pages: [String?: ListTools.Result]) {
        self.pages = pages
    }

    func waitForCall() async {
        if callCount > 0 { return }
        await withCheckedContinuation { callWaiters.append($0) }
    }

    private func list(_ cursor: String?) async throws -> ListTools.Result {
        listCount += 1
        if notifyDuringNextList {
            notifyDuringNextList = false
            try await server.notify(ToolListChangedNotification.message())
        }
        return pages[cursor] ?? .init(tools: [])
    }

    private func call() async throws -> CallTool.Result {
        callCount += 1
        let waiters = callWaiters
        callWaiters.removeAll()
        waiters.forEach { $0.resume() }
        if let callError { throw callError }
        if delayCalls { try await delayResponse() }
        return toolResult
    }

    private func delayResponse() async throws {
        try await withCheckedThrowingContinuation { delayedCalls.append($0) }
    }
}
