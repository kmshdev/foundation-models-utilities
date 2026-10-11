import EngineeringCore
import SwiftUI

enum StudioSpacing {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let standard: CGFloat = 16
    static let section: CGFloat = 24
    static let group: CGFloat = 32
}
enum StudioRadius {
    static let control: CGFloat = 12
    static let container: CGFloat = 20
}

enum StudioTypography {
    static let title = Font.title2.weight(.semibold)
    static let heading = Font.headline
    static let label = Font.subheadline.weight(.semibold)
    static let secondary = Font.callout
    static let caption = Font.caption
    static var body: Font {
        #if os(macOS)
        .system(size: 15)
        #else
        .body
        #endif
    }
}

struct StudioBackdrop: View {
    var body: some View { Rectangle().fill(.background).ignoresSafeArea() }
}

struct WorkspacePanel: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content
            .background(.thinMaterial, in: .rect(cornerRadius: StudioRadius.container))
            .overlay {
                RoundedRectangle(cornerRadius: StudioRadius.container)
                    .strokeBorder(.primary.opacity(contrast == .increased ? 0.45 : 0.10))
                    .allowsHitTesting(false)
            }
    }
}

struct SymbolBadge: View {
    let symbol: String
    var size: CGFloat = 48
    var tint: Color = .primary
    @ScaledMetric(relativeTo: .body) private var scale = 1.0
    var body: some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: size * scale * 0.47))
            .foregroundStyle(tint)
            .frame(width: size * scale, height: size * scale)
            .background(.quaternary, in: .circle)
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
