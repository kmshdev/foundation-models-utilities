import EngineeringCore
import SwiftUI

enum StudioSection: String, CaseIterable, Identifiable {
    case room = "Engineering", team = "Team", work = "Work", settings = "Settings"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .room: "bubble.left.and.bubble.right"
        case .team: "person.3"
        case .work: "square.stack.3d.up"
        case .settings: "slider.horizontal.3"
        }
    }
}

struct StudioRootView: View {
    @Bindable var store: StudioStore
    @State private var selection: StudioSection? = .room
    /// The initial section is a one-time navigation seed, including for previews.
    init(store: StudioStore, initialSection: StudioSection = .room) {
        self.store = store
        _selection = State(initialValue: initialSection)
    }
    var body: some View {
        Group {
            #if os(macOS)
            NavigationSplitView {
                List(StudioSection.allCases, selection: $selection) { section in
                    Label(section.rawValue, systemImage: section.symbol).tag(section)
                }
                .navigationTitle("Engineering Studio")
                .navigationSplitViewColumnWidth(min: 190, ideal: 220)
            } detail: {
                NavigationStack { content(selection ?? .room) }
            }
            #else
            TabView {
                Tab("Engineering", systemImage: StudioSection.room.symbol) { NavigationStack { content(.room) } }
                Tab("Team", systemImage: StudioSection.team.symbol) { NavigationStack { content(.team) } }
                Tab("Work", systemImage: StudioSection.work.symbol) { NavigationStack { content(.work) } }
                Tab("Settings", systemImage: StudioSection.settings.symbol) { NavigationStack { content(.settings) } }
            }
            #endif
        }
        .tint(StudioStyle.accent)
        .alert("Something needs attention", isPresented: Binding(
            get: { store.failure != nil }, set: { if !$0 { store.failure = nil } }
        )) {
            Button("OK", role: .cancel) { store.failure = nil }
        } message: { Text(store.failure ?? "") }
    }

    @ViewBuilder private func content(_ section: StudioSection) -> some View {
        switch section {
        case .room: EngineeringRoomView(store: store)
        case .team: TeamView()
        case .work: WorkListView(store: store)
        case .settings: StudioSettingsView(store: store)
        }
    }
}

enum StudioStyle {
    static let accent = Color("AccentColor")
    static let paper = Color("Paper")
}

struct SectionEyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.caption.monospaced()).tracking(1.3).foregroundStyle(.secondary)
    }
}

struct StudioHeading: View {
    let eyebrow: String
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionEyebrow(text: eyebrow)
            Text(title).font(.largeTitle.weight(.medium)).fontDesign(.serif)
                .accessibilityAddTraits(.isHeader)
            Text(detail).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 18)
    }
}

struct StatusStrip: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack { Label("8 specialties", systemImage: "person.3"); Spacer(); Label("0 connected", systemImage: "network.slash") }
            VStack(alignment: .leading, spacing: 8) { Label("8 specialties", systemImage: "person.3"); Label("0 connected", systemImage: "network.slash") }
        }
        .font(.caption.monospaced()).padding(.vertical, 12)
        .overlay(alignment: .top) { Divider() }.overlay(alignment: .bottom) { Divider() }
    }
}
