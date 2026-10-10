import EngineeringCore
import SwiftUI

struct EngineeringRoomView: View {
    let store: StudioStore
    let outcome: Outcome
    @Binding var selectedTaskID: String?
    @State private var draft = ""
    @State private var showsTasks = false

    private var messages: [RoomMessage] { store.workspace.messages.filter { $0.outcomeID == outcome.id } }
    private var questions: [QuestionBatch] {
        store.workspace.questions.filter { $0.outcomeID == outcome.id && !$0.isComplete }
    }
    var body: some View {
        VStack(spacing: 0) {
            Picker("Outcome view", selection: $showsTasks) {
                Text("Conversation").tag(false)
                Text("Tasks").tag(true)
            }
            .pickerStyle(.segmented).frame(maxWidth: 330).padding(.vertical, 12)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        if !showsTasks {
                            Text(outcome.createdAt, style: .date)
                                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                            if messages.isEmpty {
                                // Legacy workspaces preserve the outcome without guessing message ownership.
                                Text(outcome.text).textSelection(.enabled)
                            }
                            ForEach(messages) { message in MessageRow(message: message).id(message.id) }
                        }
                        if let plan = outcome.plan {
                            TaskSummaryView(tasks: plan.tasks, selectedTaskID: $selectedTaskID)
                        }
                        ForEach(questions) { batch in
                            QuestionBatchView(batch: batch) { store.answer(batch, answers: $0) }
                        }
                        OutcomeSummary(outcome: outcome, store: store)
                        HStack {
                            Label(store.saveState, systemImage: "internaldrive")
                            if store.saveState == "Changes not saved" {
                                Button("Retry") { store.retrySave() }
                            }
                        }.font(.caption).foregroundStyle(.secondary)
                        Color.clear.frame(height: 1).id("end")
                    }.padding(20)
                }
                .onChange(of: messages.count) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassEffectContainer {
                HStack(alignment: .bottom, spacing: 12) {
                    TextField("Direct the team…", text: $draft, axis: .vertical)
                        .lineLimit(1...5).textFieldStyle(.plain).padding(.vertical, 8)
                        .accessibilityLabel("Message for this outcome")
                    Button("Send", systemImage: "arrow.up") {
                        if store.send(draft, to: outcome.id) { draft = "" }
                    }
                    .buttonStyle(.glassProminent).tint(.blue)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.isLoaded)
                    .keyboardShortcut(.return, modifiers: .command)
                }
                .padding(12).glassEffect(.regular, in: .rect(cornerRadius: 24))
            }
            Text("Messages are saved locally and used when you prepare a plan.")
                .font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 8)
        }.padding(12)
    }
}

struct MessageRow: View {
    let message: RoomMessage
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: message.author == .user ? "person.crop.circle.fill" : "sparkles")
                .font(.title3).frame(width: 36, height: 36)
                .background(.thinMaterial, in: .circle).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 10) {
                    Text(message.author == .user ? "You" : "Coordinator · AI").font(.headline)
                    Text(message.createdAt, style: .time).font(.caption).foregroundStyle(.secondary)
                }
                Text(message.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.accessibilityElement(children: .combine)
    }
}

struct TaskSummaryView: View {
    let tasks: [WorkTask]
    @Binding var selectedTaskID: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Task").frame(maxWidth: .infinity, alignment: .leading)
                Text("Status")
            }.font(.caption).foregroundStyle(.secondary).padding(12)
            ForEach(tasks) { task in
                Divider()
                Button {
                    selectedTaskID = task.id
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.title).font(.body.weight(.medium))
                            Text(task.owner.title).font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Label("Planned", systemImage: "circle.dashed").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(12).contentShape(.rect)
                    .background(selectedTaskID == task.id ? Color.blue.opacity(0.24) : .clear)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedTaskID == task.id ? [.isSelected] : [])
                .accessibilityHint("Show scope and handoff in task details")
            }
        }
        .background(.thinMaterial, in: .rect(cornerRadius: 16))
        .clipShape(.rect(cornerRadius: 16))
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
                    .buttonStyle(.glass).tint(.orange)
            } else if waiting {
                Label("Waiting for your answers", systemImage: "bubble.left.and.text.bubble.right")
            } else if store.usesOnDeviceModel {
                Button(outcome.plan == nil ? "Prepare Plan" : "Update Plan", systemImage: "play.fill") { store.plan(outcome) }
                    .buttonStyle(.glassProminent).tint(.green).disabled(store.isPlanning)
            } else if outcome.plan == nil {
                Text("Enable Apple Intelligence in Settings to prepare assignments on this device.")
                    .foregroundStyle(.secondary)
            }
            Label(outcome.plan == nil ? "Developer execution is not connected." : "Plan saved · Tasks have not been dispatched.",
                  systemImage: "network.slash")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct TaskDetailView: View {
    let task: WorkTask
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: task.owner.symbol).font(.title2)
                        .frame(width: 44, height: 44).background(.thinMaterial, in: .rect(cornerRadius: 12))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(task.title).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                        Text("Planned · \(task.owner.title)").font(.callout).foregroundStyle(.secondary)
                    }
                }
                Divider()
                detailSection("Scope", symbol: "doc.text") {
                    ForEach(task.paths, id: \.self) { Text($0).font(.callout.monospaced()).textSelection(.enabled) }
                }
                Divider()
                detailSection("Acceptance criteria", symbol: "checklist") {
                    ForEach(task.acceptance, id: \.self) { criterion in
                        Label(criterion, systemImage: "circle").fixedSize(horizontal: false, vertical: true)
                    }
                }
                Divider()
                detailSection("Handoff", symbol: "arrow.triangle.branch") {
                    Text(task.handoff).textSelection(.enabled)
                    if !task.dependencies.isEmpty {
                        Text("Depends on: \(task.dependencies.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                detailSection("Verification", symbol: "checkmark.seal") {
                    Text("Tests have not run").font(.headline)
                    Text("No test runner or pull request is connected to this task.").foregroundStyle(.secondary)
                }
                ViewThatFits(in: .horizontal) {
                    HStack { testButton; pullRequestButton }
                    VStack(alignment: .leading) { testButton; pullRequestButton }
                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Task details")
    }
    private var testButton: some View {
        Button("Run Tests", systemImage: "play.fill") { }
            .buttonStyle(.glassProminent).tint(.green).disabled(true)
            .help("Connect a test runner to run and verify tests")
    }
    private var pullRequestButton: some View {
        Button("Open PR", systemImage: "arrow.up.right") { }
            .buttonStyle(.glass).disabled(true).help("No pull request exists for this task")
    }
    private func detailSection<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.headline)
            content()
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
                                Text(option).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }.padding(.vertical, 6).frame(minHeight: 44)
                        }.buttonStyle(.bordered)
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
