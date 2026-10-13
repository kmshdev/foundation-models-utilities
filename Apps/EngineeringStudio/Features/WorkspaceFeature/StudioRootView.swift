import RuntimeFeature
import StudioWorkflows
import StudioServices
import StudioUI
import EngineeringCore
import SwiftUI

struct StudioRootView: View {
    let store: StudioStore
    let connections: ServiceConnections
    let chatGPT: ChatGPTConnection
    let runtime: DeveloperRuntimeConnection
    private let navigation: WorkspaceNavigation?
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif
    private let initialDraft: String
    @State private var destination: WorkspaceDestination?
    @State private var selectedTaskID: String?
    @State private var columns: NavigationSplitViewVisibility = .all
    @State private var compactColumn: NavigationSplitViewColumn = .sidebar
    @State private var sheet: StudioSheet?
    @State private var search = ""
    @State private var routing: WorkspaceRouting
    @State private var routedTaskID: String?
    @State private var routedOutcomeID: UUID?
    #if os(macOS)
    @State private var showsSidebar = true
    #endif

    /// One-time selection seeds for self-contained SwiftUI previews.
    init(store: StudioStore, connections: ServiceConnections = ServiceConnections(), chatGPT: ChatGPTConnection = ChatGPTConnection(),
         runtime: DeveloperRuntimeConnection = DeveloperRuntimeConnection(),
         initialOutcomeID: UUID? = nil, initialTaskID: String? = nil, initialDraft: String = "",
         navigation: WorkspaceNavigation? = nil) {
        self.store = store
        self.connections = connections
        self.chatGPT = chatGPT
        self.runtime = runtime
        self.navigation = navigation
        self.initialDraft = initialDraft
        _destination = State(initialValue: initialOutcomeID.map(WorkspaceDestination.outcome) ?? .all)
        _selectedTaskID = State(initialValue: initialTaskID)
        self.routing = WorkspaceRouting(preservesInitialSelection: initialOutcomeID != nil)
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
    private var visibleLegacyMessages: [RoomMessage] {
        guard destination == .all, search.isEmpty else { return [] }
        return store.workspace.messages.filter { $0.outcomeID == nil }
    }

    private var routingInput: WorkspaceRoutingInput {
        .init(isLoaded: store.isLoaded, latestOutcomeID: store.workspace.outcomes.last?.id,
              requestID: navigation?.requestID)
    }

    var body: some View {
        workspaceColumns
        .background { StudioBackdrop() }
        .font(StudioTypography.body)
        .tint(StudioStyle.accent)
        #if os(macOS)
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 6) {
                Text(store.saveState)
                if store.saveState == "Changes not saved" { Button("Retry") { store.retrySave() } }
            }
            .font(StudioTypography.caption).foregroundStyle(.secondary)
            .padding(.trailing, 20).padding(.bottom, 12)
        }
        #endif
        .toolbar {
            #if os(macOS)
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 12) {
                    Button("Toggle sidebar", systemImage: "sidebar.left") { showsSidebar.toggle() }
                        .labelStyle(.iconOnly).keyboardShortcut("s", modifiers: [.command, .control])
                    SymbolBadge(symbol: "doc.text", size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(outcome?.text ?? "Engineering")
                            .font(.headline).lineLimit(1).help(outcome?.text ?? "Engineering")
                        Text("Engineering").font(StudioTypography.secondary).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 280, alignment: .leading)
                }
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
                        .font(StudioTypography.body).padding(.horizontal, 14).frame(width: 164, height: 38)
                        .glassEffect(.regular, in: .capsule)
                        Button { sheet = .newOutcome } label: {
                            Image(systemName: "square.and.pencil").font(.system(size: 18)).frame(width: 40, height: 40)
                                .glassEffect(.regular.interactive(), in: .circle)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut("n", modifiers: .command)
                        .accessibilityLabel("New outcome").help("Start a new outcome").disabled(!store.isLoaded)
                        RuntimeFeatureAPI.control(runtime: runtime, openRuntime: { sheet = .runtime })
                        Menu {
                            Button("Developers", systemImage: "person.2") { sheet = .team }
                            Button("Connections", systemImage: "link") { sheet = .connections }
                            Button("Developer runtime", systemImage: "terminal") { sheet = .runtime }
                            Button("Settings", systemImage: "gearshape") { openSettings() }
                            if store.isPlanning {
                                Button("Cancel Planning", systemImage: "stop.fill") { store.cancelPlanning() }
                            }
                        } label: {
                            Image(systemName: "ellipsis").font(.system(size: 18)).frame(width: 40, height: 40)
                        }
                        .menuIndicator(.hidden).buttonStyle(.glass).buttonBorderShape(.circle)
                        .accessibilityLabel("More options")
                    }
                }
            }.sharedBackgroundVisibility(.hidden)
            #endif
        }
        #if os(macOS)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        #else
        .searchable(text: $search, prompt: "Search outcomes")
        #endif
        .sheet(item: $sheet) { item in
            StudioSheetView(kind: item, store: store, connections: connections, chatGPT: chatGPT, runtime: runtime)
        }
        .onChange(of: destination) { _, _ in
            if outcome?.id == routedOutcomeID { selectedTaskID = routedTaskID }
            else { selectedTaskID = nil }
            routedOutcomeID = nil; routedTaskID = nil
        }
        .onChange(of: routingInput, initial: true) { _, input in applyRouting(input) }
        .onChange(of: search) { _, query in
            if !query.isEmpty { destination = .all; compactColumn = .content }
        }
        .onChange(of: outcome?.plan) { _, plan in
            if !((plan?.tasks.contains { $0.id == selectedTaskID }) ?? false) { selectedTaskID = nil }
        }
        .alert("Something needs attention", isPresented: Binding(
            get: { store.failure != nil }, set: { if !$0 { store.failure = nil } }
        )) { Button("OK", role: .cancel) { store.failure = nil } }
        message: { Text(store.failure ?? "") }
    }

    private func applyRouting(_ input: WorkspaceRoutingInput) {
        switch routing.resolve(input, request: navigation?.request, outcomes: store.workspace.outcomes) {
        case .none:
            return
        case .missingOutcome:
            store.failure = "This outcome is not saved in this workspace."
            return
        case .select(let outcomeID, let taskID):
            if destination == .outcome(outcomeID) { selectedTaskID = taskID }
            else {
                routedOutcomeID = outcomeID; routedTaskID = taskID
                destination = .outcome(outcomeID)
            }
            compactColumn = taskID == nil ? .content : .detail
        }
    }

    #if os(iOS)
    @ToolbarContentBuilder private var mobileControls: some ToolbarContent {
            ToolbarItem(placement: .primaryAction) {
                Button("New outcome", systemImage: "square.and.pencil") { sheet = .newOutcome }
                    .disabled(!store.isLoaded)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu("More", systemImage: "ellipsis") {
                    Button("Developers", systemImage: "person.2") { sheet = .team }
                    Button("Connections", systemImage: "link") { sheet = .connections }
                            Button("Developer runtime", systemImage: "terminal") { sheet = .runtime }
                    Button("Settings", systemImage: "gearshape") { sheet = .settings }
                    if runtime.state.connected {
                        Button("Pause Team", systemImage: "pause.fill") { Task { do { _ = try await runtime.stop() } catch { runtime.reportError(error) } } }
                            .disabled(runtime.isControlling || runtime.isDisconnecting)
                    } else if runtime.hasRuntime {
                        Button("Restart developers", systemImage: "play.fill") { Task { do { _ = try await runtime.restart() } catch { runtime.reportError(error) } } }
                            .disabled(runtime.isControlling || runtime.isConnecting || runtime.isDisconnecting)
                    }
                    if store.isPlanning {
                        Button("Cancel Planning", systemImage: "stop.fill") { store.cancelPlanning() }
                    }
                }
            }
    }
    #endif

    @ViewBuilder private var workspaceColumns: some View {
        #if os(macOS)
        HSplitView {
            if showsSidebar {
                sidebar.frame(minWidth: 220, idealWidth: 258, maxWidth: 258)
            }
            conversationColumn
                .frame(minWidth: 430, idealWidth: 610, maxWidth: .infinity)
                .padding(.horizontal, 10)
            detailColumn
                .frame(minWidth: 300, idealWidth: 368, maxWidth: 368)
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 38)
        #else
        NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $compactColumn) {
            sidebar.navigationSplitViewColumnWidth(min: 230, ideal: 258, max: 300)
                .toolbar { mobileControls }
        } content: {
            conversationColumn
                .navigationTitle(outcome.map { String($0.text.prefix(55)) } ?? "Engineering")
                .navigationSplitViewColumnWidth(min: 340, ideal: 610)
                .toolbar { mobileControls }
        } detail: {
            detailColumn.navigationSplitViewColumnWidth(min: 300, ideal: 368, max: 420)
                .toolbar { mobileControls }
        }
        .navigationSplitViewStyle(.balanced)
        #endif
    }

    private var conversationColumn: some View {
        Group {
            if !store.isLoaded {
                ContentUnavailableView {
                    Label(store.saveState, systemImage: "externaldrive")
                } description: {
                    Text("Your workspace must open before you can make changes.")
                } actions: {
                    Button("Retry") { Task { await store.load() } }
                }
            } else if let outcome {
                EngineeringRoomView(store: store, connections: connections, runtime: runtime, outcome: outcome, selectedTaskID: selectedTaskID,
                                    initialDraft: initialDraft, openConnections: { sheet = .connections },
                                    openSettings: {
                                        #if os(macOS)
                                        openSettings()
                                        #else
                                        sheet = .settings
                                        #endif
                                    }, openRuntime: { sheet = .runtime }) { taskID in
                    selectedTaskID = taskID
                    // A repeated selection must reopen the detail after Back,
                    // even when the highlighted task ID hasn't changed.
                    compactColumn = .detail
                }
                    .id(outcome.id)
            } else { outcomeList }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var detailColumn: some View {
        Group {
            if let selectedTask, let outcome {
                TaskInspectorColumn(task: selectedTask, outcomeID: outcome.id, store: store, runtime: runtime)
            }
            else {
                ContentUnavailableView("Select a task", systemImage: "sidebar.right",
                                       description: Text("Its scope, requirements and handoff appear here."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(WorkspacePanel())
    }

    private var sidebar: some View {
        Group {
        #if os(macOS)
        List(selection: $destination) {
            Section("Engineering") {
                Label("All outcomes", systemImage: "rectangle.stack").tag(WorkspaceDestination.all)
                HStack {
                    Label("Needs input", systemImage: "bubble.left")
                    Spacer()
                    if !pendingIDs.isEmpty { Text(pendingIDs.count, format: .number).foregroundStyle(.secondary) }
                }.tag(WorkspaceDestination.needsInput)
            }
            Section("Outcomes") {
                ForEach(store.workspace.outcomes.reversed()) { item in
                    Label(item.text, systemImage: "doc.text").lineLimit(2).tag(WorkspaceDestination.outcome(item.id))
                }
                Button("New outcome", systemImage: "square.and.pencil") { sheet = .newOutcome }
                    .disabled(!store.isLoaded)
            }
            Section("Team") { developerSidebarButton }
        }
        .listStyle(.sidebar).scrollContentBackground(.hidden)
        #else
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
                Button("New outcome", systemImage: "square.and.pencil") { sheet = .newOutcome }
                    .frame(minHeight: 44).padding(.horizontal, 14).disabled(!store.isLoaded)
                if store.workspace.outcomes.isEmpty {
                    Text("Give the team an outcome or import tickets from Connections.")
                        .font(StudioTypography.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 14).padding(.bottom, 8)
                }
                Divider().padding(.horizontal, 12).padding(.vertical, 13)
                sidebarHeading("Team")
                developerSidebarButton.padding(.horizontal, 14).padding(.vertical, 12)
            }.padding(.horizontal, 8).padding(.top, 16)
        }
        #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(WorkspacePanel())
        .navigationTitle("Engineering")
    }

    private var developerSidebarButton: some View {
        Button { sheet = .team } label: {
            RuntimeFeatureAPI.availability(runtime: runtime)
        }.buttonStyle(.plain)
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
                Text(title).font(StudioTypography.body).lineLimit(2)
                Spacer(minLength: 0)
                if let count {
                    Text(count, format: .number).font(StudioTypography.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 4).background(.thinMaterial, in: .capsule)
                }
            }
            .padding(.horizontal, 14).frame(minHeight: 44).contentShape(.rect)
            .background {
                if destination == value {
                    RoundedRectangle(cornerRadius: StudioRadius.control).fill(StudioStyle.accent)
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(destination == value ? Color.white : Color.primary)
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
                        Text(runtime.outcomeStatus(item))
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }.buttonStyle(.plain)
            }
            // Keep pre-thread messages available without attributing them to an unrelated outcome.
            if !visibleLegacyMessages.isEmpty {
                Section("Earlier workspace conversation") {
                    ForEach(visibleLegacyMessages) { message in MessageRow(message: message) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .overlay {
            if filteredOutcomes.isEmpty && visibleLegacyMessages.isEmpty {
                ContentUnavailableView {
                    Label(search.isEmpty ? "No outcomes here" : "No matching outcomes", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Start with a shared outcome for your engineering team.")
                } actions: {
                    Button { sheet = .newOutcome } label: {
                        Label("New Outcome", systemImage: "plus").frame(minHeight: 36)
                    }
                    .buttonStyle(.glassProminent).controlSize(.large).disabled(!store.isLoaded)
                }
            }
        }
    }
}
