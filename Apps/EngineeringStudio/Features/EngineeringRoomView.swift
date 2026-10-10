import EngineeringCore
import SwiftUI

struct EngineeringRoomView: View {
    let store: StudioStore
    let outcome: Outcome
    @Binding var selectedTaskID: String?
    @State private var draft: String
    @State private var showsTasks = false

    /// One-time draft seed used only by self-contained previews.
    init(store: StudioStore, outcome: Outcome, selectedTaskID: Binding<String?>, initialDraft: String = "") {
        self.store = store
        self.outcome = outcome
        _selectedTaskID = selectedTaskID
        _draft = State(initialValue: initialDraft)
    }

    private var messages: [RoomMessage] { store.workspace.messages.filter { $0.outcomeID == outcome.id } }
    private var questions: [QuestionBatch] { store.workspace.questions.filter { $0.outcomeID == outcome.id && !$0.isComplete } }
    private var selectedTask: WorkTask? { outcome.plan?.tasks.first { $0.id == selectedTaskID } }

    var body: some View {
        VStack(spacing: 0) {
            conversationPicker.padding(.bottom, 18)
            Divider().overlay(.white.opacity(0.04))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        if !showsTasks {
                            Text(outcome.createdAt, style: .date)
                                .font(.system(size: 14)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                            if messages.isEmpty { Text(outcome.text).textSelection(.enabled) }
                            ForEach(messages) { message in
                                MessageRow(message: message).id(message.id)
                            }
                        }
                        if let plan = outcome.plan {
                            TaskSummaryView(tasks: plan.tasks, selectedTaskID: $selectedTaskID)
                        }
                        if let selectedTask, !showsTasks {
                            ProposedHandoffView(task: selectedTask)
                        }
                        ForEach(questions) { batch in
                            QuestionBatchView(batch: batch) { store.answer(batch, answers: $0) }
                        }
                        OutcomeSummary(outcome: outcome, store: store)
                        Color.clear.frame(height: 1).id("end")
                    }.padding(.horizontal, 10).padding(.top, 16).padding(.bottom, 12)
                }
                .onChange(of: messages.count) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            }
            composer.padding(.top, 10)
        }
    }

    private var conversationPicker: some View {
        HStack(spacing: 4) {
            segment("Conversation", selected: !showsTasks) { showsTasks = false }
            segment("Tasks", selected: showsTasks) { showsTasks = true }
        }
        .padding(4).frame(width: 290)
        .background(.ultraThinMaterial, in: .capsule)
        .overlay { Capsule().strokeBorder(.white.opacity(0.12)) }
        .accessibilityElement(children: .contain).accessibilityLabel("Outcome view")
    }

    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 15, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? .primary : .secondary)
                .frame(maxWidth: .infinity).frame(height: 32)
                .background {
                    if selected {
                        Capsule().fill(.thinMaterial)
                            .overlay { Capsule().strokeBorder(.white.opacity(0.22)) }
                    }
                }
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var composer: some View {
        VStack(spacing: 7) {
            HStack(alignment: .center, spacing: 10) {
                Button {} label: {
                    Image(systemName: "paperclip").font(.system(size: 22)).frame(width: 42, height: 46)
                }
                .buttonStyle(.glass).buttonBorderShape(.circle).disabled(true)
                .accessibilityLabel("Attach a file").help("Attachments are not supported yet")
                TextField("Direct the team…", text: $draft, axis: .vertical)
                    .font(.system(size: 16)).lineLimit(1...5).textFieldStyle(.plain)
                    .padding(.horizontal, 18).padding(.vertical, 16)
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: 20))
                    .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.15)) }
                    .accessibilityLabel("Message for this outcome")
                Button {
                    if store.send(draft, to: outcome.id) { draft = "" }
                } label: {
                    Label("Send", systemImage: "arrow.up").font(.system(size: 16, weight: .medium))
                        .frame(minWidth: 88, minHeight: 38)
                }
                .buttonStyle(.glassProminent).tint(.blue).controlSize(.large)
                .buttonBorderShape(.roundedRectangle(radius: 15))
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.isLoaded)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(12).glassEffect(.regular, in: .rect(cornerRadius: 26))
            HStack(spacing: 6) {
                Image(systemName: "internaldrive")
                Text(store.saveState)
                Spacer()
                if store.saveState == "Changes not saved" { Button("Retry") { store.retrySave() } }
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 10)
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
                    Text(message.author == .user ? "You" : "Coordinator").font(.system(size: 14, weight: .semibold))
                    if message.author != .user { Text("· AI").foregroundStyle(.secondary) }
                    Text(message.createdAt, style: .time).foregroundStyle(.secondary)
                }.font(.system(size: 14))
                Text(message.text).font(.system(size: 16)).lineSpacing(4)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }.padding(.top, 4)
            Spacer(minLength: 0)
        }.accessibilityElement(children: .combine)
    }
}

struct TaskSummaryView: View {
    let tasks: [WorkTask]
    @Binding var selectedTaskID: String?
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Task").frame(maxWidth: .infinity, alignment: .leading)
                Text("Owner").frame(width: 130, alignment: .leading)
                Text("Status").frame(width: 108, alignment: .leading)
            }.font(.system(size: 14)).foregroundStyle(.secondary)
                .padding(.horizontal, 22).frame(height: 40)
                .background(.white.opacity(0.04))
            ForEach(tasks) { task in
                Divider().opacity(0.55)
                Button { selectedTaskID = task.id } label: {
                    HStack(spacing: 12) {
                        Text(task.title).frame(maxWidth: .infinity, alignment: .leading)
                        Text(task.owner.displayName).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
                        Label("Planned", systemImage: "circle.dashed").foregroundStyle(.secondary)
                            .frame(width: 108, alignment: .leading)
                    }
                    .font(.system(size: 15)).padding(.horizontal, 22).frame(minHeight: 43)
                    .contentShape(.rect)
                    .background {
                        if selectedTaskID == task.id {
                            RoundedRectangle(cornerRadius: 10).fill(.blue.opacity(0.35).gradient)
                                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.blue.opacity(0.9)) }
                        }
                    }
                }.buttonStyle(.plain)
                    .accessibilityLabel("\(task.title), \(task.owner.title), planned")
                    .accessibilityAddTraits(selectedTaskID == task.id ? [.isSelected] : [])
                    .accessibilityHint("Show scope and handoff in task details")
            }
        }
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
        .clipShape(.rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.13)) }
    }
}

private struct ProposedHandoffView: View {
    let task: WorkTask
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            SymbolBadge(symbol: task.owner.symbol, tint: .blue)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(task.owner.displayName).fontWeight(.semibold)
                    Text("· Proposed handoff").foregroundStyle(.secondary)
                }.font(.system(size: 14))
                Text(task.handoff).font(.system(size: 16)).lineSpacing(4)
                HStack(spacing: 12) {
                    SymbolBadge(symbol: "doc.text", size: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title)
                        Text("Planned · Not dispatched").font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.turn.down.right").foregroundStyle(.secondary)
                }
                .padding(12).background(.thinMaterial, in: .rect(cornerRadius: 13))
                .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(.white.opacity(0.12)) }
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
            } else if store.usesOnDeviceModel {
                Button(outcome.plan == nil ? "Prepare Plan" : "Update Plan", systemImage: "play.fill") { store.plan(outcome) }
                    .buttonStyle(.glassProminent).tint(.green).controlSize(.large).disabled(store.isPlanning)
            } else if outcome.plan == nil {
                Text("Enable Apple Intelligence in Settings to prepare assignments on this device.").foregroundStyle(.secondary)
            }
            Label(outcome.plan == nil ? "Developer execution is not connected." : "Plan saved · Tasks have not been dispatched.",
                  systemImage: "network.slash")
                .font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }
}

struct TaskDetailView: View {
    let task: WorkTask
    @State private var showsRequirements = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(spacing: 16) {
                    SymbolBadge(symbol: "doc.text", size: 62)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(task.title).font(.system(size: 22, weight: .semibold)).accessibilityAddTraits(.isHeader)
                        Text("Planned · \(task.owner.displayName)").font(.system(size: 16)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                Divider().opacity(0.6)
                detailSection("Scope", symbol: "doc.text") {
                    ForEach(task.paths, id: \.self) { path in
                        Text(path.split(separator: "/").suffix(2).joined(separator: "/\n"))
                            .font(.system(size: 16)).foregroundStyle(.secondary).lineSpacing(6)
                            .textSelection(.enabled).help(path).accessibilityLabel(path)
                    }
                }
                Divider().opacity(0.6)
                detailSection("Handoff", symbol: "arrow.triangle.branch") {
                    Text(task.handoff).font(.system(size: 16)).lineSpacing(5).textSelection(.enabled)
                    Text("Not dispatched").font(.system(size: 14)).foregroundStyle(.secondary)
                    if !task.dependencies.isEmpty {
                        Text("Depends on: \(task.dependencies.joined(separator: ", "))")
                            .font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                }
                Divider().opacity(0.6)
                detailSection("Verification", symbol: "checkmark.seal") {
                    Text("Tests have not run").font(.system(size: 16))
                    Text("Connect a runner to verify results.").font(.system(size: 14)).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Button {} label: {
                        Label("Run Tests", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 34)
                    }.buttonStyle(.glassProminent).tint(.green).disabled(true)
                        .help("Connect a test runner to run and verify tests")
                    Button {} label: {
                        Label("Open PR", systemImage: "arrow.up.right").frame(maxWidth: .infinity, minHeight: 34)
                    }.buttonStyle(.glass).disabled(true).help("No pull request exists for this task")
                }.font(.system(size: 15, weight: .medium)).controlSize(.large).buttonBorderShape(.roundedRectangle(radius: 13))
                DisclosureGroup("Acceptance criteria", isExpanded: $showsRequirements) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(task.acceptance, id: \.self) { criterion in
                            Label(criterion, systemImage: "circle").fixedSize(horizontal: false, vertical: true)
                        }
                    }.font(.system(size: 15)).padding(.top, 12)
                }.font(.system(size: 14)).foregroundStyle(.secondary)
            }.padding(24).padding(.top, 8).frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Task details")
    }

    private func detailSection<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 16) {
            SymbolBadge(symbol: symbol, size: 36)
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.system(size: 16, weight: .semibold)).accessibilityAddTraits(.isHeader)
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
