import EngineeringCore
import SwiftUI

struct TeamAvailabilityLabel: View {
    let runtime: DeveloperRuntimeConnection

    var body: some View {
        HStack(alignment: .top, spacing: StudioSpacing.medium) {
            Image(systemName: "person.2").font(.title3).frame(width: 26).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Developers")
                    Spacer(minLength: 0)
                    Text(Specialty.allCases.count, format: .number).foregroundStyle(.secondary)
                }
                Label(runtime.state.connected ? "\(runtime.availableCount) available" : "Offline",
                      systemImage: runtime.state.connected ? "circle.fill" : "circle")
                    .font(StudioTypography.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(.rect)
    }
}
