public protocol ExecutionPublicationObjectReading: Sendable {
    func snapshot(for record: ExecutionRecord) async throws -> ExecutionPublicationSnapshot
}
