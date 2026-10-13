struct ProviderOAuthRegistrationResponse: Decodable, Sendable {
    let clientID: String
    let tokenEndpointAuthMethod: String?
    let redirectURIs: [String]?

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case tokenEndpointAuthMethod = "token_endpoint_auth_method"
        case redirectURIs = "redirect_uris"
    }
}
