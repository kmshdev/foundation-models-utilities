import EngineeringMCP
import Foundation
@testable import StudioWorkflows
@testable import StudioServices

@MainActor
struct ProviderCheckHarness {
    let identity: MCPConnectionIdentity
    let vault: ProviderCheckVault
    let http: ProviderCheckHTTP
    let browser: ProviderCheckBrowser
    let validator: ProviderCheckValidator
    let session: ProviderOAuthSession
    let connection: ProviderMCPConnection

    init(provider: MCPProvider, accountID: String = "isolated-fixture",
         vault: ProviderCheckVault = .init(), http: ProviderCheckHTTP = .init()) throws {
        identity = try MCPConnectionIdentity(provider: provider, accountID: accountID)
        self.vault = vault
        self.http = http
        browser = ProviderCheckBrowser()
        validator = ProviderCheckValidator()
        session = ProviderOAuthSession(identity: identity, vault: vault, transport: http,
                                       cryptography: ProviderCheckCryptography())
        let validation = validator
        connection = ProviderMCPConnection(provider: provider, session: session, browser: browser,
            validateCapabilities: { session, receipt, version, limits in
                await validation.validate(session, receipt: receipt, appVersion: version, limits: limits)
            })
    }
}
