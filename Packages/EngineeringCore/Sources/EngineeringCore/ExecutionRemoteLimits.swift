public enum ExecutionRemoteLimits {
    public static let maximumHeaderBytes = 16_384
    public static let maximumBodyBytes = 262_144
    public static let maximumResponseBytes = 2_097_152
    public static let maximumConnections = 8
    public static let requestTimeoutSeconds = 20
    /// Publication can require several GitHub object/ref/PR operations; its authenticated budget remains bounded.
    public static let publicationTimeoutSeconds = 120

    public static func validPairingToken(_ value: String) -> Bool {
        (32...256).contains(value.utf8.count) && value.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }
    }
}
