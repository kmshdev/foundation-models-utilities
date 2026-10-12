import EngineeringCore
import SwiftUI

struct TeamView: View {
    var runtime: DeveloperRuntimeConnection = DeveloperRuntimeConnection()
    @Environment(\.dynamicTypeSize) private var dynamicType

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: StudioSpacing.medium) {
                    Text("Developers").font(StudioTypography.title).accessibilityAddTraits(.isHeader)
                    if dynamicType.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: StudioSpacing.small) { specialties; connectionStatus }
                    } else {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: StudioSpacing.standard) { specialties; connectionStatus }
                            VStack(alignment: .leading, spacing: StudioSpacing.small) { specialties; connectionStatus }
                        }
                    }
                }.padding(.vertical, StudioSpacing.medium)
                ForEach(Specialty.allCases) { specialty in
                    TeamMemberRow(specialty: specialty, connected: runtime.state.connected,
                                  presence: runtime.state.developers.first { $0.specialty == specialty })
                }
            }.padding(StudioSpacing.section).frame(maxWidth: 840).frame(maxWidth: .infinity)
        }.background(StudioStyle.paper).navigationTitle("Team")
    }

    private var specialties: some View {
        Label("\(Specialty.allCases.count) specialties", systemImage: "person.3")
            .font(StudioTypography.secondary).foregroundStyle(.secondary)
    }
    private var connectionStatus: some View {
        Label(runtime.status, systemImage: "terminal")
            .font(StudioTypography.secondary).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
