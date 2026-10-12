import Foundation
import MCP
import Testing
@testable import EngineeringMCP

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite("Reviewed native MCP adapter", .timeLimit(.minutes(1)))
struct EngineeringMCPClientTests {
    private func identity() throws -> MCPConnectionIdentity {
        try .init(provider: .github, accountID: "fixture-account")
    }

    private func reviewed(_ name: String = "read_issue", access: MCPToolAccess = .read,
                          schema: Value = MCPServerFixture.schema) throws -> MCPReviewedOperation {
        try MCPReviewedOperation(toolName: name, access: access, inputSchema: schema) { arguments in
            guard arguments == ["repository": "kmshdev/foundation-models-utilities"] else {
                throw MCPFixtureError.invalidArguments
            }
        }
    }

    private func adapter(_ fixture: MCPServerFixture, operations: [MCPReviewedOperation]? = nil,
                         limits: MCPClientLimits = .init()) async throws -> EngineeringMCPClient {
        let policy = try MCPToolPolicy(identity: identity(), operations: operations ?? [reviewed()])
        return try EngineeringMCPClient(policy: policy, transport: await fixture.start(),
                                        appVersion: "fixture", limits: limits)
    }

    @Test("Provider endpoint is fixed and blank account identities fail")
    func identityBoundaries() throws {
        #expect(MCPProvider.github.endpoint.absoluteString == "https://api.githubcopilot.com/mcp/")
        #expect(MCPProvider.linear.endpoint.absoluteString == "https://mcp.linear.app/mcp/readonly")
        #expect(throws: MCPClientError.invalidAccount) {
            try MCPConnectionIdentity(provider: .linear, accountID: " \n")
        }
        #expect(throws: MCPClientError.invalidOperationName) {
            try reviewed("read issue")
        }
        #expect(throws: MCPClientError.duplicateReviewedOperation("read_issue")) {
            try MCPToolPolicy(identity: identity(), operations: [reviewed(), reviewed()])
        }
    }

    @Test("Initialize observes real capabilities and traverses every catalog page")
    func paginatedCatalog() async throws {
        let fixture = MCPServerFixture(pages: [nil: .init(tools: [MCPServerFixture.tool("read_issue")], nextCursor: "second"),
                                              "second": .init(tools: [MCPServerFixture.tool("get_checks")])])
        let adapter = try await adapter(fixture)
        let receipt = try await adapter.initialize()
        #expect(receipt.protocolVersion == "2025-11-25")
        #expect(receipt.serverName == "Fixture")
        #expect(receipt.supportsToolListChanges)
        let expectedIdentity = try identity()
        #expect(receipt.identity == expectedIdentity)
        let catalog = try await adapter.catalog()
        #expect(catalog.tools.map(\.name) == ["read_issue", "get_checks"])
        #expect(await fixture.listCount == 2)
        _ = try await adapter.catalog()
        #expect(await fixture.listCount == 2)
        await adapter.disconnect()
        await fixture.stop()
    }

    @Test("Missing tools capability closes the unusable connection")
    func missingCapability() async throws {
        let fixture = MCPServerFixture(pages: [:], supportsTools: false)
        let adapter = try await adapter(fixture)
        await #expect(throws: MCPClientError.toolsUnavailable) { try await adapter.initialize() }
        #expect(await adapter.isClosed)
        await #expect(throws: MCPClientError.connectionClosed) { try await adapter.catalog() }
        await fixture.stop()
    }

    @Test("Catalog rejects repeated cursors, duplicate names and bounded page counts")
    func hostileCatalog() async throws {
        let repeated = MCPServerFixture(pages: [nil: .init(tools: [], nextCursor: "again"),
                                               "again": .init(tools: [], nextCursor: "again")])
        let repeatedAdapter = try await adapter(repeated)
        try await repeatedAdapter.initialize()
        await #expect(throws: MCPClientError.repeatedCursor) { try await repeatedAdapter.catalog() }
        #expect(await repeated.listCount == 2)
        await repeatedAdapter.disconnect()
        await repeated.stop()

        let duplicated = MCPServerFixture(pages: [nil: .init(tools: [MCPServerFixture.tool("read_issue"), MCPServerFixture.tool("read_issue")])])
        let duplicateAdapter = try await adapter(duplicated)
        try await duplicateAdapter.initialize()
        await #expect(throws: MCPClientError.duplicateTool("read_issue")) { try await duplicateAdapter.catalog() }
        await duplicateAdapter.disconnect()
        await duplicated.stop()

        let bounded = MCPServerFixture(pages: [nil: .init(tools: [], nextCursor: "second")])
        let boundedAdapter = try await adapter(bounded, limits: .init(maximumCatalogPages: 1))
        try await boundedAdapter.initialize()
        await #expect(throws: MCPClientError.catalogPageLimit) { try await boundedAdapter.catalog() }
        #expect(await bounded.listCount == 1)
        await boundedAdapter.disconnect()
        await bounded.stop()
    }

    @Test("Reads preserve structured content, text, provider error and metadata")
    func fullResultReceipt() async throws {
        let result = try CallTool.Result(content: [.text(text: "Provider rejected request", annotations: nil, _meta: nil)],
                                     structuredContent: Value.object(["issue": .string("ENG-46")]),
                                     isError: true, _meta: .init(additionalFields: ["receipt": "fixture"]))
        let fixture = MCPServerFixture(pages: [nil: .init(tools: [MCPServerFixture.tool("read_issue")])], result: result)
        let adapter = try await adapter(fixture)
        try await adapter.initialize()
        let receipt = try await adapter.callRead(named: "read_issue", arguments: ["repository": "kmshdev/foundation-models-utilities"])
        let expectedIdentity = try identity()
        #expect(receipt.identity == expectedIdentity)
        #expect(receipt.toolName == "read_issue")
        #expect(receipt.result == result)
        #expect(receipt.result.isError == true)
        #expect(await fixture.callCount == 1)
        await adapter.disconnect()
        await fixture.stop()
    }

    @Test("Allowlist and argument scope reject calls before transmission; writes stay disabled")
    func operationPolicy() async throws {
        let fixture = MCPServerFixture(pages: [nil: .init(tools: [MCPServerFixture.tool("read_issue"), MCPServerFixture.tool("merge_pull_request")])])
        let adapter = try await adapter(fixture, operations: [reviewed(), reviewed("merge_pull_request", access: .mutation)])
        try await adapter.initialize()
        await #expect(throws: MCPClientError.operationNotReviewed("get_checks")) {
            try await adapter.callRead(named: "get_checks", arguments: [:])
        }
        await #expect(throws: MCPClientError.mutationsDisabled("merge_pull_request")) {
            try await adapter.callRead(named: "merge_pull_request", arguments: [:])
        }
        await #expect(throws: MCPFixtureError.invalidArguments) {
            try await adapter.callRead(named: "read_issue", arguments: ["repository": "other/repo"])
        }
        #expect(await fixture.callCount == 0)
        #expect(await fixture.listCount == 0)
        await adapter.disconnect()
        await fixture.stop()
    }

    @Test("Catalog changes invalidate cache without expanding policy or accepting a changed schema")
    func catalogInvalidation() async throws {
        let fixture = MCPServerFixture(pages: [nil: .init(tools: [MCPServerFixture.tool("read_issue")])])
        let adapter = try await adapter(fixture)
        try await adapter.initialize()
        let first = try await adapter.catalog()
        let changed: Value = ["type": "object", "properties": ["anything": ["type": "string"]]]
        try await fixture.changeCatalog(to: [nil: .init(tools: [MCPServerFixture.tool("read_issue", schema: changed),
                                                               MCPServerFixture.tool("write_new_issue")])])
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while await adapter.catalogRevision == first.revision, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(await adapter.catalogRevision > first.revision)
        let updated = try await adapter.catalog()
        #expect(updated.tools.count == 2)
        #expect(await fixture.listCount == 2)
        await #expect(throws: MCPClientError.operationNotReviewed("write_new_issue")) {
            try await adapter.callRead(named: "write_new_issue", arguments: [:])
        }
        await #expect(throws: MCPClientError.schemaChanged("read_issue")) {
            try await adapter.callRead(named: "read_issue", arguments: ["repository": "kmshdev/foundation-models-utilities"])
        }
        #expect(await fixture.callCount == 0)
        await adapter.disconnect()
        await fixture.stop()
    }

    @Test("RPC deadline releases an indefinitely delayed response and closes its dedicated connection")
    func requestTimeout() async throws {
        let fixture = MCPServerFixture(pages: [nil: .init(tools: [MCPServerFixture.tool("read_issue")])], delayCalls: true)
        let adapter = try await adapter(fixture, limits: .init(requestDeadline: .milliseconds(100)))
        try await adapter.initialize()
        _ = try await adapter.catalog()
        let started = ContinuousClock.now
        await #expect(throws: MCPClientError.deadlineExceeded) {
            try await adapter.callRead(named: "read_issue", arguments: ["repository": "kmshdev/foundation-models-utilities"])
        }
        #expect(started.duration(to: .now) < .seconds(2))
        #expect(await adapter.isClosed)
        #expect(await fixture.callCount == 1)
        await fixture.stop()
    }

    @Test("Caller cancellation unblocks the SDK request and rejects late or further work")
    func callerCancellation() async throws {
        let fixture = MCPServerFixture(pages: [nil: .init(tools: [MCPServerFixture.tool("read_issue")])], delayCalls: true)
        let adapter = try await adapter(fixture)
        try await adapter.initialize()
        _ = try await adapter.catalog()
        let read = Task {
            try await adapter.callRead(named: "read_issue", arguments: ["repository": "kmshdev/foundation-models-utilities"])
        }
        await fixture.waitForCall()
        read.cancel()
        await #expect(throws: CancellationError.self) { try await read.value }
        #expect(await adapter.isClosed)
        await #expect(throws: MCPClientError.connectionClosed) {
            try await adapter.callRead(named: "read_issue", arguments: ["repository": "kmshdev/foundation-models-utilities"])
        }
        await fixture.stop()
    }

    @Test("Unsupported negotiated protocol is rejected rather than advertised as compatible")
    func unsupportedProtocol() async throws {
        let fixture = MCPServerFixture(pages: [:])
        let adapter = try await adapter(fixture)
        await fixture.overrideInitialization(protocolVersion: "2026-07-28")
        await #expect(throws: MCPClientError.unsupportedProtocol("2026-07-28")) { try await adapter.initialize() }
        #expect(await adapter.isClosed)
        await fixture.stop()
    }

    @Test("A server that never completes initialization cannot hold the adapter indefinitely")
    func initializationTimeout() async throws {
        let fixture = MCPServerFixture(pages: [:])
        let adapter = try await adapter(fixture, limits: .init(initializationDeadline: .milliseconds(100)))
        await fixture.overrideInitialization(neverRespond: true)
        let started = ContinuousClock.now
        await #expect(throws: MCPClientError.deadlineExceeded) { try await adapter.initialize() }
        #expect(started.duration(to: .now) < .seconds(2))
        #expect(await adapter.isClosed)
        await fixture.stop()
    }

    @Test("An in-flight catalog invalidation cannot install stale tool schemas")
    func inFlightInvalidation() async throws {
        let fixture = MCPServerFixture(pages: [nil: .init(tools: [MCPServerFixture.tool("read_issue")])],
                                       notifyDuringNextList: true)
        let adapter = try await adapter(fixture)
        try await adapter.initialize()
        await #expect(throws: MCPClientError.catalogChanged) { try await adapter.catalog() }
        let retry = try await adapter.catalog()
        #expect(retry.tools.count == 1)
        #expect(await fixture.listCount == 2)
        await adapter.disconnect()
        await fixture.stop()
    }

    @Test("Protocol failures remain errors rather than successful execution receipts")
    func protocolFailure() async throws {
        let fixture = MCPServerFixture(pages: [nil: .init(tools: [MCPServerFixture.tool("read_issue")])],
                                       callError: .invalidParams("Fixture rejection"))
        let adapter = try await adapter(fixture)
        try await adapter.initialize()
        do {
            _ = try await adapter.callRead(named: "read_issue", arguments: ["repository": "kmshdev/foundation-models-utilities"])
            Issue.record("Protocol failure was incorrectly returned as a receipt")
        } catch let error as MCPError {
            #expect(error.code == -32602)
        }
        #expect(await fixture.callCount == 1)
        await adapter.disconnect()
        await fixture.stop()
    }

    @Test("Arguments, catalog cardinality and response payloads are bounded")
    func payloadBounds() async throws {
        let fixture = MCPServerFixture(pages: [nil: .init(tools: [MCPServerFixture.tool("read_issue")])])
        let adapter = try await adapter(fixture, limits: .init(maximumArgumentsBytes: 8))
        try await adapter.initialize()
        await #expect(throws: MCPClientError.argumentsTooLarge) {
            try await adapter.callRead(named: "read_issue", arguments: ["repository": "kmshdev/foundation-models-utilities"])
        }
        #expect(await fixture.callCount == 0)
        await adapter.disconnect()
        await fixture.stop()

        let largeResult = MCPServerFixture(pages: [nil: .init(tools: [MCPServerFixture.tool("read_issue")])])
        let resultAdapter = try await self.adapter(largeResult, limits: .init(maximumResponseBytes: 1))
        try await resultAdapter.initialize()
        await #expect(throws: MCPClientError.responseTooLarge) {
            try await resultAdapter.callRead(named: "read_issue", arguments: ["repository": "kmshdev/foundation-models-utilities"])
        }
        #expect(await largeResult.callCount == 1)
        await resultAdapter.disconnect()
        await largeResult.stop()

        let manyTools = MCPServerFixture(pages: [nil: .init(tools: [MCPServerFixture.tool("read_issue"), MCPServerFixture.tool("other")])])
        let countAdapter = try await self.adapter(manyTools, limits: .init(maximumCatalogTools: 1))
        try await countAdapter.initialize()
        await #expect(throws: MCPClientError.catalogToolLimit) { try await countAdapter.catalog() }
        await countAdapter.disconnect()
        await manyTools.stop()
    }

    @Test("Transmission stalls are bounded for both catalog and tool requests")
    func stalledSendDeadline() async throws {
        for method in [ListTools.name, CallTool.name] {
            let fixture = MCPServerFixture(pages: [nil: .init(tools: [MCPServerFixture.tool("read_issue")])])
            let transport = MCPStalledSendTransport(wrapping: try await fixture.start(), method: method)
            let policy = try MCPToolPolicy(identity: identity(), operations: [reviewed()])
            let adapter = try EngineeringMCPClient(policy: policy, transport: transport, appVersion: "fixture",
                                                    limits: .init(requestDeadline: .milliseconds(100)))
            try await adapter.initialize()
            let started = ContinuousClock.now
            await #expect(throws: MCPClientError.deadlineExceeded) {
                if method == ListTools.name {
                    _ = try await adapter.catalog()
                } else {
                    _ = try await adapter.callRead(named: "read_issue", arguments: ["repository": "kmshdev/foundation-models-utilities"])
                }
            }
            #expect(started.duration(to: .now) < .seconds(2))
            #expect(await transport.didStall)
            #expect(await adapter.isClosed)
            #expect(await fixture.callCount == 0)
            if method == ListTools.name { #expect(await fixture.listCount == 0) }
            await fixture.stop()
        }
    }

    @Test("Caller cancellation releases stalled transmission before any tool is delivered")
    func stalledSendCancellation() async throws {
        let fixture = MCPServerFixture(pages: [nil: .init(tools: [MCPServerFixture.tool("read_issue")])])
        let transport = MCPStalledSendTransport(wrapping: try await fixture.start(), method: CallTool.name)
        let policy = try MCPToolPolicy(identity: identity(), operations: [reviewed()])
        let adapter = try EngineeringMCPClient(policy: policy, transport: transport, appVersion: "fixture")
        try await adapter.initialize()
        let read = Task {
            try await adapter.callRead(named: "read_issue", arguments: ["repository": "kmshdev/foundation-models-utilities"])
        }
        await transport.waitForStall()
        read.cancel()
        await #expect(throws: CancellationError.self) { try await read.value }
        #expect(await adapter.isClosed)
        #expect(await fixture.callCount == 0)
        await fixture.stop()
    }

    @Test("Provider read-only modes keep authentication identity and metadata matching intact")
    func providerReadOnlyModes() throws {
        let github = try identity()
        let githubRequest = EngineeringMCPHTTPFactory.readOnlyRequest(URLRequest(url: github.endpoint), identity: github)
        #expect(githubRequest.url == github.endpoint)
        #expect(githubRequest.value(forHTTPHeaderField: "X-MCP-Readonly") == "true")
        #expect(githubRequest.value(forHTTPHeaderField: "Authorization") == nil)
        let unrelated = URL(string: "https://example.com/")!
        let unrelatedRequest = EngineeringMCPHTTPFactory.readOnlyRequest(URLRequest(url: unrelated), identity: github)
        #expect(unrelatedRequest.value(forHTTPHeaderField: "X-MCP-Readonly") == nil)

        let linear = try MCPConnectionIdentity(provider: .linear, accountID: "fixture-account")
        let linearRequest = EngineeringMCPHTTPFactory.readOnlyRequest(URLRequest(url: linear.endpoint), identity: linear)
        #expect(linearRequest.url?.path == "/mcp/readonly")
        #expect(linearRequest.value(forHTTPHeaderField: "X-MCP-Readonly") == nil)
        let metadata = DefaultOAuthMetadataDiscovery()
        let resource = try metadata.canonicalResourceURI(from: URL(string: "https://mcp.linear.app/mcp")!)
        let endpoint = try metadata.canonicalResourceURI(from: linear.endpoint)
        #expect(metadata.protectedResourceMatches(resource: resource, endpoint: endpoint))
    }
}
