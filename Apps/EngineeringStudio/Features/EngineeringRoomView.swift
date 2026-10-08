import EngineeringCore
import SwiftUI

struct EngineeringRoomView: View {
    @Bindable var store: StudioStore
    @State private var draft = ""
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    StudioHeading(eyebrow: "Workspace / 01", title: "A place for the work.",
                                  detail: "Give your team an outcome. Keep its requirements, questions and handoffs together.")
                    StatusStrip()
                    if store.workspace.messages.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            SectionEyebrow(text: "Start with an outcome")
                            Text("What should we build?").font(.title2)
                            Text("Outcomes are saved on this device. Planning can use Apple Intelligence when you enable it in Settings. Developer execution is not connected yet.")
                                .foregroundStyle(.secondary)
                            Button("Add the coordinator outcome", systemImage: "plus") {
                                _ = store.submit("Build the engineering coordinator and team workflow as a native SwiftUI app for iOS 27 and macOS 27.")
                            }
                            .buttonStyle(.bordered).disabled(!store.isLoaded)
                        }.padding(.vertical, 22)
                    }
                    ForEach(store.workspace.messages) { message in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                SectionEyebrow(text: message.author == .user ? "You / Outcome" : "Coordinator")
                                Spacer()
                                Text(message.createdAt, style: .time).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                            Text(message.text).textSelection(.enabled)
                        }
                        .padding(.vertical, 10).id(message.id)
                        .overlay(alignment: .bottom) { Divider() }
                    }
                    ForEach(store.workspace.questions.filter { !$0.isComplete }) { batch in
                        QuestionBatchView(batch: batch) { store.answer(batch, answers: $0) }
                    }
                    if let outcome = store.workspace.outcomes.last {
                        OutcomeSummary(outcome: outcome, store: store)
                    }
                    Text(store.saveState).font(.caption).foregroundStyle(.secondary)
                        .accessibilityLabel("Workspace status: \(store.saveState)")
                    if store.saveState == "Changes not saved" { Button("Retry saving") { store.retrySave() } }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 24).padding(.bottom, 20)
                .frame(maxWidth: 840).frame(maxWidth: .infinity)
            }
            .onChange(of: store.workspace.messages.count) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
        }
        .background(StudioStyle.paper)
        .navigationTitle("Engineering")
        .safeAreaInset(edge: .bottom) { composer }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("Describe an outcome…", text: $draft, axis: .vertical)
                .lineLimit(1...5).textFieldStyle(.plain)
                .accessibilityLabel("Outcome for the engineering team")
                .padding(.vertical, 10)
            Button("Add outcome", systemImage: "arrow.up") {
                if store.submit(draft) { draft = "" }
            }
            .labelStyle(.iconOnly).buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.isLoaded)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(12).glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(.horizontal, 18).padding(.vertical, 10)
        .frame(maxWidth: 860).frame(maxWidth: .infinity)
    }
}

struct OutcomeSummary: View {
    let outcome: Outcome
    @Bindable var store: StudioStore
    private var waiting: Bool { store.workspace.questions.contains { $0.outcomeID == outcome.id && !$0.isComplete } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionEyebrow(text: outcome.plan == nil ? "Next / Assignment plan" : "Assignment plan")
            if let plan = outcome.plan {
                Text("\(plan.tasks.count) scoped tasks").font(.title3)
                NavigationLink("View assignments and handoffs") { PlanDetailView(plan: plan) }
                Text("Plan saved. No tasks have been dispatched.").font(.caption).foregroundStyle(.secondary)
            } else if waiting {
                Label("Waiting for your answers above", systemImage: "bubble.left.and.text.bubble.right")
            } else if store.isPlanning {
                HStack { ProgressView(); Text("Preparing assignments…"); Spacer(); Button("Cancel") { store.cancelPlanning() } }
            } else if store.usesOnDeviceModel {
                Button("Prepare assignment plan", systemImage: "sparkles") { store.plan(outcome) }.buttonStyle(.borderedProminent)
            } else {
                Text("Enable on-device planning in Settings to prepare assignments. Your requested ChatGPT subscription connection is not implemented yet.")
                    .foregroundStyle(.secondary)
            }
        }.padding(.vertical, 12)
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
                    ForEach(Array(question.options.enumerated()), id: \.offset) { _, option in
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
