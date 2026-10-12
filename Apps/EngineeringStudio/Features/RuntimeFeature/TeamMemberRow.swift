import StudioWorkflows
import StudioServices
import StudioUI
import EngineeringCore
import SwiftUI

struct TeamMemberRow: View {
    let specialty: Specialty
    let connected: Bool
    let presence: ExecutionDeveloperPresence?

    private var isFresh: Bool {
        guard connected, let presence else { return false }
        let age = Date.now.timeIntervalSince(presence.observedAt)
        return age >= 0 && age <= 90
    }
    private var status: String {
        guard connected, presence != nil else { return "Offline · No developer connected" }
        guard isFresh else { return "Presence needs refresh" }
        return presence?.activeTask == nil ? "Available" : "Working"
    }
    private var symbol: String {
        guard connected, presence != nil else { return "circle" }
        guard isFresh else { return "clock" }
        return presence?.activeTask == nil ? "checkmark.circle" : "arrow.triangle.2.circlepath"
    }
    private var color: Color {
        guard isFresh else { return .secondary }
        return presence?.activeTask == nil ? .green : .blue
    }

    var body: some View {
        HStack(alignment: .top, spacing: StudioSpacing.standard) {
            Image(systemName: specialty.symbol).font(.title2).foregroundStyle(.secondary)
                .frame(width: 30).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: StudioSpacing.small) {
                Text(specialty.title).font(StudioTypography.heading)
                    .fixedSize(horizontal: false, vertical: true)
                Label(status, systemImage: symbol).font(StudioTypography.secondary).foregroundStyle(color)
                    .fixedSize(horizontal: false, vertical: true)
                if connected, let presence {
                    Text("Last observed \(presence.observedAt, format: .dateTime.month(.abbreviated).day().hour().minute())")
                        .font(StudioTypography.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, StudioSpacing.section)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .combine)
    }
}
