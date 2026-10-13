import StudioServices
import SwiftUI

@MainActor
struct GitHubAppConfigurationSheet: View {
    let connection: ProviderMCPConnection
    let connectAfterSave: Bool
    let registrationSaved: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var clientID: String
    @State private var clientSecret = ""
    @State private var isSaving = false
    @State private var saveTask: Task<Void, Never>?

    private let callback = "engineeringstudio://oauth/github"

    init(connection: ProviderMCPConnection, connectAfterSave: Bool = false,
         registrationSaved: (() -> Void)? = nil) {
        self.connection = connection
        self.connectAfterSave = connectAfterSave
        self.registrationSaved = registrationSaved
        // This is the editable draft for one sheet presentation, not a mirrored binding.
        self.clientID = connection.githubClientID ?? ""
    }

    private var canSave: Bool {
        !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSaving && !connection.isBusy
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Register Engineering Studio as a GitHub App and install it on your repository. Copy the registration’s client ID and client secret here to enable browser sign-in.")
                        .font(.callout).foregroundStyle(.secondary)
                    Link("Register a GitHub App", destination: URL(string: "https://github.com/settings/apps/new")!)
                }
                Section("App registration") {
                    TextField("Client ID", text: $clientID)
                        .modifier(ProviderCredentialFieldStyle())
                    SecureField("Client secret", text: $clientSecret)
                        .modifier(ProviderCredentialFieldStyle())
                    Text("Registration credentials are saved in this device’s Keychain. Saved secrets are never filled into this form.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Section("Authorization callback") {
                    Text(callback)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                    Text("Add this exact callback URL to the GitHub App and leave wildcard matching off.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Section("Repository access") {
                    Text("kmshdev/foundation-models-utilities")
                        .textSelection(.enabled)
                    Text("Select this repository during installation. Read access to Contents, Pull requests, Actions and Checks is enough for the tool connection.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Section {
                    Text("GitHub requires a client secret for native browser sign-in. Native apps cannot keep app registration credentials confidential; PKCE protects this sign-in.")
                        .font(.caption).foregroundStyle(.secondary)
                    if isSaving {
                        ProgressView("Saving registration…").controlSize(.small)
                    }
                    if let error = connection.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("GitHub app")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { cancelAndDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(connectAfterSave ? "Save and connect" : "Save") { save() }
                        .buttonStyle(.glassProminent).tint(.blue)
                        .disabled(!canSave)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 560)
        #endif
        .onDisappear {
            if isSaving { connection.cancel() }
            saveTask?.cancel()
            clientSecret = ""
        }
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        saveTask = Task {
            let identifier = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
            let secret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
            let saved = await connection.configureGitHub(clientID: identifier, clientSecret: secret)
            guard !Task.isCancelled else { return }
            isSaving = false
            if saved {
                clientSecret = ""
                registrationSaved?()
                dismiss()
            }
        }
    }

    private func cancelAndDismiss() {
        if isSaving { connection.cancel() }
        saveTask?.cancel()
        clientSecret = ""
        dismiss()
    }
}
