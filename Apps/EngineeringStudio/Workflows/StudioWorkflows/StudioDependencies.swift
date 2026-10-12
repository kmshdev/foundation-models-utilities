import EngineeringCore
import StudioServices

/// Composition surface for the application and feature entry points.
/// Services perform I/O; this workflow owns their lifecycle and coordination.
@MainActor
public final class StudioDependencies {
    package let store: StudioStore
    package let connections: ServiceConnections
    package let chatGPT: ChatGPTConnection
    package let runtime: DeveloperRuntimeConnection
    private var startup: Task<Void, Never>?

    public var planningIdentity: StudioPlanningIdentity {
        .init(accountID: chatGPT.activeAccount?.id, model: chatGPT.selectedModel, isSignedIn: chatGPT.isSignedIn)
    }

    public func modelContextChanged() { store.cancelPlanning() }

    public init() {
        store = StudioStore(); connections = ServiceConnections()
        chatGPT = ChatGPTConnection(); runtime = DeveloperRuntimeConnection()
    }

    public func start() async {
        if let startup { await startup.value; return }
        let task = Task { @MainActor [self] in
            runtime.configure(store: store, connections: connections)
            await runtime.load()
            chatGPT.configureBeforeAccountChange { [store, runtime] in
                store.cancelPlanning()
                if runtime.needsAccountDisconnect { await runtime.disconnect() }
            }
            store.configureExecutionContext { [runtime] in runtime.planningContext(for: $0) }
            store.configurePlanPrepared { [store, runtime] in runtime.enqueue($0, store: store) }
            store.configureSubscriptionPlanner { [chatGPT] outcome, answers in
                try await FoundationPlanner.subscription(outcome: outcome, answers: answers,
                                                         client: chatGPT.responsesClient,
                                                         modelName: chatGPT.requireSelectedModel())
            }
            await store.load()
            async let services: Void = connections.load()
            async let account: Void = chatGPT.load()
            _ = await (services, account)
        }
        startup = task
        await task.value
    }

    /// Flushes on scene inactivity without imposing an extra user review step.
    @discardableResult public func flush() async -> Bool {
        guard store.isLoaded else { return true }
        return await store.flushPendingChanges()
    }

    public func prepareForTermination() async -> Bool {
        guard await flush() else { return false }
        await runtime.disconnect()
        return true
    }
}
