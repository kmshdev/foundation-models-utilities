import EngineeringCore
import SwiftUI

struct TeamView: View {
    var runtime: DeveloperRuntimeConnection = DeveloperRuntimeConnection()
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                StudioHeading(eyebrow: "Team / 03", title: "Eight distinct disciplines.",
                              detail: runtime.status)
                HStack { Label("8 specialties", systemImage: "person.3"); Spacer(); Label(runtime.status, systemImage: "terminal") }.font(.caption).foregroundStyle(.secondary)
                ForEach(Specialty.allCases) { specialty in
                    HStack(alignment: .top, spacing: 18) {
                        Image(systemName: specialty.symbol).font(.title2).foregroundStyle(.secondary)
                            .frame(width: 30).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(specialty.title).font(.headline)
                            Text(presenceDescription(specialty)).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }.padding(.vertical, 24).overlay(alignment: .bottom) { Divider() }
                }
            }.padding(24).frame(maxWidth: 840).frame(maxWidth: .infinity)
        }.background(StudioStyle.paper).navigationTitle("Team")
    }
    private func presenceDescription(_ specialty: Specialty) -> String {
        guard runtime.state.connected, let presence = runtime.state.developers.first(where: { $0.specialty == specialty }) else {
            return "Offline · No developer connected"
        }
        if presence.isAvailable(at: .now) { return "Available" }
        if presence.activeTask != nil { return "Working" }
        return "Presence needs refresh"
    }
}
