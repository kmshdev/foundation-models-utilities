import Foundation

enum ProviderCheckFailure: Error, LocalizedError {
    case assertion(String)

    var errorDescription: String? {
        switch self { case .assertion(let message): message }
    }
}

func providerCheckRequire(_ condition: Bool, _ message: String) throws {
    guard condition else { throw ProviderCheckFailure.assertion(message) }
}

func waitForProviderCheckGate(_ gate: ProviderCheckGate) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(3))
    while !(await gate.isWaiting) {
        guard clock.now < deadline else {
            throw ProviderCheckFailure.assertion("The authorization fixture did not reach its gate")
        }
        try await Task.sleep(for: .milliseconds(2))
    }
}
