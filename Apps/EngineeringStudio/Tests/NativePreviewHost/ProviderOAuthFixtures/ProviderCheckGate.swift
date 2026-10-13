/// Deterministic fixture gate. It deliberately ignores task cancellation so a
/// delayed adapter completion can exercise the production generation fence.
actor ProviderCheckGate {
    private var suspendNext = false
    private var continuation: CheckedContinuation<Void, Never>?

    var isWaiting: Bool { continuation != nil }

    func suspendNextOperation() { suspendNext = true }

    func waitIfSuspended() async {
        guard suspendNext else { return }
        suspendNext = false
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        let pending = continuation
        continuation = nil
        pending?.resume()
    }
}
