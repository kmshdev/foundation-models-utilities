import EngineeringCore
import SwiftUI

struct MessageRow: View {
    let message: RoomMessage
    @Environment(\.dynamicTypeSize) private var dynamicType

    var body: some View {
        HStack(alignment: .top, spacing: StudioSpacing.standard) {
            SymbolBadge(symbol: message.author == .user ? "person.fill" : "sparkle", size: 48)
            VStack(alignment: .leading, spacing: StudioSpacing.small) {
                metadata
                Text(message.text)
                    .font(StudioTypography.body).lineSpacing(4)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var metadata: some View {
        if dynamicType.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) { author; timestamp }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: StudioSpacing.small) { author; timestamp }
                VStack(alignment: .leading, spacing: 4) { author; timestamp }
            }
        }
    }

    private var author: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(message.author == .user ? "You" : "Coordinator").font(StudioTypography.label)
            if message.author != .user {
                Text("· AI").font(StudioTypography.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var timestamp: some View {
        Text(message.createdAt, style: .time)
            .font(StudioTypography.caption).foregroundStyle(.secondary)
    }
}
