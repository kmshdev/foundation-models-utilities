import RuntimeFeature
import IntegrationFeature
import StudioWorkflows
import StudioServices
import StudioUI
import EngineeringCore
import SwiftUI

struct StudioSettingsView: View {
    let store: StudioStore
    let connections: ServiceConnections
    let chatGPT: ChatGPTConnection
    var runtime: DeveloperRuntimeConnection = DeveloperRuntimeConnection()
    var body: some View {
        Form {
            Section {
                LabeledContent("Access", value: "Personal account")
                LabeledContent("Connection", value: chatGPT.status)
                NavigationLink {
                    IntegrationFeatureAPI.accounts(store: store, chatGPT: chatGPT)
                } label: { Label("ChatGPT accounts and models", systemImage: "person.crop.circle") }
            } header: { Text("ChatGPT") }
            Section {
                Picker("Planning model", selection: Binding(get: { store.planningProvider }, set: { store.setPlanningProvider($0) })) {
                    ForEach(PlanningProvider.allCases) { provider in Text(provider.title).tag(provider) }
                }
                Text(FoundationPlanner.availabilityDescription).foregroundStyle(.secondary)
                Text("Apple Intelligence prepares assignments on this device. ChatGPT uses your signed-in subscription and selected model.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("Planning") }
            Section("Project") {
                LabeledContent("App", value: "Engineering Studio")
                LabeledContent("Linear", value: "Engineering Workflow Automation")
                Link("Foundation Models utilities", destination: URL(string: "https://github.com/kmshdev/foundation-models-utilities")!)
                Text("Allowed repository for this engineering workspace.").font(.callout).foregroundStyle(.secondary)
            }
            Section("Connections") {
                NavigationLink {
                    IntegrationFeatureAPI.connections(store: store, connections: connections)
                } label: { Label("GitHub and Linear", systemImage: "link") }
                Text("Repository activity, workflow evidence and project issue intake.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Team behavior") {
                Text("Use your explicit order, urgent defects, dependency blockers, then Linear priority.")
                Text("Work autonomously within the stated scope. Ask blocking questions together and wait for their answers. Preserve context and report evidence at handoffs.")
            }
            Section("Developer execution") {
                NavigationLink { RuntimeFeatureAPI.configuration(runtime: runtime, account: chatGPT) } label: {
                    Label("Developer runtime", systemImage: "terminal")
                }
                LabeledContent("Availability", value: runtime.status)
                Text("Newly prepared plans run automatically while developers are connected. Existing plans can be run from their conversation.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).scrollContentBackground(.hidden)
        .background(StudioStyle.paper).navigationTitle("Settings")
    }
}
