import Foundation

public enum PlanError: Error, LocalizedError, Equatable {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { message } else { nil } }
}

public enum PlanValidator {
    /// Read-only validation. A valid plan does not imply that a developer has accepted it.
    public static func validate(_ plan: WorkPlan) throws {
        guard !plan.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !plan.tasks.isEmpty else { throw PlanError.invalid("A plan needs a summary and tasks.") }
        let ids = Set(plan.tasks.map(\.id))
        guard ids.count == plan.tasks.count else { throw PlanError.invalid("Task IDs must be unique.") }
        let tasks = Dictionary(uniqueKeysWithValues: plan.tasks.map { ($0.id, $0) })
        for task in plan.tasks {
            guard !task.id.isEmpty, !task.title.isEmpty, !task.handoff.isEmpty,
                  !task.paths.isEmpty, !task.acceptance.isEmpty,
                  task.acceptance.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            else { throw PlanError.invalid("Every task needs an owner, file scope, acceptance criteria, and a handoff.") }
            guard task.dependencies.allSatisfy({ ids.contains($0) && $0 != task.id }) else {
                throw PlanError.invalid("Task \(task.id) has an unknown or self dependency.")
            }
            for path in task.paths { _ = try canonicalPath(path) }
        }
        var cached: [String: Set<String>] = [:]
        func ancestors(_ id: String, visiting: Set<String> = []) throws -> Set<String> {
            if let found = cached[id] { return found }
            guard !visiting.contains(id) else { throw PlanError.invalid("Task dependencies contain a cycle.") }
            var next = visiting; next.insert(id)
            var result: Set<String> = []
            for dependency in tasks[id]!.dependencies {
                result.insert(dependency)
                result.formUnion(try ancestors(dependency, visiting: next))
            }
            cached[id] = result
            return result
        }
        var dependencies: [String: Set<String>] = [:]
        for task in plan.tasks { dependencies[task.id] = try ancestors(task.id) }
        for (index, task) in plan.tasks.enumerated() {
            for other in plan.tasks.dropFirst(index + 1) {
                let ordered = dependencies[task.id]!.contains(other.id) || dependencies[other.id]!.contains(task.id)
                guard !ordered else { continue }
                for a in task.paths {
                    for b in other.paths where try overlaps(a, b) {
                        throw PlanError.invalid("\(task.id) and \(other.id) overlap. Split their file scopes or add a handoff dependency.")
                    }
                }
            }
        }
    }

    static func canonicalPath(_ path: String) throws -> String {
        let pieces = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"),
              !path.contains(":"), !path.contains("*"), !path.contains("?"),
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              pieces.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw PlanError.invalid("Use a relative file or directory path without wildcards: \(path)")
        }
        return path.precomposedStringWithCanonicalMapping.lowercased()
    }
    static func overlaps(_ lhs: String, _ rhs: String) throws -> Bool {
        let a = try canonicalPath(lhs), b = try canonicalPath(rhs)
        return a == b || a.hasPrefix(b + "/") || b.hasPrefix(a + "/")
    }
}
