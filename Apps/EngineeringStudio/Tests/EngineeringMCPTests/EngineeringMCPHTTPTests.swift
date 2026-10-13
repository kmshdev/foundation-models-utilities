#if !os(Linux)
import Foundation
import MCP
import Testing
@testable import EngineeringMCP

@Suite("Native stateless MCP HTTP transport", .serialized, .timeLimit(.minutes(1)))
struct EngineeringMCPHTTPTests {
    @Test("Stateless initialize and reads preserve JSON and POST SSE without an idle GET", arguments: [MCPHTTPResponseMode.json, .sse])
    func statelessRead(mode: MCPHTTPResponseMode) async throws {
        let id = UUID().uuidString
        let fixture = MCPHTTPFixture(mode: mode)
        MCPHTTPFixtureURLProtocol.register(fixture, id: id)
        defer { MCPHTTPFixtureURLProtocol.unregister(id: id) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MCPHTTPFixtureURLProtocol.self]
        configuration.httpAdditionalHeaders = [MCPHTTPFixtureURLProtocol.marker: id]
        let identity = try MCPConnectionIdentity(provider: .github, accountID: "fixture-account")
        let operation = try MCPReviewedOperation(toolName: "read_issue", access: .read,
                                                inputSchema: MCPServerFixture.schema) { arguments in
            guard arguments == ["repository": "kmshdev/foundation-models-utilities"] else {
                throw MCPFixtureError.invalidArguments
            }
        }
        let policy = try MCPToolPolicy(identity: identity, operations: [operation])
        let transport = EngineeringMCPHTTPFactory.makeTransport(identity: identity, configuration: configuration,
                                                                accessToken: { "fixture-token" })
        let adapter = try EngineeringMCPClient(policy: policy, transport: transport, appVersion: "fixture",
                                                limits: .init(requestDeadline: .seconds(2), initializationDeadline: .seconds(2)))
        let initialized = try await adapter.initialize()
        #expect(!initialized.supportsToolListChanges)
        let result = try await adapter.callRead(named: "read_issue", arguments: ["repository": "kmshdev/foundation-models-utilities"])
        #expect(result.result.structuredContent == .object(["issue": .string("ENG-46")]))
        #expect(result.result.isError == false)
        #expect(result.result._meta?["receipt"] == .string("http-fixture"))
        let requests = await fixture.requests
        #expect(requests.count == 4)
        #expect(requests.allSatisfy { $0.httpMethod == "POST" })
        #expect(requests.allSatisfy { $0.url == identity.endpoint })
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token" })
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "X-MCP-Readonly") == "true" })
        await adapter.disconnect()
    }
}
#endif
