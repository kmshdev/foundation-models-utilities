import EngineeringCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// OAuth credentials are bound to the documented endpoint, never a redirected host.
final class ChatGPTModelRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
