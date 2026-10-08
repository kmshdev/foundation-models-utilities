import EngineeringCore
import Foundation
import Observation

@MainActor @Observable
final class StudioStore {
    private(set) var workspace = Workspace()
    private(set) var isLoaded = false
    private(set) var isPlanning = false
    private(set) var saveState = "Opening workspace"
    var failure: String?
    var usesOnDeviceModel = false
    private let repository: WorkspaceRepository
    private var loadStarted = false
    private var planningTask: Task<Void, Never>?

    init() {
        let directory = URL.applicationSupportDirectory.appendingPathComponent("EngineeringStudio", isDirectory: true)
        repository = WorkspaceRepository(url: directory.appendingPathComponent("workspace.json"))
        usesOnDeviceModel = UserDefaults.standard.bool(forKey: "usesOnDeviceModel")
    }

    func load() async {
        guard !loadStarted else { return }; loadStarted = true
        do {
            workspace = try await repository.load()
            isLoaded = true; saveState = "Saved on this device"
        } catch { failure = "Could not open the workspace. \(error.localizedDescription)"; saveState = "Workspace unavailable" }
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
        let answers = workspace.questions.filter { $0.outcomeID == outcome.id }.flatMap(\.questions)
            .compactMap { question in question.answer.map { "\(question.prompt): \($0)" } }.joined(separator: "\n")
        planningTask = Task {
            defer { isPlanning = false; planningTask = nil }
            do {
                let result = try await FoundationPlanner.onDevice(outcome: outcome.text, answers: answers)
                try Task.checkCancellation()
                if !result.questions.isEmpty {
                    workspace.questions.append(.init(outcomeID: outcome.id, questions: result.questions))
                    workspace.messages.append(.init(author: .coordinator, text: "I need these details to finish the assignment plan. You can answer them together below."))
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
            } catch WorkspaceError.staleRevision {
                // Another write from this store has already persisted the newer snapshot.
            } catch {
                saveState = "Changes not saved"
                failure = "Could not save the workspace. Your changes remain in memory. \(error.localizedDescription)"
            }
        }
    }
}
