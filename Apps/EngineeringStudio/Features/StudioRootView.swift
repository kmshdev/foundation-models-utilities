import EngineeringCore
import SwiftUI

private enum WorkspaceDestination: Hashable {
    case all, needsInput, outcome(UUID)
}
private enum StudioSheet: String, Identifiable {
    case newOutcome, team, settings
    var id: Self { self }
}

struct StudioRootView: View {
    @Bindable var store: StudioStore
    @State private var destination: WorkspaceDestination?
    @State private var selectedTaskID: String?
    @State private var columns: NavigationSplitViewVisibility = .all
    @State private var compactColumn: NavigationSplitViewColumn = .sidebar
    @State private var sheet: StudioSheet?
    @State private var search = ""

    /// One-time selection seeds for self-contained SwiftUI previews.
    init(store: StudioStore, initialOutcomeID: UUID? = nil, initialTaskID: String? = nil) {
        self.store = store
        _destination = State(initialValue: initialOutcomeID.map(WorkspaceDestination.outcome) ?? .all)
        _selectedTaskID = State(initialValue: initialTaskID)
    }

    private var outcome: Outcome? {
        guard case let .outcome(id) = destination else { return nil }
        return store.workspace.outcomes.first { $0.id == id }
    }
    private var selectedTask: WorkTask? {
        outcome?.plan?.tasks.first { $0.id == selectedTaskID }
    }
    private var pendingIDs: Set<UUID> {
        Set(store.workspace.questions.filter { !$0.isComplete }.map(\.outcomeID))
    }
    private var filteredOutcomes: [Outcome] {
        store.workspace.outcomes.reversed().filter {
            (destination != .needsInput || pendingIDs.contains($0.id)) &&
            (search.isEmpty || $0.text.localizedStandardContains(search))
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $compactColumn) {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 235, max: 300)
        } content: {
            Group {
                if let outcome {
                    EngineeringRoomView(store: store, outcome: outcome, selectedTaskID: $selectedTaskID)
                        .id(outcome.id)
                } else {
                    outcomeList
                }
            }
            .navigationTitle(outcome.map { String($0.text.prefix(55)) } ?? "Engineering")
            .navigationSplitViewColumnWidth(min: 340, ideal: 610)
        } detail: {
            Group {
                if let selectedTask {
                    TaskDetailView(task: selectedTask)
                } else {
                    ContentUnavailableView("Select a task", systemImage: "sidebar.right",
                                           description: Text("Its scope, requirements and handoff appear here."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial, in: .rect(cornerRadius: 22))
            .padding(10)
            .navigationSplitViewColumnWidth(min: 275, ideal: 340, max: 470)
        }
        .navigationSplitViewStyle(.balanced)
        .background { StudioBackdrop() }
        .preferredColorScheme(.dark)
        .tint(.blue)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New outcome", systemImage: "square.and.pencil") { sheet = .newOutcome }
                    .keyboardShortcut("n", modifiers: .command)
                    .help("Start a new outcome")
            }
            ToolbarItem(placement: .primaryAction) {
                if store.isPlanning {
                    Button("Cancel Planning", systemImage: "stop.fill") { store.cancelPlanning() }
                        .tint(.orange)
                } else {
                    Button("Pause Team", systemImage: "pause.fill") { }
                        .tint(.orange).disabled(true)
                        .help("Developer execution is not connected yet")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu("More", systemImage: "ellipsis") {
                    Button("Developers", systemImage: "person.3") { sheet = .team }
                    Button("Settings", systemImage: "gearshape") { sheet = .settings }
                        .keyboardShortcut(",", modifiers: .command)
                }
            }
        }
        #if os(macOS)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        #endif
        .sheet(item: $sheet) { item in
            StudioSheetView(kind: item, store: store)
        }
        .onChange(of: destination) { _, _ in selectedTaskID = nil }
        .onChange(of: selectedTaskID) { _, id in
            if id != nil { compactColumn = .detail }
        }
        .onChange(of: store.workspace.outcomes.last?.id) { _, id in
            if let id { destination = .outcome(id); compactColumn = .content }
        }
        .onChange(of: outcome?.plan) { _, plan in
            if !((plan?.tasks.contains { $0.id == selectedTaskID }) ?? false) { selectedTaskID = nil }
        }
        .alert("Something needs attention", isPresented: Binding(
            get: { store.failure != nil }, set: { if !$0 { store.failure = nil } }
        )) { Button("OK", role: .cancel) { store.failure = nil } }
        message: { Text(store.failure ?? "") }
    }

    private var sidebar: some View {
        List(selection: $destination) {
            Section("Engineering") {
                Label("All outcomes", systemImage: "rectangle.stack").tag(WorkspaceDestination.all)
                HStack {
                    Label("Needs input", systemImage: "bubble.left")
                    Spacer()
                    Text(pendingIDs.count, format: .number).foregroundStyle(.secondary)
                }.tag(WorkspaceDestination.needsInput)
            }
            Section("Outcomes") {
                ForEach(store.workspace.outcomes.reversed()) { item in
                    Label(item.text, systemImage: "doc.text")
                        .lineLimit(2).tag(WorkspaceDestination.outcome(item.id))
                }
            }
            Section("Team") {
                Button { sheet = .team } label: {
                    HStack {
                        Label("Developers", systemImage: "person.3")
                        Spacer()
                        Text(Specialty.allCases.count, format: .number).foregroundStyle(.secondary)
                    }
                }.buttonStyle(.plain)
                Label("0 connected", systemImage: "network.slash")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .navigationTitle("Engineering")
        .searchable(text: $search, prompt: "Search outcomes")
    }

    private var outcomeList: some View {
        List {
            ForEach(filteredOutcomes) { item in
                Button {
                    destination = .outcome(item.id)
                    compactColumn = .content
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.text).font(.headline)
                        Text(item.plan == nil ? "Awaiting a plan" : "\(item.plan!.tasks.count) tasks · Not dispatched")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }.buttonStyle(.plain)
            }
            // Keep pre-thread messages available without attributing them to an unrelated outcome.
            if destination == .all, search.isEmpty {
                let legacy = store.workspace.messages.filter { $0.outcomeID == nil }
                if !legacy.isEmpty {
                    Section("Earlier workspace conversation") {
                        ForEach(legacy) { message in MessageRow(message: message) }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .overlay {
            if filteredOutcomes.isEmpty {
                ContentUnavailableView {
                    Label(search.isEmpty ? "No outcomes here" : "No matching outcomes", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Start with a shared outcome for your engineering team.")
                } actions: {
                    Button("New Outcome", systemImage: "plus") { sheet = .newOutcome }
                        .buttonStyle(.glassProminent).disabled(!store.isLoaded)
                }
            }
        }
    }
}

private struct StudioSheetView: View {
    let kind: StudioSheet
    let store: StudioStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                switch kind {
                case .newOutcome: NewOutcomeView(store: store)
                case .team: TeamView()
                case .settings: StudioSettingsView(store: store)
                }
            }
            .toolbar {
                if kind != .newOutcome {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 620, minHeight: 480, idealHeight: 620)
        #endif
    }
}

private struct NewOutcomeView: View {
    let store: StudioStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    var body: some View {
        Form {
            Section("Shared outcome") {
                TextField("What should the team accomplish?", text: $text, axis: .vertical)
                    .lineLimit(4...10)
            }
            Section("Workspace") {
                LabeledContent("Repository", value: "kmshdev/foundation-models-utilities")
                LabeledContent("Project", value: "Engineering Workflow Automation")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("New outcome")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") { if store.submit(text) { dismiss() } }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.isLoaded)
            }
        }
    }
}

enum StudioStyle {
    static let accent = Color.blue
    static let paper = Color.clear
}

struct StudioBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        Rectangle().fill(.background)
            .overlay {
                if !reduceTransparency {
                    LinearGradient(colors: [.blue.opacity(0.13), .clear, .blue.opacity(0.08)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .ignoresSafeArea()
    }
}

struct SectionEyebrow: View {
    let text: String
    var body: some View { Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary) }
}
struct StudioHeading: View {
    let eyebrow: String
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Text(detail).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
    }
}
struct StatusStrip: View {
    var body: some View {
        HStack {
            Label("8 specialties", systemImage: "person.3")
            Spacer()
            Label("0 connected", systemImage: "network.slash")
        }.font(.caption).foregroundStyle(.secondary).padding(.vertical, 12)
    }
}
