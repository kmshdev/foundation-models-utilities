struct NativeCommandReceipt: Codable {
    let label: String
    let executable: String
    let arguments: [String]
    let processID: Int32
    let exitStatus: Int32?
    let timedOut: Bool
    let elapsedSeconds: Double
    let stdoutFile: String
    let stderrFile: String
}
