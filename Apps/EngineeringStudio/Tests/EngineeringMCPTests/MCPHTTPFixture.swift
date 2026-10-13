#if !os(Linux)
import Foundation
import MCP

actor MCPHTTPFixture {
    let mode: MCPHTTPResponseMode
    private(set) var requests: [URLRequest] = []

    init(mode: MCPHTTPResponseMode) { self.mode = mode }

    func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        requests.append(request)
        guard request.httpMethod == "POST" else {
            throw MCPFixtureError.invalidArguments
        }
        let body = try requestBody(request)
        let message = try JSONDecoder().decode([String: Value].self, from: body)
        let method = message["method"]?.stringValue
        let encoder = JSONEncoder()
        var isToolResponse = false
        let responseData: Data
        switch method {
        case Initialize.name:
            let decoded = try JSONDecoder().decode(Request<Initialize>.self, from: body)
            responseData = try encoder.encode(Initialize.response(id: decoded.id, result: .init(
                protocolVersion: Version.latest, capabilities: .init(tools: .init(listChanged: false)),
                serverInfo: .init(name: "Stateless HTTP fixture", version: "1.0")
            )))
        case InitializedNotification.name:
            return (HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: "HTTP/1.1", headerFields: [:])!, Data())
        case ListTools.name:
            let decoded = try JSONDecoder().decode(Request<ListTools>.self, from: body)
            responseData = try encoder.encode(ListTools.response(id: decoded.id, result: .init(
                tools: [MCPServerFixture.tool("read_issue")]
            )))
        case CallTool.name:
            isToolResponse = true
            let decoded = try JSONDecoder().decode(Request<CallTool>.self, from: body)
            let result = try CallTool.Result(content: [.text(text: "ENG-46", annotations: nil, _meta: nil)],
                                             structuredContent: Value.object(["issue": .string("ENG-46")]),
                                             isError: false, _meta: .init(additionalFields: ["receipt": "http-fixture"]))
            responseData = try encoder.encode(CallTool.response(id: decoded.id, result: result))
        default: throw MCPFixtureError.invalidArguments
        }
        let isSSE = isToolResponse && mode == .sse
        let headers = ["Content-Type": isSSE ? "text/event-stream" : "application/json"]
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        // Deliberately omit MCP-Session-Id, as a valid stateless server does.
        let data = isSSE ? Data("data: \(String(decoding: responseData, as: UTF8.self))\n\n".utf8) : responseData
        return (response, data)
    }

    private func requestBody(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { throw MCPFixtureError.invalidArguments }
        stream.open()
        defer { stream.close() }
        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw stream.streamError ?? MCPFixtureError.invalidArguments }
            if count == 0 { return body }
            body.append(contentsOf: buffer.prefix(count))
        }
    }
}
#endif
