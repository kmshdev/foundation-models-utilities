import SwiftUI

struct ChatGPTConnectionView: View {
    let connection: ChatGPTConnection
    let store: StudioStore

    var body: some View {
        Form {
            Section("ChatGPT subscription") {
                LabeledContent("Connection", value: connection.status)
                if let account = connection.activeAccount {
                    if let name = account.displayName { LabeledContent("Name", value: name) }
                    if let email = account.email { LabeledContent("Account", value: email) }
                }
                Text("Sign in to use models included with your personal ChatGPT account. Account credentials are stored in this device’s Keychain.")
                    .font(.callout).foregroundStyle(.secondary)
                if connection.isSigningIn {
                    HStack {
                        ProgressView().controlSize(.small)
                        Button("Cancel Sign-in", systemImage: "xmark") { connection.cancelSignIn() }
                    }
                } else {
                    Button(connection.isSignedIn ? "Add ChatGPT account" : "Sign in with ChatGPT", systemImage: "person.crop.circle.badge.checkmark") {
                        Task {
                            await connection.signIn(addAccount: connection.isSignedIn)
                            if connection.isReadyForPlanning { store.setPlanningProvider(.chatGPT) }
                        }
                    }.buttonStyle(.glassProminent).tint(.blue)
                        .disabled(connection.isRefreshing)
                    if connection.activeAccount?.isSignedIn == true && !connection.isSignedIn {
                        Button("Enable subscription access", systemImage: "checkmark.shield") {
                            Task {
                                await connection.signIn(enablePlanUsage: true)
                                if connection.isReadyForPlanning { store.setPlanningProvider(.chatGPT) }
                            }
                        }.disabled(connection.isRefreshing)
                    }
                }
                if let error = connection.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                if connection.catalogState == .failed {
                    Button("Sign in again", systemImage: "arrow.clockwise.circle") {
                        Task { await connection.signIn() }
                    }.disabled(connection.isSigningIn || connection.isRefreshing)
                }
                if let status = connection.signOutStatus { Text(status).font(.callout).foregroundStyle(.secondary) }
            }
            if !connection.accounts.isEmpty {
                Section("Accounts") {
                    Picker("Selected account", selection: Binding(
                        get: { connection.activeAccount?.id ?? "" },
                        set: { id in Task { await connection.selectAccount(id) } }
                    )) {
                        ForEach(connection.accounts) { account in
                            Text(account.email ?? account.displayName ?? "ChatGPT account").tag(account.id)
                        }
                    }.disabled(connection.isSigningIn || connection.isRefreshing)
                    Button("Sign out of selected account", role: .destructive) {
                        store.cancelPlanning()
                        Task { await connection.signOut() }
                    }.disabled(connection.isSigningIn)
                }
            }
            if connection.isSignedIn {
                Section("Models") {
                    Picker("Planning model", selection: Binding(
                        get: { connection.selectedModel }, set: { connection.selectModel($0) }
                    )) {
                        Text("Choose a model").tag(Optional<String>.none)
                        ForEach(connection.models) { model in
                            Text(model.displayName).tag(Optional(model.slug))
                        }
                    }.disabled(connection.isRefreshing)
                    HStack {
                        Button("Refresh models", systemImage: "arrow.clockwise") { Task { await connection.refreshModels() } }
                        if connection.isRefreshing { ProgressView().controlSize(.small) }
                    }.disabled(connection.isRefreshing)
                    Button("Use for planning", systemImage: "brain") { store.setPlanningProvider(.chatGPT) }
                        .disabled(!connection.isReadyForPlanning || store.planningProvider == .chatGPT)
                    Text("Model availability and usage limits come from your ChatGPT account.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("ChatGPT")
    }
}
