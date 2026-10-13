import SwiftUI

/// Registration values are case-sensitive credentials, not prose.
struct ProviderCredentialFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        content
        #endif
    }
}
