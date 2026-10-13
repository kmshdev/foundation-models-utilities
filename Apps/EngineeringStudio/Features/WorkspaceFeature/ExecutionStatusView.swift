import StudioWorkflows
import StudioServices
import StudioUI
import EngineeringCore
import SwiftUI

/// Status is taken from an observed receipt; nil represents an assignment without delivery.
struct ExecutionStatusView: View {
    let status: ExecutionRecord.Status?

    var body: some View {
        Label(Self.title(for: status), systemImage: symbol)
            .foregroundStyle(color)
            .accessibilityElement(children: .combine)
    }

    static func title(for status: ExecutionRecord.Status?) -> String {
        switch status {
        case nil: "Planned"
        case .queued: "Queued"
        case .starting: "Starting"
        case .running: "Running"
        case .verifying: "Checking scope"
        case .completed: "Completed"
        case .blocked: "Blocked"
        case .cancelled: "Canceled"
        case .interrupted: "Interrupted"
        }
    }

    private var symbol: String {
        switch status {
        case nil: "circle.dashed"
        case .queued: "clock"
        case .starting, .running: "arrow.triangle.2.circlepath"
        case .verifying: "checkmark.shield"
        case .completed: "checkmark.circle.fill"
        case .blocked: "exclamationmark.circle"
        case .cancelled: "stop.circle"
        case .interrupted: "pause.circle"
        }
    }

    private var color: Color {
        switch status {
        case .starting, .running, .verifying: .blue
        case .completed: .green
        case .blocked, .interrupted: .orange
        default: .secondary
        }
    }
}
