import EngineeringCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// URLSession callbacks are serialized through the lock, including cancellation before the task is installed.
final class ExecutionRemoteExchange: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ServiceHTTPResponse, any Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var response: HTTPURLResponse?
    private var data = Data()
    private var finished = false

    func start(_ request: URLRequest, continuation: CheckedContinuation<ServiceHTTPResponse, any Error>) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        let publication = request.url?.path == "/v1/execution/publish"
        configuration.timeoutIntervalForResource = TimeInterval(publication ? ExecutionRemoteLimits.publicationTimeoutSeconds : ExecutionRemoteLimits.requestTimeoutSeconds)
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: request)
        lock.lock()
        if finished { lock.unlock(); session.invalidateAndCancel(); continuation.resume(throwing: CancellationError()); return }
        self.continuation = continuation; self.session = session; self.task = task
        lock.unlock()
        task.resume()
    }

    func cancel() { finish(.failure(CancellationError())) }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else { completionHandler(.cancel); finish(.failure(ExecutionRemoteError.invalidResponse)); return }
        guard response.expectedContentLength <= Int64(ExecutionRemoteLimits.maximumResponseBytes) else {
            completionHandler(.cancel); finish(.failure(ExecutionRemoteError.oversizedResponse)); return
        }
        lock.lock(); self.response = http; let active = !finished; lock.unlock()
        completionHandler(active ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        let tooLarge = chunk.count > ExecutionRemoteLimits.maximumResponseBytes - data.count
        if !tooLarge { data.append(chunk) }
        lock.unlock()
        if tooLarge { finish(.failure(ExecutionRemoteError.oversizedResponse)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error {
            if (error as? URLError)?.code == .timedOut { finish(.failure(ExecutionRemoteError.timedOut)) }
            else { finish(.failure(ExecutionRemoteError.unavailable)) }
            return
        }
        lock.lock()
        let response = self.response, bytes = data
        lock.unlock()
        guard let response else { finish(.failure(ExecutionRemoteError.invalidResponse)); return }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) {
            if let key = $1.key as? String, let value = $1.value as? String { $0[key] = value }
        }
        finish(.success(ServiceHTTPResponse(data: bytes, statusCode: response.statusCode, headers: headers)))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    private func finish(_ result: Result<ServiceHTTPResponse, any Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = self.continuation, session = self.session
        self.continuation = nil; self.session = nil; task = nil
        lock.unlock()
        session?.invalidateAndCancel()
        continuation?.resume(with: result)
    }
}
