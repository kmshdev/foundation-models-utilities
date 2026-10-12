import StudioServices
import StudioWorkflows
import SwiftUI

@MainActor
public enum RuntimeFeatureAPI {
    public static func developers(dependencies: StudioDependencies) -> some View {
        developers(runtime: dependencies.runtime)
    }

    package static func developers(runtime: DeveloperRuntimeConnection) -> some View { TeamView(runtime: runtime) }

    package static func configuration(runtime: DeveloperRuntimeConnection, account: ChatGPTConnection) -> some View {
        DeveloperRuntimeView(runtime: runtime, account: account)
    }

    package static func control(runtime: DeveloperRuntimeConnection, openRuntime: @escaping () -> Void) -> some View {
        DeveloperTeamControl(runtime: runtime, openRuntime: openRuntime)
    }

    package static func availability(runtime: DeveloperRuntimeConnection) -> some View { TeamAvailabilityLabel(runtime: runtime) }
}
