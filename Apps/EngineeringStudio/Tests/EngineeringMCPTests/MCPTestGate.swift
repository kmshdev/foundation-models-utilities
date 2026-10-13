actor MCPTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Deliberately ignores task cancellation so a queued timer can be released
    /// after the response won, reproducing the actor-hop cancellation race.
    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}
