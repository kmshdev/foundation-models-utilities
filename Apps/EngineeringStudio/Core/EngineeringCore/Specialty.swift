import Foundation

public enum Specialty: String, CaseIterable, Codable, Sendable, Identifiable {
    case architecture, models, authentication, interface, platforms, cloud, quality, integration
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .architecture: "Architecture & concurrency"
        case .models: "Foundation Models"
        case .authentication: "Authentication & security"
        case .interface: "SwiftUI & accessibility"
        case .platforms: "iOS & macOS"
        case .cloud: "Cloudflare infrastructure"
        case .quality: "Testing & evaluation"
        case .integration: "CI & integration"
        }
    }
    public var symbol: String {
        switch self {
        case .architecture: "square.stack.3d.up"
        case .models: "brain"
        case .authentication: "key"
        case .interface: "rectangle.3.group"
        case .platforms: "laptopcomputer.and.iphone"
        case .cloud: "cloud"
        case .quality: "checkmark.seal"
        case .integration: "arrow.triangle.branch"
        }
    }
}
