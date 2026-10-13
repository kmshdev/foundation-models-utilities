import StudioWorkflows
import StudioServices
import StudioUI
import EngineeringCore
import SwiftUI

/// Shows an observed command and its exit code without inferring a test count.
struct ExecutionCommandView: View {
    let receipt: ExecutionCommandReceipt

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text("Command").font(StudioTypography.label)
                Spacer(minLength: StudioSpacing.small)
                Label(exitDescription, systemImage: exitSymbol).font(StudioTypography.caption).foregroundStyle(exitColor)
            }.accessibilityElement(children: .combine)
            Text(receipt.command).font(.callout.monospaced()).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !receipt.workingDirectory.isEmpty {
                Label(receipt.workingDirectory, systemImage: "folder")
                    .font(StudioTypography.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if !receipt.output.isEmpty {
                DisclosureGroup("Output") {
                    Text(receipt.output).font(.caption.monospaced()).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .topLeading).padding(.top, StudioSpacing.small)
                        .accessibilityLabel("Command output")
                }.font(StudioTypography.secondary)
            }
        }
        .padding(StudioSpacing.medium)
        .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: StudioRadius.control))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Execution command")
    }

    private var exitDescription: String {
        if let code = receipt.exitCode { return "Exit \(code)" }
        switch receipt.status {
        case "inProgress", "in_progress", "running": return "Running"
        case "failed": return "Failed · No exit code"
        default: return "Exit not reported"
        }
    }
    private var exitSymbol: String {
        if let code = receipt.exitCode { return code == 0 ? "checkmark.circle" : "exclamationmark.circle" }
        return "clock"
    }
    private var exitColor: Color {
        if let code = receipt.exitCode { return code == 0 ? .green : .red }
        return receipt.status == "failed" ? .red : .secondary
    }
}
