import Foundation

struct ChatGPTSSEFrame: Sendable {
    let event: String?
    let data: Data
}
