import EngineeringCore
import SwiftUI

package struct WorkspacePanel: ViewModifier {
    package init() {}
    @Environment(\.colorSchemeContrast) private var contrast
    package func body(content: Content) -> some View {
        content
            .background(.thinMaterial, in: .rect(cornerRadius: StudioRadius.container))
            .overlay {
                RoundedRectangle(cornerRadius: StudioRadius.container)
                    .strokeBorder(.primary.opacity(contrast == .increased ? 0.45 : 0.10))
                    .allowsHitTesting(false)
            }
    }
}
