import EngineeringCore
import SwiftUI

struct TeamView: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                StudioHeading(eyebrow: "Team / 03", title: "Eight distinct disciplines.",
                              detail: "Availability will come from connected developers. A configured specialty is not a running bot.")
                StatusStrip()
                ForEach(Specialty.allCases) { specialty in
                    HStack(alignment: .top, spacing: 18) {
                        Image(systemName: specialty.symbol).font(.title2).foregroundStyle(.secondary)
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
