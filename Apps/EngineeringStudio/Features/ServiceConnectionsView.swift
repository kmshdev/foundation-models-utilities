import EngineeringCore
import SwiftUI

struct ServiceConnectionsView: View {
    let connections: ServiceConnections
    let store: StudioStore
    @State private var githubToken = ""
    @State private var linearToken = ""

    var body: some View {
        Form {
            Section("GitHub") {
                LabeledContent("Repository", value: "kmshdev/foundation-models-utilities")
                LabeledContent("Access", value: connections.githubStatus)
                if let date = connections.githubUpdatedAt { LabeledContent("Updated") { Text(date, style: .relative) } }
                if let error = connections.githubError { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                HStack {
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await connections.refreshGitHub() } }
                    if connections.refreshingGitHub { ProgressView().controlSize(.small) }
                }.disabled(connections.refreshingGitHub)
                DisclosureGroup(connections.hasGitHubCredential ? "Replace saved token" : "Add account access") {
                    SecureField("GitHub personal access token", text: $githubToken)
                        .textContentType(.password)
                    Text("Public repository results load without a token. A repository-scoped token enables account access; credentials stay in this device’s Keychain.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Save GitHub connection") {
                        Task { if await connections.connectGitHub(token: githubToken) { githubToken = "" } }
                    }.disabled(githubToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || connections.refreshingGitHub)
                    if connections.hasGitHubCredential {
                        Button("Remove saved token", role: .destructive) { Task { await connections.disconnectGitHub() } }
                            .disabled(connections.refreshingGitHub)
                    }
                }
            }
            Section("Pull requests") {
                if connections.pullRequests.isEmpty { Text("No pull requests loaded.").foregroundStyle(.secondary) }
                ForEach(connections.pullRequests) { pull in
                    VStack(alignment: .leading, spacing: 6) {
                        Link("#\(pull.number) · \(pull.title)", destination: pull.webURL)
                        Text("\(pull.state)\(pull.isDraft ? " · Draft" : "") · \(pull.headSHA.prefix(8))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Workflow evidence") {
                Text("Repository runs report their own status. They are not automatically proof that a planned task passed its acceptance criteria.")
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(connections.workflowRuns) { run in
                    VStack(alignment: .leading, spacing: 6) {
                        Link(run.name ?? "Workflow run", destination: run.webURL)
                        Text("\(run.conclusion ?? run.status) · \(run.headSHA.prefix(8))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if connections.githubTruncated { Text("Showing a limited set of recent results. Open GitHub for the full history.").font(.caption) }
            }
            Section("Linear") {
                LabeledContent("Project", value: "Engineering Workflow Automation")
                LabeledContent("Access", value: connections.linearStatus)
                if let date = connections.linearUpdatedAt { LabeledContent("Updated") { Text(date, style: .relative) } }
                if let error = connections.linearError { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                HStack {
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await connections.refreshLinear() } }
                        .disabled(!connections.hasLinearCredential || connections.refreshingLinear)
                    if connections.refreshingLinear { ProgressView().controlSize(.small) }
                }
                DisclosureGroup(connections.hasLinearCredential ? "Replace saved API key" : "Connect Linear") {
                    SecureField("Linear personal API key", text: $linearToken).textContentType(.password)
                    Text("Use a personal key with access to the Engineering project. The app verifies the project before saving it in Keychain.")
                        .font(.callout).foregroundStyle(.secondary)
                    Link("Manage Linear API keys", destination: URL(string: "https://linear.app/settings/account/security")!)
                    Button("Save Linear connection") {
                        Task { if await connections.connectLinear(token: linearToken) { linearToken = "" } }
                    }.disabled(linearToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || connections.refreshingLinear)
                    if connections.hasLinearCredential {
                        Button("Disconnect Linear", role: .destructive) { connections.disconnectLinear() }
                            .disabled(connections.refreshingLinear || connections.publishingOutcomeID != nil)
                    }
                }
            }
            Section("Project issues") {
                if connections.issues.isEmpty { Text("No project issues loaded.").foregroundStyle(.secondary) }
                ForEach(connections.issues) { issue in
                    VStack(alignment: .leading, spacing: 8) {
                        Link("\(issue.identifier) · \(issue.title)", destination: issue.webURL)
                        Text(issue.state.name).font(.caption).foregroundStyle(.secondary)
                        Button(store.hasImportedIssue(id: issue.id) ? "Imported" : "Use as outcome", systemImage: "square.and.arrow.down") {
                            store.importIssue(issue)
                        }.disabled(!store.isLoaded || store.hasImportedIssue(id: issue.id))
                    }
                }
                if connections.linearTruncated { Text("Showing a limited set of issues. Open Linear for the full project.").font(.caption) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Connections")
    }
}

struct PlanPublishingControls: View {
    let outcome: Outcome
    let store: StudioStore
    let connections: ServiceConnections
    let openConnections: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if connections.hasLinearCredential {
                Button("Publish tasks to Linear", systemImage: "arrow.up.doc") {
                    Task { await connections.publishPlan(for: outcome, store: store) }
                }
                .disabled(connections.publishingOutcomeID != nil || store.isPlanning)
                if connections.publishingOutcomeID == outcome.id {
                    ProgressView(connections.publicationStatus ?? "Publishing…").controlSize(.small)
                }
                if connections.lastPublicationOutcomeID == outcome.id, let error = connections.publicationError {
                    Text(error).foregroundStyle(.red)
                }
            } else {
                Button("Connect Linear to publish tasks", systemImage: "link", action: openConnections)
            }
            if let plan = outcome.plan {
                let linkedCount = plan.tasks.filter {
                    store.issueBinding(outcomeID: outcome.id, taskID: $0.id)?.publishedTask == $0
                }.count
                if linkedCount > 0 {
                    Text("\(linkedCount) of \(plan.tasks.count) tasks synced to Linear. Developer execution is separate.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
