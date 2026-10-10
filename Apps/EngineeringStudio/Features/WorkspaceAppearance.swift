import EngineeringCore
import SwiftUI

/// Decorative workspace color lives below semantic system materials, never in
/// a rasterized imitation of glass. Accessibility settings retain their effect.
struct StudioBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            Color(red: 0.075, green: 0.115, blue: 0.17)
            if !reduceTransparency {
                LinearGradient(colors: [.blue.opacity(0.20), .clear, .blue.opacity(0.10)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [.blue.opacity(0.23), .clear], center: .bottomLeading,
                               startRadius: 0, endRadius: 620)
                RadialGradient(colors: [.blue.opacity(0.12), .clear], center: .topTrailing,
                               startRadius: 0, endRadius: 600)
            }
        }.ignoresSafeArea()
    }
}

struct WorkspacePanel: ViewModifier {
    @Environment(\.accessibilityContrast) private var contrast
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(.white.opacity(contrast == .increased ? 0.55 : 0.17), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

struct SymbolBadge: View {
    let symbol: String
    var size: CGFloat = 48
    var tint: Color = .primary
    var body: some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: size * 0.47, weight: .regular))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(.thinMaterial, in: .circle)
            .overlay { Circle().strokeBorder(.white.opacity(0.17), lineWidth: 1) }
            .accessibilityHidden(true)
    }
}

extension Specialty {
    /// Compact names are presentation only; the full specialty remains available
    /// in Developers and accessibility labels.
    var displayName: String {
        switch self {
        case .architecture: "Architecture"
        case .models: "Models"
        case .authentication: "Security"
        case .interface: "SwiftUI"
        case .platforms: "Platforms"
        case .cloud: "Cloudflare"
        case .quality: "Testing"
        case .integration: "Integration"
        }
    }
}
