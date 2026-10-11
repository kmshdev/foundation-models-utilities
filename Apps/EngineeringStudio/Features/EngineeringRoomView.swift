import EngineeringCore
import SwiftUI

struct EngineeringRoomView: View {
    let store: StudioStore
    let connections: ServiceConnections
    let outcome: Outcome
    let selectedTaskID: String?
    let inspectTask: (String) -> Void
    let openConnections: () -> Void
    private let initialDraft: String
    @State private var showsTasks = false

    /// One-time draft seed used only by self-contained previews.
    init(store: StudioStore, connections: ServiceConnections, outcome: Outcome, selectedTaskID: String?, initialDraft: String = "",
         openConnections: @escaping () -> Void, inspectTask: @escaping (String) -> Void) {
        self.store = store
        self.connections = connections
        self.outcome = outcome
        self.selectedTaskID = selectedTaskID
        self.inspectTask = inspectTask
        self.openConnections = openConnections
        self.initialDraft = initialDraft
    }

    private var messages: [RoomMessage] { store.workspace.messages.filter { $0.outcomeID == outcome.id } }
    private var questions: [QuestionBatch] { store.workspace.questions.filter { $0.outcomeID == outcome.id && !$0.isComplete } }
    private var selectedTask: WorkTask? { outcome.plan?.tasks.first { $0.id == selectedTaskID } }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Outcome view", selection: $showsTasks) {
                Text("Conversation").tag(false)
                Text("Tasks").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().controlSize(.large)
            .frame(maxWidth: 330).padding(.bottom, StudioSpacing.section)
            Divider()
            if let source = outcome.source {
                Link("Open source issue in Linear", destination: source.url)
                    .font(.caption).padding(.top, 8)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        if !showsTasks {
                            Text(outcome.createdAt, style: .date)
                                .font(StudioTypography.secondary).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                            if messages.isEmpty { Text(outcome.text).textSelection(.enabled) }
                            ForEach(messages) { message in
                                MessageRow(message: message).id(message.id)
                            }
                        }
                        if let plan = outcome.plan {
                            TaskSummaryView(tasks: plan.tasks, selectedTaskID: selectedTaskID, inspectTask: inspectTask)
                        }
                        if let selectedTask, !showsTasks {
                            ProposedHandoffView(task: selectedTask)
                        }
                        ForEach(questions) { batch in
                            QuestionBatchView(batch: batch) { store.answer(batch, answers: $0) }
                        }
                        OutcomeSummary(outcome: outcome, store: store)
                        if outcome.plan != nil {
                            PlanPublishingControls(outcome: outcome, store: store, connections: connections,
                                                   openConnections: openConnections)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }.padding(.horizontal, 10).padding(.top, 16).padding(.bottom, 12)
                }
                .onChange(of: messages.count) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OutcomeComposer(store: store, outcomeID: outcome.id,
                            draft: store.draft(for: outcome.id, initialText: initialDraft))
                .padding(.top, StudioSpacing.standard)
        }
    }

}

struct MessageRow: View {
    let message: RoomMessage
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            SymbolBadge(symbol: message.author == .user ? "person.fill" : "sparkle", size: 48)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 10) {
                    Text(message.author == .user ? "You" : "Coordinator").font(StudioTypography.label)
                    if message.author != .user { Text("· AI").foregroundStyle(.secondary) }
                    Text(message.createdAt, style: .time).foregroundStyle(.secondary)
                }.font(StudioTypography.secondary)
                Text(message.text).font(StudioTypography.body).lineSpacing(4)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }.padding(.top, 4)
            Spacer(minLength: 0)
        }.accessibilityElement(children: .combine)
    }
}

private struct ProposedHandoffView: View {
    let task: WorkTask
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            SymbolBadge(symbol: task.owner.symbol)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(task.owner.displayName).fontWeight(.semibold)
                    Text("· Proposed handoff").foregroundStyle(.secondary)
                }.font(StudioTypography.secondary)
                Text(task.handoff).font(StudioTypography.body).lineSpacing(4)
                HStack(spacing: 12) {
                    SymbolBadge(symbol: "doc.text", size: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title)
                        Text("Planned · Not dispatched").font(StudioTypography.secondary).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.turn.down.right").foregroundStyle(.secondary)
                }
                .padding(12).background(.thinMaterial, in: .rect(cornerRadius: 13))
                .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(.primary.opacity(0.10)) }
            }.padding(.top, 5)
        }
    }
}

struct OutcomeSummary: View {
    let outcome: Outcome
    let store: StudioStore
    private var waiting: Bool { store.workspace.questions.contains { $0.outcomeID == outcome.id && !$0.isComplete } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.planningOutcomeID == outcome.id {
                HStack { ProgressView().controlSize(.small); Text("Preparing assignments…") }
                Button("Cancel Planning", systemImage: "stop.fill") { store.cancelPlanning() }
                    .buttonStyle(.glass).tint(.orange).controlSize(.large)
            } else if waiting {
                Label("Waiting for your answers", systemImage: "bubble.left.and.text.bubble.right")
            } else if store.isQueuedForPlanning(outcome.id) {
                Label("Planning queued", systemImage: "clock")
            } else if store.isPlanningEnabled {
                Button(outcome.plan == nil ? "Prepare Plan" : "Update Plan", systemImage: "play.fill") { store.plan(outcome) }
                    .buttonStyle(.glassProminent).tint(.green).controlSize(.large).disabled(store.isPlanning)
            } else if outcome.plan == nil {
                Text("Choose a planning model in Settings to prepare assignments.").foregroundStyle(.secondary)
            }
            Label(outcome.plan == nil ? "Developer execution is not connected." : "Plan saved · Tasks have not been dispatched.",
                  systemImage: "network.slash")
                .font(StudioTypography.caption).foregroundStyle(.secondary)
        }
    }
}

struct TaskDetailView: View {
    let task: WorkTask
    var issueBinding: TaskIssueBinding? = nil
    @State private var showsRequirements = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(spacing: 16) {
                    SymbolBadge(symbol: "doc.text", size: 62)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(task.title).font(StudioTypography.title).accessibilityAddTraits(.isHeader)
                        Text("Planned · \(task.owner.displayName)").font(StudioTypography.body).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                Divider().opacity(0.6)
                if let binding = issueBinding, let url = binding.webURL {
                    Link(binding.identifier ?? "Open Linear issue", destination: url)
                    if binding.publishedTask != task {
                        Text("This task has changed since its last publication.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                detailSection("Scope", symbol: "doc.text") {
                    ForEach(task.paths, id: \.self) { path in
                        Text(path)
                            .font(StudioTypography.body).foregroundStyle(.secondary).lineSpacing(6)
                            .textSelection(.enabled).help(path).accessibilityLabel(path)
                    }
                }
                Divider().opacity(0.6)
                detailSection("Handoff", symbol: "arrow.triangle.branch") {
                    Text(task.handoff.components(separatedBy: ". ").first ?? task.handoff)
                        .font(StudioTypography.body).lineSpacing(5).textSelection(.enabled)
                    Text("Not dispatched").font(StudioTypography.secondary).foregroundStyle(.secondary)
                    if !task.dependencies.isEmpty {
                        Text("Depends on: \(task.dependencies.joined(separator: ", "))")
                            .font(StudioTypography.secondary).foregroundStyle(.secondary)
                    }
                }
                Divider().opacity(0.6)
                detailSection("Verification", symbol: "checkmark.seal") {
                    Text("Tests have not run").font(StudioTypography.body)
                    Text("Connect a runner to verify results.").font(StudioTypography.secondary).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Button {} label: {
                        Label("Run Tests", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 34)
                    }.buttonStyle(.glassProminent).tint(.green).disabled(true)
                        .help("Connect a test runner to run and verify tests")
                    Button {} label: {
                        Label("Open PR", systemImage: "arrow.up.right").frame(maxWidth: .infinity, minHeight: 34)
                    }.buttonStyle(.glass).disabled(true).help("No pull request exists for this task")
                }.font(StudioTypography.label).controlSize(.large).buttonBorderShape(.roundedRectangle(radius: 13))
                DisclosureGroup("Acceptance criteria", isExpanded: $showsRequirements) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(task.acceptance, id: \.self) { criterion in
                            Label(criterion, systemImage: "circle").fixedSize(horizontal: false, vertical: true)
                        }
                    }.font(StudioTypography.body).padding(.top, 12)
                }.font(StudioTypography.secondary).foregroundStyle(.secondary)
                DisclosureGroup("Handoff context") {
                    Text(task.handoff).font(StudioTypography.body).lineSpacing(4).textSelection(.enabled).padding(.top, 10)
                }.font(StudioTypography.secondary).foregroundStyle(.secondary)
            }.padding(24).padding(.top, 8).frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Task details")
    }

    private func detailSection<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 16) {
            SymbolBadge(symbol: symbol, size: 36)
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(StudioTypography.heading).accessibilityAddTraits(.isHeader)
                content()
            }.padding(.top, 3)
        }
    }
}
struct QuestionBatchView: View {
    let batch: QuestionBatch
    let submit: ([UUID: String]) -> Void
    @State private var answers: [UUID: String] = [:]
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionEyebrow(text: "Your input / Answer together")
            ForEach(batch.questions) { question in
                VStack(alignment: .leading, spacing: 10) {
                    Text(question.prompt).font(.headline)
                    ForEach(question.options, id: \.self) { option in
                        Button {
                            answers[question.id] = option
                        } label: {
                            HStack {
                                Image(systemName: (answers[question.id] ?? question.answer) == option ? "largecircle.fill.circle" : "circle")
                                    .accessibilityHidden(true)
                                Text(option).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }.padding(.vertical, 6).frame(minHeight: 44)
                        }.buttonStyle(.bordered)
                            .accessibilityLabel(option)
                            .accessibilityAddTraits((answers[question.id] ?? question.answer) == option ? [.isSelected] : [])
                    }
                    TextField("Your answer", text: Binding(
                        get: { answers[question.id] ?? question.answer ?? "" },
                        set: { answers[question.id] = $0 }
                    ), axis: .vertical).textFieldStyle(.roundedBorder).accessibilityLabel(question.prompt)
                }
            }
            Button("Save answers") { submit(answers) }.buttonStyle(.borderedProminent)
                .disabled(answers.isEmpty)
            Text("Partial answers are saved. Planning waits until this batch is complete.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 16).overlay(alignment: .top) { Divider() }
    }
}
