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
    private let initialDraft: String
    @State private var destination: WorkspaceDestination?
    @State private var selectedTaskID: String?
    @State private var columns: NavigationSplitViewVisibility = .all
    @State private var compactColumn: NavigationSplitViewColumn = .sidebar
    @State private var sheet: StudioSheet?
    @State private var search = ""

    /// One-time selection seeds for self-contained SwiftUI previews.
    init(store: StudioStore, initialOutcomeID: UUID? = nil, initialTaskID: String? = nil, initialDraft: String = "") {
        self.store = store
        self.initialDraft = initialDraft
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
        workspaceColumns
        .background { StudioBackdrop() }
        .preferredColorScheme(.dark)
        .font(.system(size: 16))
        .tint(.blue)
        .toolbar {
            #if os(macOS)
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 12) {
                    SymbolBadge(symbol: "doc.text", size: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(outcome.map { String($0.text.prefix(45)) } ?? "Engineering")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Engineering").font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                }.padding(.leading, 92)
            }.sharedBackgroundVisibility(.hidden)
            ToolbarSpacer(.flexible, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Search", text: $search).textFieldStyle(.plain)
                                .accessibilityLabel("Search outcomes")
                        }
                        .font(.system(size: 15)).padding(.horizontal, 14).frame(width: 164, height: 38)
                        .glassEffect(.regular, in: .capsule)
                        Button { sheet = .newOutcome } label: {
                            Image(systemName: "square.and.pencil").font(.system(size: 18)).frame(width: 24, height: 28)
                        }
                        .buttonStyle(.glass).buttonBorderShape(.circle).tint(.gray)
                        .keyboardShortcut("n", modifiers: .command)
                        .accessibilityLabel("New outcome").help("Start a new outcome")
                        Button {
                            store.cancelPlanning()
                        } label: {
                            Label(store.isPlanning ? "Cancel Planning" : "Pause Team",
                                  systemImage: store.isPlanning ? "stop.fill" : "pause.fill")
                                .font(.system(size: 15, weight: .medium)).padding(.horizontal, 6).frame(height: 28)
                        }
                        .labelStyle(.titleAndIcon)
                        .buttonStyle(.glass).tint(.orange).disabled(!store.isPlanning)
                        .help(store.isPlanning ? "Cancel planning" : "Developer execution is not connected yet")
                        Menu {
                            Button("Developers", systemImage: "person.2") { sheet = .team }
                            Button("Settings", systemImage: "gearshape") { sheet = .settings }
                                .keyboardShortcut(",", modifiers: .command)
                        } label: {
                            Image(systemName: "ellipsis").font(.system(size: 18)).frame(width: 24, height: 28)
                        }
                        .menuIndicator(.hidden).buttonStyle(.glass).buttonBorderShape(.circle)
                        .accessibilityLabel("More options")
                    }
                }
            }.sharedBackgroundVisibility(.hidden)
            #else
            ToolbarItem(placement: .primaryAction) {
                Button("New outcome", systemImage: "square.and.pencil") { sheet = .newOutcome }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu("More", systemImage: "ellipsis") {
                    Button("Developers", systemImage: "person.2") { sheet = .team }
                    Button("Settings", systemImage: "gearshape") { sheet = .settings }
                    if store.isPlanning {
                        Button("Cancel Planning", systemImage: "stop.fill") { store.cancelPlanning() }
                    }
                }
            }
            #endif
        }
        #if os(macOS)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        #else
        .searchable(text: $search, prompt: "Search outcomes")
        #endif
        .sheet(item: $sheet) { item in
            StudioSheetView(kind: item, store: store)
        }
        .onChange(of: destination) { _, _ in selectedTaskID = nil }
        .onChange(of: search) { _, query in
            if !query.isEmpty { destination = .all; compactColumn = .content }
        }
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

    @ViewBuilder private var workspaceColumns: some View {
        #if os(macOS)
        HSplitView {
            sidebar
                .frame(minWidth: 220, idealWidth: 258, maxWidth: 258)
            conversationColumn
                .frame(minWidth: 430, idealWidth: 610, maxWidth: .infinity)
                .padding(.horizontal, 10)
            detailColumn
                .frame(minWidth: 300, idealWidth: 368, maxWidth: 368)
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 20)
        #else
        NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $compactColumn) {
            sidebar.navigationSplitViewColumnWidth(min: 230, ideal: 258, max: 300)
        } content: {
            conversationColumn
                .navigationTitle(outcome.map { String($0.text.prefix(55)) } ?? "Engineering")
                .navigationSplitViewColumnWidth(min: 340, ideal: 610)
        } detail: {
            detailColumn.navigationSplitViewColumnWidth(min: 300, ideal: 368, max: 420)
        }
        .navigationSplitViewStyle(.balanced)
        #endif
    }

    private var conversationColumn: some View {
        Group {
            if let outcome {
                EngineeringRoomView(store: store, outcome: outcome, selectedTaskID: $selectedTaskID, initialDraft: initialDraft)
                    .id(outcome.id)
            } else { outcomeList }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var detailColumn: some View {
        Group {
            if let selectedTask { TaskDetailView(task: selectedTask) }
            else {
                ContentUnavailableView("Select a task", systemImage: "sidebar.right",
                                       description: Text("Its scope, requirements and handoff appear here."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(WorkspacePanel())
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                sidebarHeading("Engineering")
                destinationRow("All outcomes", symbol: "rectangle.stack", value: .all)
                destinationRow("Needs input", symbol: "bubble.left", value: .needsInput, count: pendingIDs.isEmpty ? nil : pendingIDs.count)
                Divider().padding(.horizontal, 12).padding(.vertical, 13)
                sidebarHeading("Outcomes")
                ForEach(store.workspace.outcomes.reversed()) { item in
                    destinationRow(item.text, symbol: "doc.text", value: .outcome(item.id))
                }
                Divider().padding(.horizontal, 12).padding(.vertical, 13)
                sidebarHeading("Team")
                Button { sheet = .team } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "person.2").font(.system(size: 22)).frame(width: 26)
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Developers")
                            Label("0 connected", systemImage: "circle").font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Text(Specialty.allCases.count, format: .number).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(.secondary)
                    }.padding(.horizontal, 14).padding(.vertical, 12).contentShape(.rect)
                }.buttonStyle(.plain)
            }.padding(.horizontal, 8).padding(.top, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(WorkspacePanel())
        .navigationTitle("Engineering")
    }

    private func sidebarHeading(_ text: String) -> some View {
        Text(text).font(.system(size: 16, weight: .medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .accessibilityAddTraits(.isHeader)
    }

    private func destinationRow(_ title: String, symbol: String, value: WorkspaceDestination, count: Int? = nil) -> some View {
        Button {
            destination = value
            compactColumn = .content
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 21)).frame(width: 26)
                Text(title).font(.system(size: 16)).lineLimit(2)
                Spacer(minLength: 0)
                if let count {
                    Text(count, format: .number).font(.system(size: 14))
                        .padding(.horizontal, 10).padding(.vertical, 4).background(.thinMaterial, in: .capsule)
                }
            }
            .padding(.horizontal, 14).frame(minHeight: 43).contentShape(.rect)
            .background {
                if destination == value {
                    RoundedRectangle(cornerRadius: 11).fill(.blue.gradient)
                        .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(0.24)) }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(destination == value ? [.isSelected] : [])
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
                        Text(item.plan.map { "\($0.tasks.count) tasks · Not dispatched" } ?? "Awaiting a plan")
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
