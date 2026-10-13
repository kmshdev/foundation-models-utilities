import StudioWorkflows
import StudioServices
import StudioUI
import EngineeringCore
import SwiftUI

struct NewOutcomeView: View {
    let store: StudioStore
    @Bindable var draft: OutcomeDraft
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    init(store: StudioStore) {
        self.store = store
        draft = store.newOutcomeDraft
    }

    var body: some View {
        Form {
            Section("Shared outcome") {
                TextField("What should the team accomplish?", text: $draft.text, axis: .vertical)
                    .lineLimit(4...10).focused($isFocused)
                    .accessibilityLabel("Shared engineering outcome")
                Text("Your draft is saved on this device. Describe the result; the coordinator prepares the assignments and handoffs.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Workspace") {
                LabeledContent("Repository", value: "kmshdev/foundation-models-utilities")
                LabeledContent("Project", value: "Engineering Workflow Automation")
            }
        }
        .formStyle(.grouped).navigationTitle("New outcome")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") { if store.createOutcomeFromDraft() != nil { dismiss() } }
                    .disabled(draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.isLoaded)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .onAppear { isFocused = true }
    }
}
