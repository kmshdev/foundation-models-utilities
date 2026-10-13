import EngineeringCore
import Foundation

/// Incremental framing accepts split UTF-8, LF, CRLF, CR, comments and multiline data.
/// Events are dispatched only on a blank line, as required by the SSE protocol.
struct ChatGPTSSEParser {
    private var line: [UInt8] = []
    private var dataLines: [String] = []
    private var event: String?
    private var skipLineFeed = false
    private var firstLine = true
    private var eventBytes = 0
    private let maximumEventBytes: Int

    init(maximumEventBytes: Int = 1_048_576) { self.maximumEventBytes = maximumEventBytes }

    mutating func append(_ bytes: Data) throws -> [ChatGPTSSEFrame] {
        var frames: [ChatGPTSSEFrame] = []
        for byte in bytes {
            if skipLineFeed {
                skipLineFeed = false
                if byte == 10 { continue }
            }
            if byte == 13 || byte == 10 {
                if let frame = try finishLine() { frames.append(frame) }
                skipLineFeed = byte == 13
            } else {
                line.append(byte)
                guard line.count + eventBytes <= maximumEventBytes else { throw ChatGPTResponsesError.oversizedEvent }
            }
        }
        return frames
    }

    private mutating func finishLine() throws -> ChatGPTSSEFrame? {
        defer { line.removeAll(keepingCapacity: true) }
        if firstLine {
            firstLine = false
            if line.starts(with: [0xEF, 0xBB, 0xBF]) { line.removeFirst(3) }
        }
        guard let text = String(bytes: line, encoding: .utf8) else { throw ChatGPTResponsesError.invalidStream }
        if text.isEmpty {
            defer { dataLines.removeAll(keepingCapacity: true); event = nil; eventBytes = 0 }
            guard !dataLines.isEmpty else { return nil }
            return ChatGPTSSEFrame(event: event, data: Data(dataLines.joined(separator: "\n").utf8))
        }
        eventBytes += line.count + 1
        guard eventBytes <= maximumEventBytes else { throw ChatGPTResponsesError.oversizedEvent }
        if text.hasPrefix(":") { return nil }
        let components = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let field = String(components[0])
        var value = components.count == 2 ? String(components[1]) : ""
        if value.hasPrefix(" ") { value.removeFirst() }
        switch field {
        case "data": dataLines.append(value)
        case "event": event = value
        default: break
        }
        return nil
    }
}
