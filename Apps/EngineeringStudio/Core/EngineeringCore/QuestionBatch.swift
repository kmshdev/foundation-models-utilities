import Foundation

public struct QuestionBatch: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let outcomeID: UUID
    public private(set) var questions: [Question]
    public var isComplete: Bool { !questions.isEmpty && questions.allSatisfy { $0.answer != nil } }
    public init(id: UUID = UUID(), outcomeID: UUID, questions: [Question]) {
        self.id = id; self.outcomeID = outcomeID; self.questions = questions
    }
    public mutating func answer(_ answers: [UUID: String]) throws {
        guard Set(answers.keys).isSubset(of: Set(questions.map(\.id))) else {
            throw PlanError.invalid("An answer refers to an unknown question.")
        }
        for index in questions.indices {
            if let value = answers[questions[index].id] {
                let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
                questions[index].answer = text.isEmpty ? nil : text
            }
        }
    }
}
