import EngineeringMCP
import Foundation
@testable import StudioWorkflows
@testable import StudioServices

/// Simulates an observed MCP initialization/catalog only at the workflow seam.
/// Transport-level MCP behavior is covered separately by the real SDK fixtures.
actor ProviderCheckValidator {
    let validationGate = ProviderCheckGate()
    private(set) var validationCount = 0

    func validate(_ session: ProviderOAuthSession, receipt: ProviderOAuthAuthorizationReceipt,
                  appVersion: String, limits: MCPClientLimits) async -> ProviderMCPReceipt {
        validationCount += 1
        await validationGate.waitIfSuspended()
        return .init(identity: receipt.identity, serverName: "Isolated fixture MCP", serverVersion: "fixture",
                     protocolVersion: "2025-11-25", toolCount: 2, verifiedAt: Date())
    }
}
