import EngineeringCore
import SwiftUI

struct EngineeringRoomView: View {
    let store: StudioStore
    let connections: ServiceConnections
    let runtime: DeveloperRuntimeConnection
    let outcome: Outcome
    let selectedTaskID: String?
    let inspectTask: (String) -> Void
    let openConnections: () -> Void
    private let initialDraft: String
    @State private var showsTasks = false

    /// One-time draft seed used only by self-contained previews.
    init(store: StudioStore, connections: ServiceConnections, runtime: DeveloperRuntimeConnection = DeveloperRuntimeConnection(), outcome: Outcome, selectedTaskID: String?, initialDraft: String = "",
         openConnections: @escaping () -> Void, inspectTask: @escaping (String) -> Void) {
        self.store = store
        self.connections = connections
        self.runtime = runtime
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
                            TaskSummaryView(tasks: plan.tasks, selectedTaskID: selectedTaskID, records: runtime.state.records.filter { $0.key.outcomeID == outcome.id }, inspectTask: inspectTask)
                        }
                        if let selectedTask, !showsTasks {
                            ProposedHandoffView(task: selectedTask, record: runtime.record(outcomeID: outcome.id, taskID: selectedTask.id))
                        }
                        ForEach(questions) { batch in
                            QuestionBatchView(batch: batch) { store.answer(batch, answers: $0) }
                        }
                        OutcomeSummary(outcome: outcome, store: store, runtime: runtime)
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
    let record: ExecutionRecord?
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            SymbolBadge(symbol: task.owner.symbol)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(task.owner.displayName).fontWeight(.semibold)
                    Text(record?.task == task && record?.status == .completed ? "· Result" : "· Handoff").foregroundStyle(.secondary)
                }.font(StudioTypography.secondary)
                Text(task.handoff).font(StudioTypography.body).lineSpacing(4)
                HStack(spacing: 12) {
                    SymbolBadge(symbol: "doc.text", size: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title)
                        Text(record?.task == task ? record!.status.rawValue.capitalized : "Planned · Not dispatched").font(StudioTypography.secondary).foregroundStyle(.secondary)
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
    let runtime: DeveloperRuntimeConnection
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
            if outcome.plan != nil {
                HStack {
                    Label(runtime.outcomeStatus(outcome), systemImage: runtime.state.connected ? "terminal" : "network.slash")
                        .font(StudioTypography.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if !runtime.hasDelivered(outcome) {
                        Button("Run Team", systemImage: "play.fill") { Task { await runtime.run(outcome, store: store) } }
                            .buttonStyle(.glassProminent).tint(.green)
                            .disabled(!runtime.state.connected || runtime.isDispatching || store.isPlanning)
                    }
                }
            }
            if let error = runtime.error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            ForEach(runtime.state.records.filter { $0.key.outcomeID == outcome.id && !$0.summary.isEmpty }) { record in
                VStack(alignment: .leading, spacing: 6) {
                    Label(record.task.title, systemImage: record.task.owner.symbol).font(.headline)
                    Text(record.summary).textSelection(.enabled)
                    if let blocker = record.blocker { Label(blocker, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                }.padding(.vertical, 8)
            }
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
