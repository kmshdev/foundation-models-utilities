import EngineeringCore
import SwiftUI

struct ProposedHandoffView: View {
    let task: WorkTask
    let record: ExecutionRecord?
    private var matchingRecord: ExecutionRecord? { record?.task == task ? record : nil }

    var body: some View {
        HStack(alignment: .top, spacing: StudioSpacing.standard) {
            SymbolBadge(symbol: task.owner.symbol)
            VStack(alignment: .leading, spacing: StudioSpacing.medium) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { owner; context }
                    VStack(alignment: .leading, spacing: 4) { owner; context }
                }.font(StudioTypography.secondary)
                Text(matchingRecord?.status == .completed ? (matchingRecord?.summary ?? task.handoff) : task.handoff)
                    .font(StudioTypography.body).lineSpacing(4).textSelection(.enabled)
                HStack(spacing: StudioSpacing.medium) {
                    SymbolBadge(symbol: "doc.text", size: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title)
                        Text(matchingRecord?.status.rawValue.capitalized ?? "Planned · Not dispatched")
                            .font(StudioTypography.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.turn.down.right").foregroundStyle(.secondary).accessibilityHidden(true)
                }
                .padding(StudioSpacing.medium).background(.thinMaterial, in: .rect(cornerRadius: StudioRadius.control))
                .overlay { RoundedRectangle(cornerRadius: StudioRadius.control).strokeBorder(.primary.opacity(0.10)) }
            }.padding(.top, 5)
        }
    }

    private var owner: some View { Text(task.owner.displayName).fontWeight(.semibold) }
    private var context: some View {
        Text(matchingRecord?.status == .completed ? "Result" : "Handoff").foregroundStyle(.secondary)
    }
}
