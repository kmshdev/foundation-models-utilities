import StudioWorkflows
import StudioServices
import StudioUI
import EngineeringCore
import SwiftUI

/// Team controls observe runtime transitions without invalidating the conversation.
struct DeveloperTeamControl: View {
    let runtime: DeveloperRuntimeConnection
    let openRuntime: () -> Void

    private var title: String {
        if let status = runtime.controlStatus { return status }
        if runtime.isConnecting { return "Connecting…" }
        if runtime.isDisconnecting { return "Disconnecting…" }
        if runtime.state.connected { return "Pause Team" }
        return runtime.hasRuntime ? "Restart Team" : "Connect Team"
    }
    private var symbol: String {
        runtime.state.connected ? "pause.fill" : (runtime.hasRuntime ? "play.fill" : "link")
    }
    private var tint: Color {
        runtime.state.connected ? .orange : (runtime.hasRuntime ? .green : StudioStyle.accent)
    }

    var body: some View {
        Button(action: perform) {
            Label(title, systemImage: symbol)
                .font(StudioTypography.label).padding(.horizontal, 6).frame(minHeight: 28)
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.glass).tint(tint)
        .disabled(runtime.isControlling || runtime.isConnecting || runtime.isDisconnecting)
        .help(runtime.state.connected ? "Pause developers and retain their context" : "Connect or restart the developer team")
    }

    private func perform() {
        guard runtime.hasRuntime else { openRuntime(); return }
        Task {
            do {
                if runtime.state.connected { _ = try await runtime.stop() }
                else { _ = try await runtime.restart() }
            } catch { runtime.reportError(error) }
        }
    }
}
