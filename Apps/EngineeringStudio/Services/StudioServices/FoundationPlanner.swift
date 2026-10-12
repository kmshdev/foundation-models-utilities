import EngineeringServices
import EngineeringCore
import Foundation
import FoundationModels
import FoundationModelsUtilities

@MainActor
package enum FoundationPlanner {
    package static var availabilityDescription: String {
        switch SystemLanguageModel.default.availability {
        case .available: "Available on this device"
        case .unavailable(let reason): "Unavailable: \(String(describing: reason))"
        }
    }

    package static func onDevice(outcome: String, answers: String) async throws -> PlanningResult {
        guard case .available = SystemLanguageModel.default.availability else {
            throw PlannerFailure.unavailable(availabilityDescription)
        }
        return try await generate(using: SystemLanguageModel.default, outcome: outcome, answers: answers)
    }

    package static func subscription(outcome: String, answers: String, client: ChatGPTResponsesClient,
                             modelName: String) async throws -> PlanningResult {
        try await generate(using: ChatGPTLanguageModel(name: modelName, client: client),
                           outcome: outcome, answers: answers, sourceDescription: "ChatGPT subscription model \(modelName)")
    }

    /// The same session/profile accepts a conforming server model when its supported
    /// authentication and transport are implemented. No subscription credentials are fabricated.
    package static func generate<Model: LanguageModel>(using model: Model, outcome: String, answers: String,
                                               sourceDescription: String = "Apple's on-device model") async throws -> PlanningResult {
        let session = LanguageModelSession(profile: EngineeringProfile(model: model, sourceDescription: sourceDescription))
        do {
            let response = try await session.respond(
                to: "Outcome:\n\(outcome)\n\nPreviously answered questions:\n\(answers)",
                generating: GeneratedPlan.self
            )
            try Task.checkCancellation()
            let generated = response.content
            if !generated.questions.isEmpty {
                return PlanningResult(plan: nil, questions: generated.questions.map { .init(prompt: $0.prompt, options: $0.options) })
            }
            let tasks = try generated.tasks.map { task in
                guard let owner = Specialty(rawValue: task.owner) else { throw PlannerFailure.invalidOwner(task.owner) }
                return WorkTask(id: task.id, title: task.title, owner: owner, paths: task.paths,
                                acceptance: task.acceptance, dependencies: task.dependencies, handoff: task.handoff)
            }
            let plan = WorkPlan(summary: generated.summary, tasks: tasks)
            try PlanValidator.validate(plan)
            return PlanningResult(plan: plan, questions: [])
        } catch let error as LanguageModelError { throw PlannerFailure.model(error.localizedDescription) }
        catch let error as SystemLanguageModel.Error { throw PlannerFailure.onDevice(error.localizedDescription) }
        catch let error as LanguageModelSession.Error { throw PlannerFailure.session(error.localizedDescription) }
    }
}
