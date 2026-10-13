import StudioServices
import SwiftUI

/// Reads connection state at the provider boundary instead of invalidating the whole form.
@MainActor
struct MCPConnectionSection: View {
    let connection: ProviderMCPConnection
    var configureGitHub: ((Bool) -> Void)?

    private var providerName: String {
        switch connection.provider {
        case .github: "GitHub"
        case .linear: "Linear"
        }
    }

    private var symbol: String {
        switch connection.provider {
        case .github: "chevron.left.forwardslash.chevron.right"
        case .linear: "list.bullet.rectangle"
        }
    }

    private var canCancel: Bool {
        switch connection.phase {
        case .restoring, .authorizing, .connecting, .refreshing, .configuring: true
        default: false
        }
    }

    var body: some View {
        Section {
            LabeledContent("Status") {
                HStack(spacing: 8) {
                    if connection.isBusy {
                        ProgressView().controlSize(.small)
                            .accessibilityHidden(true)
                    }
                    Text(connection.status)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            LabeledContent("Tool access", value: "Read only")
            if connection.hasSavedAuthorization {
                Label("Authorization saved on this device", systemImage: "key")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let receipt = connection.receipt {
                LabeledContent(connection.phase == .ready ? "Catalog" : "Previous catalog",
                               value: "\(receipt.toolCount) tools discovered")
                DisclosureGroup("Connection details") {
                    LabeledContent("Granted access", value: grantedAccess)
                    LabeledContent("Server", value: receipt.serverName)
                    LabeledContent("Version", value: receipt.serverVersion)
                    LabeledContent("MCP protocol", value: receipt.protocolVersion)
                    LabeledContent("Catalog checked") {
                        Text(receipt.verifiedAt, style: .relative)
                    }
                }
            }
            if let error = connection.error {
                Label {
                    Text(error).textSelection(.enabled)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .foregroundStyle(.red)
                .accessibilityElement(children: .combine)
            }
            GlassEffectContainer(spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { actions }
                        .fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 12) { actions }
                }
            }
        } header: {
            Label("\(providerName) tools", systemImage: symbol)
        } footer: {
            Text(footer)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if connection.phase != .ready {
            Button("Connect \(providerName)", systemImage: "person.crop.circle.badge.checkmark") {
                if connection.provider == .github, connection.githubClientID == nil {
                    configureGitHub?(true)
                } else {
                    Task { await connection.connect() }
                }
            }
            .buttonStyle(.glassProminent).tint(.blue)
            .disabled(connection.isBusy)
        }
        if canCancel {
            Button("Cancel", systemImage: "xmark") { connection.cancel() }
                .buttonStyle(.glass)
                .accessibilityLabel("Cancel \(providerName) connection")
        } else if !connection.isBusy {
            if connection.hasSavedAuthorization {
                Button("Refresh catalog", systemImage: "arrow.clockwise") {
                    Task { await connection.refresh() }
                }
                .buttonStyle(.borderless)
                .accessibilityHint("Checks saved authorization without opening sign-in.")
            }
            if connection.provider == .github, connection.githubClientID != nil {
                Button("App registration", systemImage: "key.horizontal", action: { configureGitHub?(false) })
                    .buttonStyle(.borderless)
            }
            if connection.hasSavedAuthorization || connection.receipt != nil {
                Button("Disconnect", role: .destructive) {
                    Task { await connection.disconnect() }
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Disconnect \(providerName) tools")
            }
        }
    }

    private var footer: String {
        switch connection.provider {
        case .github:
            "Connect GitHub’s tool catalog with browser sign-in. Use the API connection below for repository data and pull request writes."
        case .linear:
            "Browser sign-in registers this app automatically and connects Linear’s read-only tool catalog. Project imports and task publication use the API connection below."
        }
    }

    private var grantedAccess: String {
        if connection.provider == .github { return "App installation permissions" }
        let scopes = connection.grantedScopes.sorted()
        return scopes.isEmpty ? "Not reported by the server" : scopes.joined(separator: ", ")
    }
}
