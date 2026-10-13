import EngineeringCore

/// A gate makes concurrent scene startup overlap without timers or real credentials.
actor StartupCredentialVault: ChatGPTCredentialVault {
    private var state: ChatGPTCredentialState?
    private var gate: CheckedContinuation<Void, Never>?
    private var pausesFirstLoad = true
    private(set) var loadCount = 0
    var isWaiting: Bool { gate != nil }

    func load() async -> ChatGPTCredentialState? {
        loadCount += 1
        if pausesFirstLoad {
            await withCheckedContinuation { gate = $0 }
        }
        return state
    }

    func save(_ state: ChatGPTCredentialState) { self.state = state }

    func release() {
        pausesFirstLoad = false
        let continuation = gate
        gate = nil
        continuation?.resume()
    }
}
