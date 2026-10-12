import EngineeringCore
import Foundation

struct ChatGPTIDTokenValidator: Sendable {
    let verifier: any ChatGPTJWTSignatureVerifying

    struct Identity: Sendable {
        let subject: String
        let issuer: String
        let email: String?
        let displayName: String?
    }

    func validate(_ token: String, jwks: Data, clientID: String, nonce: String?, now: Date) throws -> Identity {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, token.utf8.count < 64_000,
              let headerData = Self.decode(String(parts[0])), let payload = Self.decode(String(parts[1])),
              let signature = Self.decode(String(parts[2])) else { throw ChatGPTAuthenticationError.invalidIDToken }
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: headerData), header.alg == "RS256",
              header.crit == nil || header.crit?.isEmpty == true,
              let keys = try? decoder.decode(KeySet.self, from: jwks),
              let key = keys.keys.first(where: { $0.kid == header.kid && $0.kty == "RSA" && ($0.alg == nil || $0.alg == "RS256") && ($0.use == nil || $0.use == "sig") }),
              let modulus = Self.decode(key.n), let exponent = Self.decode(key.e), modulus.count >= 256,
              try verifier.verify(message: Data("\(parts[0]).\(parts[1])".utf8), signature: signature, modulus: modulus, exponent: exponent),
              let claims = try? decoder.decode(Claims.self, from: payload),
              claims.iss == "https://auth.openai.com", !claims.sub.isEmpty,
              claims.aud.contains(clientID), claims.aud.count == 1 || claims.azp == clientID,
              claims.exp > now.timeIntervalSince1970 - 5,
              claims.iat <= now.timeIntervalSince1970 + 5,
              claims.nbf == nil || claims.nbf! <= now.timeIntervalSince1970 + 5,
              nonce == nil || claims.nonce == nonce else { throw ChatGPTAuthenticationError.invalidIDToken }
        return Identity(subject: claims.sub, issuer: claims.iss, email: claims.email, displayName: claims.name)
    }

    static func decode(_ value: String) -> Data? {
        guard !value.isEmpty, value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
        let standard = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        return Data(base64Encoded: standard + String(repeating: "=", count: (4 - standard.count % 4) % 4))
    }

    private struct Header: Decodable { let alg: String; let kid: String; let crit: [String]? }
    private struct KeySet: Decodable { let keys: [Key] }
    private struct Key: Decodable { let kid: String; let kty: String; let n: String; let e: String; let alg: String?; let use: String? }
    private struct Claims: Decodable {
        let iss: String; let sub: String; let aud: [String]; let exp: Double; let iat: Double
        let nonce: String?; let email: String?; let name: String?; let azp: String?; let nbf: Double?
        enum CodingKeys: String, CodingKey { case iss, sub, aud, exp, iat, nonce, email, name, azp, nbf }
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            iss = try c.decode(String.self, forKey: .iss); sub = try c.decode(String.self, forKey: .sub)
            if let single = try? c.decode(String.self, forKey: .aud) { aud = [single] }
            else { aud = try c.decode([String].self, forKey: .aud) }
            exp = try c.decode(Double.self, forKey: .exp); iat = try c.decode(Double.self, forKey: .iat)
            nonce = try c.decodeIfPresent(String.self, forKey: .nonce); email = try c.decodeIfPresent(String.self, forKey: .email)
            name = try c.decodeIfPresent(String.self, forKey: .name); azp = try c.decodeIfPresent(String.self, forKey: .azp)
            nbf = try c.decodeIfPresent(Double.self, forKey: .nbf)
        }
    }
}
