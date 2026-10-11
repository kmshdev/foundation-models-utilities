import SwiftUI

struct StudioSettingsView: View {
    let store: StudioStore
    let connections: ServiceConnections
    var body: some View {
        Form {
            Section {
                LabeledContent("Access", value: "Personal account")
                LabeledContent("Connection", value: "Not connected")
                Text("Your personal ChatGPT connection is not available yet. Messages stay in this workspace until a model connection is ready.")
                    .foregroundStyle(.secondary)
            } header: { Text("ChatGPT") }
            Section {
                Toggle("Use on-device planning", isOn: Binding(get: { store.usesOnDeviceModel }, set: { store.setOnDeviceModel($0) }))
                Text(FoundationPlanner.availabilityDescription).foregroundStyle(.secondary)
                Text("Prepare assignments privately on this device. Developer execution requires a separate connection.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("Apple Intelligence") }
            Section("Project") {
                LabeledContent("App", value: "Engineering Studio")
                LabeledContent("Linear", value: "Engineering Workflow Automation")
                Link("Foundation Models utilities", destination: URL(string: "https://github.com/kmshdev/foundation-models-utilities")!)
                Text("Allowed repository for this engineering workspace.").font(.callout).foregroundStyle(.secondary)
            }
            Section("Connections") {
                NavigationLink {
                    ServiceConnectionsView(connections: connections, store: store)
                } label: { Label("GitHub and Linear", systemImage: "link") }
                Text("Repository activity, workflow evidence and project issue intake.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Team behavior") {
                Text("Use your explicit order, urgent defects, dependency blockers, then Linear priority.")
                Text("Work autonomously within the stated scope. Ask blocking questions together and wait for their answers. Preserve context and report evidence at handoffs.")
            }
            Section("Unavailable connections") {
                Label("Cloudflare developer runtime", systemImage: "cloud")
                Label("Task execution and acceptance verification", systemImage: "checkmark.seal")
            }
        }
        .formStyle(.grouped).scrollContentBackground(.hidden)
        .background(StudioStyle.paper).navigationTitle("Settings")
    }
}
