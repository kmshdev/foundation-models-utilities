import EngineeringCore
import Foundation
import Observation

@MainActor @Observable
final class OutcomeDraft {
    var text: String {
        didSet { if text != oldValue { didChange?() } }
    }
    @ObservationIgnored private let didChange: (@MainActor () -> Void)?
    init(text: String = "", didChange: (@MainActor () -> Void)? = nil) {
        self.text = text
        self.didChange = didChange
    }
}

@MainActor @Observable
final class StudioStore {
    typealias Planner = @MainActor (String, String) async throws -> PlanningResult
    private(set) var workspace = Workspace()
    private(set) var isLoaded = false
    private(set) var isPlanning = false
    private(set) var planningOutcomeID: UUID?
    private(set) var saveState = "Opening workspace"
    var failure: String?
    private(set) var planningProvider: PlanningProvider = .disabled
    var usesOnDeviceModel: Bool { planningProvider == .onDevice }
    var isPlanningEnabled: Bool { planningProvider != .disabled }
    private let repository: WorkspaceRepository
    @ObservationIgnored private let planner: Planner
    @ObservationIgnored private var subscriptionPlanner: Planner?
    @ObservationIgnored private var loadStarted = false
    @ObservationIgnored private var planningTask: Task<Void, Never>?
    private var planningQueue: [UUID] = []
    @ObservationIgnored private var contextVersions: [UUID: Int] = [:]
    @ObservationIgnored private var drafts: [UUID: OutcomeDraft] = [:]
    @ObservationIgnored private var draftSaveTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Bool, Never>?
    @ObservationIgnored private var lastSaveRevision = 0
    @ObservationIgnored private var saveFailure: String?

    init() {
        let directory = URL.applicationSupportDirectory.appendingPathComponent("EngineeringStudio", isDirectory: true)
        repository = WorkspaceRepository(url: directory.appendingPathComponent("workspace.json"))
        planner = FoundationPlanner.onDevice
        if let saved = UserDefaults.standard.string(forKey: "planningProvider"),
           let provider = PlanningProvider(rawValue: saved) {
            planningProvider = provider
        } else {
            planningProvider = UserDefaults.standard.bool(forKey: "usesOnDeviceModel") ? .onDevice : .disabled
        }
    }

    /// Dependency injection for persistence checks; no user defaults are changed.
    init(repository: WorkspaceRepository, usesOnDeviceModel: Bool = false,
         planner: @escaping Planner = FoundationPlanner.onDevice) {
        self.repository = repository
        planningProvider = usesOnDeviceModel ? .onDevice : .disabled
        self.planner = planner
    }

    /// Retains unsent text across outcome/view switches and app relaunches.
    /// The composer observes its own draft, so typing does not invalidate history.
    func draft(for outcomeID: UUID, initialText: String = "") -> OutcomeDraft {
        if let draft = drafts[outcomeID] { return draft }
        let draft = OutcomeDraft(text: workspace.drafts[outcomeID] ?? initialText) { [weak self] in
            self?.scheduleDraftSave()
        }
        drafts[outcomeID] = draft
        return draft
    }

    @discardableResult func sendDraft(to outcomeID: UUID) -> Bool {
        let draft = draft(for: outcomeID)
        guard isLoaded else { return false }
        do {
            try workspace.recordMessage(draft.text, for: outcomeID)
            draft.text = ""
            // One snapshot contains both the message and the cleared draft.
            // Retry only writes this snapshot; it never records another message.
            persist()
            enqueuePlanning(for: outcomeID)
            return true
        } catch { failure = error.localizedDescription; return false }
    }

    #if DEBUG
    /// Self-contained preview state; does not read user defaults, disk or services.
    init(preview workspace: Workspace) {
        self.workspace = workspace
        repository = WorkspaceRepository(url: URL.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        planner = FoundationPlanner.onDevice
        isLoaded = true
        loadStarted = true
        saveState = "Preview data · not connected"
    }
    #endif

    func load() async {
        guard !loadStarted else { return }; loadStarted = true
        do {
            workspace = try await repository.load()
            lastSaveRevision = workspace.revision
            isLoaded = true; failure = nil; saveState = "Saved on this device"
        } catch {
            loadStarted = false
            failure = "Could not open the workspace. \(error.localizedDescription)"
            saveState = "Workspace unavailable"
        }
    }

    func setOnDeviceModel(_ enabled: Bool) {
        setPlanningProvider(enabled ? .onDevice : .disabled)
    }

    func configureSubscriptionPlanner(_ planner: @escaping Planner) {
        subscriptionPlanner = planner
    }

    func setPlanningProvider(_ provider: PlanningProvider) {
        guard planningProvider != provider else { return }
        cancelPlanning()
        planningProvider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: "planningProvider")
        UserDefaults.standard.set(provider == .onDevice, forKey: "usesOnDeviceModel")
    }

    @discardableResult func submit(_ text: String) -> Bool {
        guard isLoaded else { return false }
        do {
            try workspace.recordOutcome(text)
            persist()
            if isPlanningEnabled, let outcome = workspace.outcomes.last { plan(outcome) }
            return true
        }
        catch { failure = error.localizedDescription; return false }
    }

    func hasImportedIssue(id: String) -> Bool {
        workspace.outcomes.contains { $0.source?.matches(kind: .linear, id: id) == true }
    }

    @discardableResult func importIssue(_ issue: LinearIssue) -> Bool {
        guard isLoaded, !hasImportedIssue(id: issue.id) else { return false }
        let text = ["\(issue.identifier): \(issue.title)", issue.description]
            .compactMap { $0 }.joined(separator: "\n\n")
        do {
            let id = try workspace.recordOutcome(text, source: OutcomeSource(kind: .linear, id: issue.id, url: issue.webURL))
            persist()
            enqueuePlanning(for: id)
            return true
        } catch { failure = error.localizedDescription; return false }
    }

    func issueBinding(outcomeID: UUID, taskID: String) -> TaskIssueBinding? {
        workspace.issueBinding(outcomeID: outcomeID, taskID: taskID)
    }

    /// The caller must await this durable reservation before any network mutation.
    /// Retrying returns the same issue ID, including after an ambiguous response.
    func prepareIssuePublication(outcomeID: UUID, task: WorkTask) async throws -> TaskIssueBinding {
        guard isLoaded else { throw WorkspaceError.workspaceNotLoaded }
        let binding = try workspace.reserveIssuePublication(outcomeID: outcomeID, taskID: task.id)
        guard await flushPendingChanges() else { throw WorkspaceError.publicationNotSaved }
        return issueBinding(outcomeID: outcomeID, taskID: task.id) ?? binding
    }

    func recordIssuePublication(outcomeID: UUID, task: WorkTask, issue: LinearIssue) async throws {
        guard isLoaded else { throw WorkspaceError.workspaceNotLoaded }
        guard let issueID = UUID(uuidString: issue.id) else { throw WorkspaceError.issueReceiptMismatch }
        try workspace.recordIssuePublication(outcomeID: outcomeID, task: task, issueID: issueID,
                                             identifier: issue.identifier, webURL: issue.webURL)
        guard await flushPendingChanges() else { throw WorkspaceError.publicationNotSaved }
    }

    func plan(_ outcome: Outcome) {
        enqueuePlanning(for: outcome.id)
    }

    func isQueuedForPlanning(_ outcomeID: UUID) -> Bool {
        planningQueue.contains(outcomeID)
    }

    private func enqueuePlanning(for outcomeID: UUID) {
        // Version even gated requests so changing answers cannot publish a plan
        // produced from the old answer set while a model call is suspended.
        contextVersions[outcomeID, default: 0] += 1
        guard isLoaded, isPlanningEnabled,
              workspace.outcomes.contains(where: { $0.id == outcomeID }),
              !hasUnansweredQuestions(for: outcomeID) else { return }
        if !planningQueue.contains(outcomeID) { planningQueue.append(outcomeID) }
        startPlanningIfNeeded()
    }

    private func hasUnansweredQuestions(for outcomeID: UUID) -> Bool {
        workspace.questions.contains { $0.outcomeID == outcomeID && !$0.isComplete }
    }

    private func startPlanningIfNeeded() {
        guard planningTask == nil, isPlanningEnabled, !planningQueue.isEmpty else { return }
        isPlanning = true
        planningTask = Task {
            defer {
                isPlanning = false; planningOutcomeID = nil; planningTask = nil
                // A new request may arrive while a cancelled provider unwinds.
                // Keep one provider call active at a time, including that period.
                startPlanningIfNeeded()
            }
            while !Task.isCancelled, isPlanningEnabled, !planningQueue.isEmpty {
                let outcomeID = planningQueue.removeFirst()
                guard !hasUnansweredQuestions(for: outcomeID),
                      let outcome = workspace.outcomes.first(where: { $0.id == outcomeID }) else { continue }
                planningOutcomeID = outcomeID
                let version = contextVersions[outcomeID, default: 0]
                let answers = workspace.questions.filter { $0.outcomeID == outcomeID }.flatMap(\.questions)
                    .compactMap { question in question.answer.map { "\(question.prompt): \($0)" } }.joined(separator: "\n")
                let context = workspace.messages.filter { $0.outcomeID == outcomeID && $0.author == .user }
                    .dropFirst().map(\.text).joined(separator: "\n")
                do {
                    let selectedPlanner: Planner
                    switch planningProvider {
                    case .onDevice: selectedPlanner = planner
                    case .chatGPT:
                        guard let subscriptionPlanner else {
                            throw ChatGPTConnectionError.notConnected
                        }
                        selectedPlanner = subscriptionPlanner
                    case .disabled: continue
                    }
                    let result = try await selectedPlanner(outcome.text, [answers, context].joined(separator: "\n"))
                    try Task.checkCancellation()
                    guard isPlanningEnabled, contextVersions[outcomeID] == version,
                          !hasUnansweredQuestions(for: outcomeID) else { continue }
                    if !result.questions.isEmpty {
                        workspace.questions.append(.init(outcomeID: outcomeID, questions: result.questions))
                        workspace.messages.append(.init(author: .coordinator, text: "I need these details to finish the assignment plan. You can answer them together below.", outcomeID: outcomeID))
                        workspace.revision += 1
                    } else if let plan = result.plan {
                        try workspace.attach(plan, to: outcomeID)
                    }
                    persist()
                } catch is CancellationError { }
                catch {
                    if !Task.isCancelled, contextVersions[outcomeID] == version {
                        failure = error.localizedDescription
                    }
                }
            }
        }
    }

    func cancelPlanning() {
        planningQueue.removeAll()
        planningTask?.cancel()
    }

    @discardableResult func send(_ text: String, to outcomeID: UUID) -> Bool {
        guard isLoaded else { return false }
        do {
            try workspace.recordMessage(text, for: outcomeID)
            persist()
            enqueuePlanning(for: outcomeID)
            return true
        } catch { failure = error.localizedDescription; return false }
    }

    func answer(_ batch: QuestionBatch, answers: [UUID: String]) {
        guard let index = workspace.questions.firstIndex(where: { $0.id == batch.id }) else { return }
        do {
            try workspace.questions[index].answer(answers)
            workspace.revision += 1; persist()
            enqueuePlanning(for: workspace.questions[index].outcomeID)
        } catch { failure = error.localizedDescription }
    }

    func retrySave() { persist() }

    /// Await at lifecycle boundaries; normal typing is saved after a short pause.
    /// A false result leaves all edits in memory with retryable failure feedback.
    @discardableResult func flushPendingChanges() async -> Bool {
        guard isLoaded else { return false }
        return await persist().value
    }

    private func scheduleDraftSave() {
        draftSaveTask?.cancel()
        guard isLoaded else { return }
        draftSaveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) }
            catch { return }
            guard let self else { return }
            self.persist()
        }
    }

    @discardableResult private func persist() -> Task<Bool, Never> {
        draftSaveTask?.cancel()
        draftSaveTask = nil
        var snapshot = workspace
        for (id, draft) in drafts {
            snapshot.drafts[id] = draft.text.isEmpty ? nil : draft.text
        }
        // Draft edits do not publish a workspace mutation on every keystroke.
        // Assign the durable revision separately, at the snapshot boundary.
        lastSaveRevision = max(lastSaveRevision, workspace.revision) + 1
        snapshot.revision = lastSaveRevision
        let revision = snapshot.revision
        let precedingSave = saveTask
        saveState = "Saving…"
        let task = Task { [snapshot] in
            // An actor serializes each operation, not the order that independent
            // Tasks reach it. Chain writes explicitly to preserve edit order.
            if let precedingSave { _ = await precedingSave.value }
            do {
                try await repository.save(snapshot)
                if lastSaveRevision == revision {
                    saveState = "Saved on this device"
                    // Clear only this persistence error, not a newer planning or
                    // input error that happens to be presented during the write.
                    if failure == saveFailure { failure = nil }
                    saveFailure = nil
                }
                return true
            } catch {
                // An obsolete write must not overwrite newer save feedback. A
                // conflict for the current revision is an error, never silent.
                if lastSaveRevision == revision {
                    saveState = "Changes not saved"
                    let message = "Could not save the workspace. Your changes remain in memory. \(error.localizedDescription)"
                    saveFailure = message
                    failure = message
                }
                return false
            }
        }
        saveTask = task
        return task
    }
}
