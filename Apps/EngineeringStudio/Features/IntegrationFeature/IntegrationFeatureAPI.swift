import EngineeringCore
import StudioServices
import StudioWorkflows
import SwiftUI

@MainActor
public enum IntegrationFeatureAPI {
    public static func connections(dependencies: StudioDependencies) -> some View {
        connections(store: dependencies.store, connections: dependencies.connections)
    }

    package static func connections(store: StudioStore, connections: ServiceConnections) -> some View {
        ServiceConnectionsView(connections: connections, store: store)
    }

    /// Captures the same native registration form without presenting a live sign-in session.
    package static func registration(connections: ServiceConnections) -> some View {
        GitHubAppConfigurationSheet(connection: connections.githubMCP)
    }

    package static func accounts(store: StudioStore, chatGPT: ChatGPTConnection) -> some View {
        ChatGPTConnectionView(connection: chatGPT, store: store)
    }

    package static func publishing(outcome: Outcome, store: StudioStore, connections: ServiceConnections,
                                  openConnections: @escaping () -> Void) -> some View {
        PlanPublishingControls(outcome: outcome, store: store, connections: connections, openConnections: openConnections)
    }
}
