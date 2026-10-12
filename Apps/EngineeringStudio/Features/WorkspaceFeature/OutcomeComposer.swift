import StudioWorkflows
import StudioServices
import StudioUI
import EngineeringCore
import SwiftUI

/// Draft observation is isolated here, outside conversation filtering/layout.
struct OutcomeComposer: View {
    let store: StudioStore
    let outcomeID: UUID
    @Bindable var draft: OutcomeDraft
    @Environment(\.dynamicTypeSize) private var dynamicType
    @FocusState private var isFocused: Bool

    private var canSend: Bool { store.isLoaded && !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: StudioSpacing.small) {
            // One standard content surface; only Send uses Liquid Glass.
            Group {
                if dynamicType.isAccessibilitySize {
                    VStack(alignment: .trailing, spacing: StudioSpacing.medium) { input; sendButton }
                } else {
                    HStack(alignment: .bottom, spacing: StudioSpacing.medium) { input; sendButton }
                }
            }
            .padding(StudioSpacing.medium)
            .background(.regularMaterial, in: .rect(cornerRadius: StudioRadius.container))
            .overlay {
                RoundedRectangle(cornerRadius: StudioRadius.container).strokeBorder(.primary.opacity(0.10))
                    .allowsHitTesting(false)
            }
            #if !os(macOS)
            HStack {
                Text(store.saveState)
                Spacer()
                if store.saveState == "Changes not saved" { Button("Retry") { store.retrySave() } }
            }.font(StudioTypography.caption).foregroundStyle(.secondary)
            #endif
        }
    }

    private var input: some View {
        TextField("Direct the team…", text: $draft.text, axis: .vertical)
            .font(StudioTypography.body).lineLimit(1...6).textFieldStyle(.plain)
            .padding(StudioSpacing.small).frame(minHeight: 44)
            .focused($isFocused)
            .accessibilityLabel("Message for this outcome")
            .accessibilityHint("Saved in this outcome when you send. Command Return sends the message.")
    }

    private var sendButton: some View {
        Button(action: send) {
            Label("Send", systemImage: "arrow.up")
                .font(StudioTypography.label).padding(.horizontal, StudioSpacing.small)
                .frame(minHeight: 36)
        }
        .buttonStyle(.glassProminent).tint(StudioStyle.accent).controlSize(.large)
        .disabled(!canSend).keyboardShortcut(.return, modifiers: .command)
        .help("Send to the selected outcome")
    }

    private func send() {
        if store.sendDraft(to: outcomeID) { isFocused = true }
    }
}
