import StudioWorkflows
import StudioServices
import StudioUI
import EngineeringCore
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct DeveloperRuntimeView: View {
    let runtime: DeveloperRuntimeConnection
    let account: ChatGPTConnection
    @State private var selectingRepository = false
    @State private var selectingCodex = false
    @State private var remoteURL = ""
    @State private var pairingToken = ""
    @State private var accessID = ""
    @State private var accessSecret = ""

    var body: some View {
        Form {
            Section("Developer runtime") {
                LabeledContent("Status", value: runtime.status)
                if let error = runtime.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                if let blocker = runtime.state.blocker { Text(blocker).foregroundStyle(.secondary).textSelection(.enabled) }
                if runtime.isConnecting { ProgressView("Connecting to developers…") }
                if let status = runtime.controlStatus { ProgressView(status) }
                if runtime.hasRuntime {
                    if !runtime.state.connected {
                        Button("Restart developers", systemImage: "play.fill") { Task { do { _ = try await runtime.restart() } catch { runtime.reportError(error) } } }
                            .buttonStyle(.glassProminent).tint(.green)
                            .disabled(runtime.isControlling || runtime.isDisconnecting)
                    }
                    Button("Refresh availability", systemImage: "arrow.clockwise") { Task { await runtime.refresh() } }
                        .disabled(runtime.isControlling || runtime.isDisconnecting)
                    Button("Stop and disconnect", role: .destructive) { Task { await runtime.disconnect() } }
                        .disabled(runtime.isDisconnecting)
                }
            }
            #if os(macOS)
            Section("Run on this Mac") {
                LabeledContent("Repository", value: runtime.repositoryURL?.lastPathComponent ?? "Choose a folder")
                Button("Choose repository", systemImage: "folder") { selectingRepository = true }
                LabeledContent("Codex", value: runtime.codexURL?.lastPathComponent ?? "Choose the installed binary")
                Button("Choose Codex binary", systemImage: "terminal") { selectingCodex = true }
                Button("Connect eight developers", systemImage: "play.fill") { Task { await runtime.connectLocal(using: account) } }
                    .buttonStyle(.glassProminent).tint(.green)
                    .disabled(!account.isReadyForPlanning || runtime.repositoryURL == nil || runtime.codexURL == nil)
                Text("Uses the selected clone and isolated task worktrees. Sign in with ChatGPT and choose a model first.")
                    .font(.callout).foregroundStyle(.secondary)
            }.disabled(runtime.isConnecting || runtime.hasRuntime)
            if runtime.state.connected && !runtime.isRemote {
                Section("Connect from iPhone") {
                    if let origin = runtime.sharingOrigin {
                        LabeledContent("Origin") { Text(origin).textSelection(.enabled) }
                        Text("Use this origin in your Cloudflare Tunnel. Enter its HTTPS address and the pairing code on iPhone.")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("Copy pairing code", systemImage: "doc.on.doc") {
                            if let code = try? runtime.pairingCode() {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(code, forType: .string)
                            }
                        }
                        Button("Stop sharing", role: .destructive) { runtime.stopSharing() }
                    } else {
                        Button("Enable runtime sharing", systemImage: "laptopcomputer.and.iphone") { Task { await runtime.shareRuntime() } }
                            .disabled(runtime.isStartingSharing)
                    }
                }
            }
            #endif
            Section("Connect to a shared runtime") {
                TextField("HTTPS address", text: $remoteURL)
                    #if os(iOS)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    #endif
                SecureField("Pairing code", text: $pairingToken)
                DisclosureGroup("Cloudflare Access credentials") {
                    TextField("Service token client ID", text: $accessID)
                        #if os(iOS)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        #endif
                    SecureField("Service token secret", text: $accessSecret)
                    Text("Required when the runtime is protected by a Cloudflare Access service-token policy.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Button("Connect", systemImage: "link") {
                    Task {
                        await runtime.connectRemote(url: remoteURL, pairingToken: pairingToken,
                                                    accessID: accessID, accessSecret: accessSecret)
                        if runtime.isRemote { pairingToken = ""; accessSecret = "" }
                    }
                }.disabled(remoteURL.isEmpty || pairingToken.isEmpty)
                Button("Reconnect saved runtime", systemImage: "arrow.clockwise") { Task { await runtime.reconnectRemote() } }
                Text("Pairing and Access credentials stay in this device’s Keychain. The execution host keeps its own ChatGPT registration.")
                    .font(.callout).foregroundStyle(.secondary)
            }.disabled(runtime.isConnecting || runtime.hasRuntime)
        }
        .formStyle(.grouped).navigationTitle("Developer Runtime")
        #if os(macOS)
        .fileImporter(isPresented: $selectingRepository, allowedContentTypes: [.folder]) { result in
            switch result { case .success(let url): runtime.selectRepository(url); case .failure(let error): runtime.reportError(error) }
        }
        .fileImporter(isPresented: $selectingCodex, allowedContentTypes: [.item]) { result in
            switch result { case .success(let url): runtime.selectCodex(url); case .failure(let error): runtime.reportError(error) }
        }
        #endif
    }
}
