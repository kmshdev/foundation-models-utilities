import EngineeringCore
import SwiftUI

struct WorkListView: View {
    @Bindable var store: StudioStore
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                StudioHeading(eyebrow: "Work / 02", title: "Intent, then evidence.",
                              detail: "Every outcome carries its assignment plan, acceptance criteria and handoff requirements.")
                if store.workspace.outcomes.isEmpty {
                    ContentUnavailableView("No outcomes yet", systemImage: "square.stack.3d.up", description: Text("Add your first outcome in Engineering."))
                }
                ForEach(store.workspace.outcomes.reversed()) { outcome in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(outcome.createdAt, style: .date).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text(outcome.text).font(.headline).textSelection(.enabled)
                        OutcomeSummary(outcome: outcome, store: store)
                    }.padding(.vertical, 16).overlay(alignment: .top) { Divider() }
                }
            }.padding(24).frame(maxWidth: 840).frame(maxWidth: .infinity)
        }.background(StudioStyle.paper).navigationTitle("Work")
    }
}

struct PlanDetailView: View {
    let plan: WorkPlan
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                StudioHeading(eyebrow: "Assignments / Draft", title: "A clear division of work.", detail: plan.summary)
                Label("Developers are not connected. These assignments have not been dispatched.", systemImage: "network.slash")
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(plan.tasks) { task in
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(task.id.uppercased()).font(.caption.monospaced()).foregroundStyle(StudioStyle.accent)
                            Text(task.owner.title).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(task.title).font(.title2).accessibilityAddTraits(.isHeader)
                        SectionEyebrow(text: "Exclusive scope")
                        ForEach(task.paths, id: \.self) { Text($0).font(.callout.monospaced()).textSelection(.enabled) }
                        SectionEyebrow(text: "Acceptance criteria")
                        ForEach(Array(task.acceptance.enumerated()), id: \.offset) { index, criterion in
                            HStack(alignment: .top) { Text(String(format: "%02d", index + 1)).font(.caption.monospaced()); Text(criterion) }
                        }
                        SectionEyebrow(text: "Handoff")
                        Text(task.handoff)
                        if !task.dependencies.isEmpty {
                            Label("After: \(task.dependencies.joined(separator: ", "))", systemImage: "arrow.turn.down.right")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Text("Tests: not run · Pull request: none").font(.caption.monospaced()).foregroundStyle(.secondary)
                    }.padding(.vertical, 20).frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .top) { Divider() }
                }
            }.padding(24).frame(maxWidth: 840).frame(maxWidth: .infinity)
        }.background(StudioStyle.paper).navigationTitle("Assignment plan")
    }
}

struct TeamView: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                StudioHeading(eyebrow: "Team / 03", title: "Eight distinct disciplines.",
                              detail: "Availability will come from connected developers. A configured specialty is not a running bot.")
                StatusStrip()
                ForEach(Specialty.allCases) { specialty in
                    HStack(alignment: .top, spacing: 18) {
                        Image(systemName: specialty.symbol).font(.title2).foregroundStyle(StudioStyle.accent)
                            .frame(width: 30).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(specialty.title).font(.headline)
                            Text("Offline · No developer connected").font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }.padding(.vertical, 24).overlay(alignment: .bottom) { Divider() }
                }
            }.padding(24).frame(maxWidth: 840).frame(maxWidth: .infinity)
        }.background(StudioStyle.paper).navigationTitle("Team")
    }
}
