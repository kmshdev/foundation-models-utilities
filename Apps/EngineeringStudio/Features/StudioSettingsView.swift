import SwiftUI

struct StudioSettingsView: View {
    @Bindable var store: StudioStore
    var body: some View {
        Form {
            Section {
                LabeledContent("Access", value: "Personal account")
                LabeledContent("Connection", value: "Not implemented")
                Text("ChatGPT subscription access remains a required integration. This app does not treat an API key as a ChatGPT subscription or require a Mac to authenticate.")
                    .foregroundStyle(.secondary)
            } header: { Text("ChatGPT") }
            Section {
                Toggle("Use on-device planning", isOn: Binding(get: { store.usesOnDeviceModel }, set: { store.setOnDeviceModel($0) }))
                Text(FoundationPlanner.availabilityDescription).foregroundStyle(.secondary)
                Text("Optional Apple Intelligence planning on this device. It does not activate developer bots or replace your requested ChatGPT connection.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("Apple Intelligence") }
            Section("Project") {
                LabeledContent("App", value: "Engineering Studio")
                LabeledContent("Linear", value: "Engineering Workflow Automation")
                Link("Foundation Models utilities", destination: URL(string: "https://github.com/kmshdev/foundation-models-utilities")!)
                Text("The app uses the utilities as a local Swift package in this repository.").font(.callout).foregroundStyle(.secondary)
            }
            Section("Team behavior") {
                Text("Use your explicit order, urgent defects, dependency blockers, then Linear priority.")
                Text("Work autonomously within the stated scope. Ask blocking questions together and wait for their answers. Preserve context and report evidence at handoffs.")
            }
            Section("Connections still to build") {
                Label("GitHub and Linear synchronization", systemImage: "link")
                Label("Cloudflare developer runtime", systemImage: "cloud")
                Label("Commit, test and pull request verification", systemImage: "checkmark.seal")
            }
        }
        .formStyle(.grouped).scrollContentBackground(.hidden)
        .background(StudioStyle.paper).navigationTitle("Settings")
    }
}
