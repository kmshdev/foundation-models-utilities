import MCP
import Testing
@testable import EngineeringMCP

@Suite("MCP deadline winner arbitration", .timeLimit(.minutes(1)))
struct MCPRequestDeadlineTests {
    @Test("A timer queued after sleep cannot disconnect a response-first successful connection")
    func responseWinsAgainstQueuedTimer() async throws {
        let fixture = MCPServerFixture(pages: [:])
        let client = Client(name: "Deadline fixture", version: "1.0", configuration: .strict)
        try await client.connect(transport: fixture.start())
        let cancellation = MCPRequestCancellation(client: client)
        let timerReached = MCPTestGate()
        let releaseTimer = MCPTestGate()
        let releaseResponse = MCPTestGate()
        let request = Task {
            try await MCPRequestDeadline.run(duration: .seconds(1), cancellation: cancellation, sleep: { _ in
                await timerReached.open()
                await releaseTimer.wait()
            }) {
                await releaseResponse.wait()
                return "Accepted response"
            }
        }
        await timerReached.wait()
        await releaseResponse.open()
        while await cancellation.resolution != .completed { await Task.yield() }
        await releaseTimer.open()
        #expect(try await request.value == "Accepted response")
        #expect(await cancellation.resolution == .completed)
        // This second real SDK RPC fails on the old implementation because the
        // losing timer closed the same transport despite returning success.
        let read = try await client.callTool(name: "read_issue", arguments: [:])
        #expect(read.isError != true)
        #expect(await fixture.callCount == 1)
        await client.disconnect()
        await fixture.stop()
    }

    @Test("A completed protocol error also prevents later timer cleanup")
    func protocolErrorWinsAgainstQueuedTimer() async throws {
        let fixture = MCPServerFixture(pages: [:])
        let client = Client(name: "Deadline fixture", version: "1.0", configuration: .strict)
        try await client.connect(transport: fixture.start())
        let cancellation = MCPRequestCancellation(client: client)
        let timerReached = MCPTestGate()
        let releaseTimer = MCPTestGate()
        let releaseResponse = MCPTestGate()
        let request = Task {
            try await MCPRequestDeadline.run(duration: .seconds(1), cancellation: cancellation, sleep: { _ in
                await timerReached.open()
                await releaseTimer.wait()
            }) {
                await releaseResponse.wait()
                throw MCPFixtureError.invalidArguments
            } as String
        }
        await timerReached.wait()
        await releaseResponse.open()
        while await cancellation.resolution != .completed { await Task.yield() }
        await releaseTimer.open()
        await #expect(throws: MCPFixtureError.invalidArguments) { try await request.value }
        #expect(await cancellation.resolution == .completed)
        _ = try await client.callTool(name: "read_issue", arguments: [:])
        #expect(await fixture.callCount == 1)
        await client.disconnect()
        await fixture.stop()
    }
}
