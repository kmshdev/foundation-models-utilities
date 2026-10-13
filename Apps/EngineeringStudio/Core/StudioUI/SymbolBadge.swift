import EngineeringCore
import SwiftUI

package struct SymbolBadge: View {
    package let symbol: String
    package var size: CGFloat = 48
    package var tint: Color = .primary
    @ScaledMetric(relativeTo: .body) private var scale = 1.0
    package init(symbol: String, size: CGFloat = 48, tint: Color = .primary) {
        self.symbol = symbol; self.size = size; self.tint = tint
    }
    package var body: some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: size * scale * 0.47))
            .foregroundStyle(tint)
            .frame(width: size * scale, height: size * scale)
            .background(.quaternary, in: .circle)
            .accessibilityHidden(true)
    }
}
