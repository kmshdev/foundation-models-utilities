import EngineeringCore
import SwiftUI

extension Specialty {
    /// Compact names are presentation only; the full specialty remains available
    /// in Developers and accessibility labels.
    package var displayName: String {
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
