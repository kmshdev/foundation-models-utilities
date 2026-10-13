import EngineeringServices
import Foundation
import Security
import EngineeringCore

package struct ChatGPTAppleSignatureVerifier: ChatGPTJWTSignatureVerifying {
    package func verify(message: Data, signature: Data, modulus: Data, exponent: Data) throws -> Bool {
        guard modulus.count >= 256, modulus.count <= 1_024, !exponent.isEmpty, exponent.count <= 8 else { return false }
        // SecKey expects an ASN.1 DER PKCS#1 public key: SEQUENCE(INTEGER n, INTEGER e).
        let body = integer(modulus) + integer(exponent)
        let encoded = Data([0x30]) + length(body.count) + body
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                                         kSecAttrKeyClass as String: kSecAttrKeyClassPublic]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(encoded as CFData, attributes as CFDictionary, &error),
              SecKeyIsAlgorithmSupported(key, .verify, .rsaSignatureMessagePKCS1v15SHA256) else { return false }
        return SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA256,
                                     message as CFData, signature as CFData, &error)
    }

    private func integer(_ value: Data) -> Data {
        var bytes = Array(value.drop(while: { $0 == 0 }))
        if bytes.isEmpty { bytes = [0] }
        if bytes[0] & 0x80 != 0 { bytes.insert(0, at: 0) }
        return Data([0x02]) + length(bytes.count) + Data(bytes)
    }

    private func length(_ count: Int) -> Data {
        if count < 128 { return Data([UInt8(count)]) }
        var remaining = count; var bytes: [UInt8] = []
        while remaining > 0 { bytes.insert(UInt8(remaining & 0xff), at: 0); remaining >>= 8 }
        return Data([0x80 | UInt8(bytes.count)]) + Data(bytes)
    }
}
