import EngineeringCore
import Foundation
import FoundationModels

/// Executes the real SDK27 adapter/session path with deterministic streams and no account or network.
@MainActor
func checkSubscriptionModel() async throws {
    let transport = SubscriptionModelCheckTransport(outputs: [
        .text("Hello, Swift."), .text("Still Swift."), .text(#"{"summary":"Native plan","tasks":["Navigation","Tests"]}"#), .failed,
        .text(#"{"summary":"Build native navigation","tasks":[{"id":"navigation","title":"Native navigation","owner":"interface","paths":["Apps/EngineeringStudio/Features/Navigation.swift"],"acceptance":["Keyboard navigation reaches every pane"],"dependencies":[],"handoff":"Share changed files, commit and keyboard test evidence with quality."}],"questions":[]}"#)
    ])
    let client = ChatGPTResponsesClient(tokenProvider: SubscriptionModelCheckToken(), streamingTransport: transport)
    let model = ChatGPTLanguageModel(name: "fixture-model", client: client)
    let session = LanguageModelSession(model: model, instructions: Instructions { "Use Swift." })
    let first = try await session.respond(to: "First outcome")
    try subscriptionRequire(first.content == "Hello, Swift.", "SSE text assembles through LanguageModelSession")
    let second = try await session.respond(to: "Continue the outcome")
    try subscriptionRequire(second.content == "Still Swift.", "A second generation preserves local session history")
    let bodies = await transport.requestBodies
    let replay = try JSONSerialization.jsonObject(with: bodies[1]) as? [String: Any]
    let messages = replay?["input"] as? [[String: String]] ?? []
    try subscriptionRequire(messages.first?["role"] == "developer", "Framework instructions use an accepted developer message")
    try subscriptionRequire(messages.contains { $0["role"] == "assistant" && $0["content"] == "Hello, Swift." },
                            "Previous completed assistant output is replayed without previous_response_id")
    try subscriptionRequire(replay?["previous_response_id"] == nil && replay?["store"] as? Bool == false,
                            "History remains local and remote storage stays disabled")

    let guided = LanguageModelSession(model: model)
    let plan = try await guided.respond(to: "Plan native navigation", generating: SubscriptionModelCheckPlan.self)
    try subscriptionRequire(plan.content.summary == "Native plan" && plan.content.tasks == ["Navigation", "Tests"],
                            "Responses JSON schema parses through the native @Generable path")
    let guidedBody = try JSONSerialization.jsonObject(with: await transport.requestBodies[2]) as? [String: Any]
    let format = (guidedBody?["text"] as? [String: Any])?["format"] as? [String: Any]
    try subscriptionRequire(format?["type"] as? String == "json_schema" && format?["strict"] as? Bool == true,
                            "Guided generation actually requests server-enforced JSON schema")
    var failed = false
    do {
        _ = try await LanguageModelSession(model: model).respond(to: "Hit the fixture plan limit")
    } catch {
        failed = true
    }
    try subscriptionRequire(failed, "A usage failure after a text delta never returns a successful native response")
    let planning = try await FoundationPlanner.subscription(outcome: "Build native navigation", answers: "",
                                                            client: client, modelName: "fixture-model")
    try subscriptionRequire(planning.plan?.tasks.first?.owner == .interface && planning.questions.isEmpty,
                            "Actual FoundationPlanner DynamicProfile and @Guide-rich plan schema generate a validated assignment")
    let planningBody = String(decoding: await transport.requestBodies[4], as: UTF8.self)
    try subscriptionRequire(planningBody.contains("Exact relative file") && planningBody.contains("genuinely blocking questions"),
                            "The actual planner's property guides are preserved in its server schema")
    print("Subscription model checks passed: native text, local history, strict guided generation, actual guided planner, and partial-output failure.")
}

@Generable
private struct SubscriptionModelCheckPlan {
    var summary: String
    var tasks: [String]
}

private struct SubscriptionModelCheckToken: ChatGPTTokenProviding {
    func accessToken() async throws -> String { "fixture-oauth-only" }
}

private actor SubscriptionModelCheckTransport: ChatGPTResponsesStreamingTransport {
    enum Output: Sendable { case text(String), failed }
    private var outputs: [Output]
    private(set) var requestBodies: [Data] = []
    init(outputs: [Output]) { self.outputs = outputs }

    func open(_ request: URLRequest) async throws -> ChatGPTResponsesHTTPStream {
        guard let body = request.httpBody, !outputs.isEmpty else { throw SubscriptionModelCheckFailure(message: "Missing fixture request") }
        requestBodies.append(body)
        let output = outputs.removeFirst()
        let delta: String
        let ending: String
        switch output {
        case .text(let text):
            delta = String(decoding: try JSONEncoder().encode(["type": "response.output_text.delta", "delta": text]), as: UTF8.self)
            ending = #"{"type":"response.completed","response":{"status":"completed"}}"#
        case .failed:
            delta = #"{"type":"response.output_text.delta","delta":"partial"}"#
            ending = #"{"type":"response.failed","response":{"status":"failed","error":{"code":"subscription_sharing_usage_limit_exceeded"}}}"#
        }
        let stream = AsyncThrowingStream<Data, any Error> { continuation in
            continuation.yield(Data("data: \(delta)\n\n".utf8))
            continuation.yield(Data("data: \(ending)\n\n".utf8))
            continuation.finish()
        }
        return .init(statusCode: 200, headers: ["Content-Type": "text/event-stream"], body: stream)
    }
}

private struct SubscriptionModelCheckFailure: Error {
    let message: String
}

private func subscriptionRequire(_ condition: Bool, _ message: String) throws {
    if !condition { throw SubscriptionModelCheckFailure(message: message) }
}
