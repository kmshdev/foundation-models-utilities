import EngineeringCore
import Foundation
import Observation

@MainActor @Observable
final class OutcomeDraft {
    var text: String
    init(text: String = "") { self.text = text }
}

@MainActor @Observable
final class StudioStore {
    private(set) var workspace = Workspace()
    private(set) var isLoaded = false
    private(set) var isPlanning = false
    private(set) var planningOutcomeID: UUID?
    private(set) var saveState = "Opening workspace"
    var failure: String?
    var usesOnDeviceModel = false
    private let repository: WorkspaceRepository
    @ObservationIgnored private var loadStarted = false
    @ObservationIgnored private var planningTask: Task<Void, Never>?
    @ObservationIgnored private var drafts: [UUID: OutcomeDraft] = [:]

    init() {
        let directory = URL.applicationSupportDirectory.appendingPathComponent("EngineeringStudio", isDirectory: true)
        repository = WorkspaceRepository(url: directory.appendingPathComponent("workspace.json"))
        usesOnDeviceModel = UserDefaults.standard.bool(forKey: "usesOnDeviceModel")
    }

    /// Dependency injection for persistence checks; no user defaults are changed.
    init(repository: WorkspaceRepository) { self.repository = repository }

    /// Retains unsent text across outcome/view switches for this app session.
    /// The composer observes its own draft, so typing does not invalidate history.
    func draft(for outcomeID: UUID, initialText: String = "") -> OutcomeDraft {
        if let draft = drafts[outcomeID] { return draft }
        let draft = OutcomeDraft(text: initialText)
        drafts[outcomeID] = draft
        return draft
    }

    @discardableResult func sendDraft(to outcomeID: UUID) -> Bool {
        let draft = draft(for: outcomeID)
        guard send(draft.text, to: outcomeID) else { return false }
        draft.text = ""
        return true
    }

    #if DEBUG
    /// Self-contained preview state; does not read user defaults, disk or services.
    init(preview workspace: Workspace) {
        self.workspace = workspace
        repository = WorkspaceRepository(url: URL.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        isLoaded = true
        loadStarted = true
        saveState = "Preview data · not connected"
    }
    #endif

    func load() async {
        guard !loadStarted else { return }; loadStarted = true
        do {
            workspace = try await repository.load()
            isLoaded = true; failure = nil; saveState = "Saved on this device"
        } catch {
            loadStarted = false
            failure = "Could not open the workspace. \(error.localizedDescription)"
            saveState = "Workspace unavailable"
        }
    }

    func setOnDeviceModel(_ enabled: Bool) {
        usesOnDeviceModel = enabled
        UserDefaults.standard.set(enabled, forKey: "usesOnDeviceModel")
        if !enabled { cancelPlanning() }
    }

    @discardableResult func submit(_ text: String) -> Bool {
        guard isLoaded else { return false }
        do {
            try workspace.recordOutcome(text)
            persist()
            if usesOnDeviceModel, let outcome = workspace.outcomes.last { plan(outcome) }
            return true
        }
        catch { failure = error.localizedDescription; return false }
    }

    func plan(_ outcome: Outcome) {
        guard usesOnDeviceModel, !isPlanning,
              !workspace.questions.contains(where: { $0.outcomeID == outcome.id && !$0.isComplete }) else { return }
        isPlanning = true
        planningOutcomeID = outcome.id
        let answers = workspace.questions.filter { $0.outcomeID == outcome.id }.flatMap(\.questions)
            .compactMap { question in question.answer.map { "\(question.prompt): \($0)" } }.joined(separator: "\n")
        planningTask = Task {
            defer { isPlanning = false; planningOutcomeID = nil; planningTask = nil }
            do {
                let context = workspace.messages.filter { $0.outcomeID == outcome.id && $0.author == .user && $0.text != outcome.text }
                    .map(\.text).joined(separator: "\n")
                let result = try await FoundationPlanner.onDevice(outcome: outcome.text, answers: [answers, context].joined(separator: "\n"))
                try Task.checkCancellation()
                if !result.questions.isEmpty {
                    workspace.questions.append(.init(outcomeID: outcome.id, questions: result.questions))
                    workspace.messages.append(.init(author: .coordinator, text: "I need these details to finish the assignment plan. You can answer them together below.", outcomeID: outcome.id))
                    workspace.revision += 1
                } else if let plan = result.plan {
                    try workspace.attach(plan, to: outcome.id)
                }
                persist()
            } catch is CancellationError { }
            catch { failure = error.localizedDescription }
        }
    }

    func cancelPlanning() { planningTask?.cancel() }

    @discardableResult func send(_ text: String, to outcomeID: UUID) -> Bool {
        guard isLoaded else { return false }
        do {
            try workspace.recordMessage(text, for: outcomeID)
            persist()
            return true
        } catch { failure = error.localizedDescription; return false }
    }

    func answer(_ batch: QuestionBatch, answers: [UUID: String]) {
        guard let index = workspace.questions.firstIndex(where: { $0.id == batch.id }) else { return }
        do {
            try workspace.questions[index].answer(answers)
            workspace.revision += 1; persist()
            if workspace.questions[index].isComplete,
               let outcome = workspace.outcomes.first(where: { $0.id == batch.outcomeID }) { plan(outcome) }
        } catch { failure = error.localizedDescription }
    }

    func retrySave() { persist() }

    private func persist() {
        let snapshot = workspace
        saveState = "Saving…"
        Task {
            do {
                try await repository.save(snapshot)
                if workspace.revision == snapshot.revision { saveState = "Saved on this device" }
            } catch {
                // An obsolete write must not overwrite newer save feedback. A
                // conflict for the current revision is an error, never silent.
                guard workspace.revision == snapshot.revision else { return }
                saveState = "Changes not saved"
                failure = "Could not save the workspace. Your changes remain in memory. \(error.localizedDescription)"
            }
        }
    }
}
