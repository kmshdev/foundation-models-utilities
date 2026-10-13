import EngineeringMCP

package enum ProviderOAuthNativeFactory {
    /// A stable local storage slot, not an authenticated provider user ID. Construction performs no I/O.
    package static func session(provider: MCPProvider) -> ProviderOAuthSession {
        let identity = try! MCPConnectionIdentity(provider: provider, accountID: "default")
        return ProviderOAuthSession(identity: identity, vault: ProviderOAuthKeychainVault())
    }

    @MainActor
    package static func browser(provider: MCPProvider) -> any ProviderOAuthBrowser {
        ProviderOAuthNativeBrowser(provider: provider)
    }
}
