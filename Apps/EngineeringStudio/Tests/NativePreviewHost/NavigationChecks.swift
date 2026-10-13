@testable import WorkspaceFeature
import EngineeringCore
import Foundation

/// Calls the same arbitration used by StudioRootView, without rendering or live I/O.
@MainActor
func checkWorkspaceNavigation() throws {
    let task = WorkTask(id: "routing-task", title: "Inspect task", owner: .architecture,
                        paths: ["Core/Task.swift"], acceptance: ["Task context is visible"],
                        dependencies: [], handoff: "Share the verified result")
    let first = Outcome(text: "Earlier outcome", plan: WorkPlan(summary: "Earlier plan", tasks: [task]))
    let latest = Outcome(text: "Latest outcome")
    let created = Outcome(text: "New outcome")
    let outcomes = [first, latest]
    let route = try navigationRoute(outcomeID: first.id, taskID: task.id)
    let navigation = WorkspaceNavigation()
    navigation.activate(route)

    var beforeLoad = WorkspaceRouting()
    try navigationRequire(beforeLoad.resolve(
        .init(isLoaded: false, latestOutcomeID: nil, requestID: navigation.requestID),
        request: navigation.request, outcomes: []) == .none,
        "A link waits for workspace restoration")
    let restored = WorkspaceRoutingInput(isLoaded: true, latestOutcomeID: latest.id, requestID: navigation.requestID)
    try navigationRequire(beforeLoad.resolve(restored, request: navigation.request, outcomes: outcomes) ==
                          .select(outcomeID: first.id, taskID: task.id),
                          "A cold-start link overrides the latest restored outcome")
    try navigationRequire(beforeLoad.resolve(restored, request: navigation.request, outcomes: outcomes) == .none,
                          "The completed restore cannot replace the already applied link")
    try navigationRequire(beforeLoad.resolve(
        .init(isLoaded: true, latestOutcomeID: created.id, requestID: navigation.requestID),
        request: navigation.request, outcomes: outcomes + [created]) == .select(outcomeID: created.id, taskID: nil),
        "A later created outcome is selected without replaying the consumed link")

    var afterLoad = WorkspaceRouting()
    try navigationRequire(afterLoad.resolve(
        .init(isLoaded: true, latestOutcomeID: latest.id, requestID: nil),
        request: nil, outcomes: outcomes) == .select(outcomeID: latest.id, taskID: nil),
        "Normal initial restoration selects the latest saved outcome")
    try navigationRequire(afterLoad.resolve(restored, request: navigation.request, outcomes: outcomes) ==
                          .select(outcomeID: first.id, taskID: task.id),
                          "A link received after loading has the same outcome and task")

    var simultaneous = WorkspaceRouting()
    try navigationRequire(simultaneous.resolve(restored, request: navigation.request, outcomes: outcomes) ==
                          .select(outcomeID: first.id, taskID: task.id),
                          "Simultaneous restoration and URL delivery prioritize the explicit route")
    let previousRequest = navigation.requestID
    navigation.activate(route)
    try navigationRequire(navigation.requestID != previousRequest,
                          "Repeated URL delivery receives a new event identity")
    try navigationRequire(simultaneous.resolve(
        .init(isLoaded: true, latestOutcomeID: latest.id, requestID: navigation.requestID),
        request: navigation.request, outcomes: outcomes) == .select(outcomeID: first.id, taskID: task.id),
        "A repeated route can reopen the same task after Back")

    var seeded = WorkspaceRouting(preservesInitialSelection: true)
    try navigationRequire(seeded.resolve(
        .init(isLoaded: true, latestOutcomeID: latest.id, requestID: nil),
        request: nil, outcomes: outcomes) == .none,
        "Intentional preview selection seeds survive their initial appearance")
    try navigationRequire(seeded.resolve(
        .init(isLoaded: true, latestOutcomeID: latest.id, requestID: navigation.requestID),
        request: navigation.request, outcomes: outcomes) == .select(outcomeID: first.id, taskID: task.id),
        "An explicit link still supersedes a seeded selection")

    let unknown = try navigationRoute(outcomeID: UUID(), taskID: nil)
    navigation.activate(unknown)
    let unknownInput = WorkspaceRoutingInput(isLoaded: true, latestOutcomeID: latest.id,
                                             requestID: navigation.requestID)
    try navigationRequire(seeded.resolve(unknownInput, request: navigation.request, outcomes: outcomes) == .missingOutcome,
                          "An unknown outcome fails without selecting another resource")
    try navigationRequire(seeded.resolve(unknownInput, request: navigation.request, outcomes: outcomes) == .none,
                          "An unknown route is reported once per delivery")
    navigation.activate(try navigationRoute(outcomeID: first.id, taskID: "missing-task"))
    try navigationRequire(seeded.resolve(
        .init(isLoaded: true, latestOutcomeID: latest.id, requestID: navigation.requestID),
        request: navigation.request, outcomes: outcomes) == .select(outcomeID: first.id, taskID: nil),
        "An absent task opens its saved outcome rather than another task")

    // StudioWindow owns one of these instances per window; service state remains shared.
    let otherWindow = WorkspaceNavigation()
    let firstWindowRequest = navigation.requestID
    otherWindow.activate(try navigationRoute(outcomeID: latest.id, taskID: nil))
    try navigationRequire(navigation.requestID == firstWindowRequest && navigation.request?.outcomeID == first.id &&
                          otherWindow.request?.outcomeID == latest.id,
                          "Routing another window leaves the first window's request unchanged")
    print("Workspace navigation checks passed: restore/URL arbitration, repeated links, later creation, seeds and window isolation.")
}

private func navigationRoute(outcomeID: UUID, taskID: String?) throws -> StudioDeepLink {
    var components = URLComponents()
    components.scheme = "engineeringstudio"
    components.host = "outcome"
    components.path = "/\(outcomeID.uuidString)"
    if let taskID { components.queryItems = [URLQueryItem(name: "task", value: taskID)] }
    guard let url = components.url, let route = StudioDeepLink(url: url) else {
        throw NSError(domain: "NavigationChecks", code: 1)
    }
    return route
}

private func navigationRequire(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw NSError(domain: "NavigationChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
