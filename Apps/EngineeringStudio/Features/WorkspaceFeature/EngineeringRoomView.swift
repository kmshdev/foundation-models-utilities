import IntegrationFeature
import StudioWorkflows
import StudioServices
import StudioUI
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
    let openSettings: () -> Void
    let openRuntime: () -> Void
    private let initialDraft: String
    @State private var showsTasks = false
    @State private var followsLatest = true
    @State private var isNearLatest = true
    @State private var isUserScrolling = false
    @State private var unreadMessages = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One-time draft seed used only by self-contained previews.
    init(store: StudioStore, connections: ServiceConnections, runtime: DeveloperRuntimeConnection = DeveloperRuntimeConnection(), outcome: Outcome, selectedTaskID: String?, initialDraft: String = "",
         openConnections: @escaping () -> Void, openSettings: @escaping () -> Void,
         openRuntime: @escaping () -> Void, inspectTask: @escaping (String) -> Void) {
        self.store = store
        self.connections = connections
        self.runtime = runtime
        self.outcome = outcome
        self.selectedTaskID = selectedTaskID
        self.inspectTask = inspectTask
        self.openConnections = openConnections
        self.openSettings = openSettings
        self.openRuntime = openRuntime
        self.initialDraft = initialDraft
    }

    private var messages: [RoomMessage] { store.workspace.messages.filter { $0.outcomeID == outcome.id } }
    private var questions: [QuestionBatch] { store.workspace.questions.filter { $0.outcomeID == outcome.id && !$0.isComplete } }

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
                            OutcomeAssignmentsView(outcomeID: outcome.id, tasks: plan.tasks, selectedTaskID: selectedTaskID,
                                                   showsHandoff: !showsTasks, runtime: runtime, inspectTask: inspectTask)
                        }
                        ForEach(questions) { batch in
                            QuestionBatchView(batch: batch) { store.answer(batch, answers: $0) }
                        }
                        OutcomePlanningControls(outcome: outcome, store: store, openSettings: openSettings)
                        if outcome.plan != nil {
                            OutcomeExecutionControls(outcome: outcome, store: store, runtime: runtime, openRuntime: openRuntime)
                            ExecutionResultsView(outcomeID: outcome.id, tasks: outcome.plan?.tasks ?? [], runtime: runtime, inspect: inspectTask)
                            IntegrationFeatureAPI.publishing(outcome: outcome, store: store, connections: connections,
                                                   openConnections: openConnections)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, 10).padding(.top, 16).padding(.bottom, 12)
                    .frame(maxWidth: 760).frame(maxWidth: .infinity)
                }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.visibleRect.maxY >= geometry.contentSize.height - 80
                } action: { _, nearLatest in
                    isNearLatest = nearLatest
                    if isUserScrolling { followsLatest = nearLatest }
                    if nearLatest { unreadMessages = 0 }
                }
                .onScrollPhaseChange { _, phase in
                    isUserScrolling = phase == .interacting || phase == .decelerating
                    if phase == .idle, isNearLatest { followsLatest = true }
                }
                .onChange(of: messages.count) { oldCount, newCount in
                    guard !showsTasks, newCount > oldCount else { return }
                    if followsLatest || messages.last?.author == .user {
                        followsLatest = true
                        revealLatest(using: proxy)
                    } else { unreadMessages += newCount - oldCount }
                }
                .overlay(alignment: .bottom) {
                    if unreadMessages > 0, !showsTasks {
                        Button {
                            followsLatest = true; unreadMessages = 0
                            revealLatest(using: proxy)
                        } label: {
                            Label("\(unreadMessages) new messages", systemImage: "arrow.down")
                        }
                        .buttonStyle(.glass).controlSize(.large).padding(.bottom, StudioSpacing.medium)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OutcomeComposer(store: store, outcomeID: outcome.id,
                            draft: store.draft(for: outcome.id, initialText: initialDraft))
                .padding(.top, StudioSpacing.standard)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
    }

    private func revealLatest(using proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            proxy.scrollTo("end", anchor: .bottom)
        }
    }
}
