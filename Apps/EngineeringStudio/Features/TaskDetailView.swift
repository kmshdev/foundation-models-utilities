import EngineeringCore
import SwiftUI

struct TaskDetailView: View {
    let task: WorkTask
    var issueBinding: TaskIssueBinding? = nil
    var record: ExecutionRecord? = nil
    var runtime: DeveloperRuntimeConnection? = nil
    @State private var publicationError: String?
    @State private var isPublishing = false
    @State private var showsRequirements = false
    @State private var isActing = false
    @State private var cancelRequested = false
    @State private var actionError: String?
    @State private var actionGeneration = UUID()

    private var matchingRecord: ExecutionRecord? { record?.task == task ? record : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                Divider().opacity(0.6)
                if let binding = issueBinding, let url = binding.webURL {
                    Link(binding.identifier ?? "Open Linear issue", destination: url)
                    if binding.publishedTask != task {
                        Text("This task has changed since its last publication.")
                            .font(StudioTypography.caption).foregroundStyle(.secondary)
                    }
                }
                if record != nil, matchingRecord == nil {
                    Label("Previous execution belongs to an earlier assignment.", systemImage: "clock.arrow.circlepath")
                        .font(StudioTypography.secondary).foregroundStyle(.secondary)
                }
                detailSection("Scope", symbol: "doc.text") {
                    ForEach(task.paths, id: \.self) { path in
                        Text(path).font(StudioTypography.body).foregroundStyle(.secondary).lineSpacing(6)
                            .textSelection(.enabled).help(path)
                    }
                }
                Divider().opacity(0.6)
                handoff
                Divider().opacity(0.6)
                if let record = matchingRecord {
                    execution(record)
                    publication(record)
                } else {
                    detailSection("Execution", symbol: "terminal") {
                        Text("Not dispatched").font(StudioTypography.body)
                        Text("Run the assignment plan to receive developer results here.")
                            .font(StudioTypography.secondary).foregroundStyle(.secondary)
                    }
                }
                acceptance
                DisclosureGroup("Handoff context") {
                    Text(task.handoff).font(StudioTypography.body).lineSpacing(4).textSelection(.enabled)
                        .padding(.top, StudioSpacing.small)
                }.font(StudioTypography.secondary).foregroundStyle(.secondary)
            }.padding(24).padding(.top, 8).frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Task details")
        .onChange(of: task) { _, _ in
            actionGeneration = UUID(); isActing = false; cancelRequested = false; actionError = nil; publicationError = nil; isPublishing = false
        }
        .onChange(of: matchingRecord?.status) { _, status in
            if status != .running { cancelRequested = false }
        }
    }

    private var header: some View {
        HStack(spacing: StudioSpacing.standard) {
            SymbolBadge(symbol: task.owner.symbol, size: 62)
            VStack(alignment: .leading, spacing: StudioSpacing.small) {
                Text(task.title).font(StudioTypography.title).accessibilityAddTraits(.isHeader)
                ViewThatFits(in: .horizontal) {
                    HStack { ExecutionStatusView(status: matchingRecord?.status); Text("· \(task.owner.displayName)").foregroundStyle(.secondary) }
                    VStack(alignment: .leading, spacing: 4) {
                        ExecutionStatusView(status: matchingRecord?.status)
                        Text(task.owner.displayName).foregroundStyle(.secondary)
                    }
                }.font(StudioTypography.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var handoff: some View {
        detailSection("Handoff", symbol: "arrow.triangle.branch") {
            Text(task.handoff.components(separatedBy: ". ").first ?? task.handoff)
                .font(StudioTypography.body).lineSpacing(5).textSelection(.enabled)
            if let record = matchingRecord, !record.receivedHandoffs.isEmpty {
                ForEach(record.receivedHandoffs) { key in
                    Label("Received from \(key.taskID)", systemImage: "arrow.down.right")
                        .font(StudioTypography.secondary).foregroundStyle(.secondary)
                }
            } else if matchingRecord != nil, !task.dependencies.isEmpty {
                Text("Dependency context has not been received.").font(StudioTypography.secondary).foregroundStyle(.secondary)
            }
            if !task.dependencies.isEmpty {
                Text("Depends on: \(task.dependencies.joined(separator: ", "))")
                    .font(StudioTypography.secondary).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func execution(_ record: ExecutionRecord) -> some View {
        detailSection("Developer result", symbol: "terminal") {
            if !record.summary.isEmpty {
                Text(record.summary).font(StudioTypography.body).lineSpacing(5).textSelection(.enabled)
            } else {
                Text("Waiting for developer progress.").font(StudioTypography.secondary).foregroundStyle(.secondary)
            }
            Text("Updated \(record.updatedAt, format: .dateTime.hour().minute())")
                .font(StudioTypography.caption).foregroundStyle(.secondary)
            if let blocker = record.blocker, !blocker.isEmpty {
                Label(blocker, systemImage: "exclamationmark.circle")
                    .font(StudioTypography.body).foregroundStyle(.orange).textSelection(.enabled)
            }
        }
        if let worktree = record.worktree {
            detailSection("Changes", symbol: "arrow.triangle.branch") {
                LabeledContent("Branch") { Text(worktree.branch).textSelection(.enabled) }
                    .font(StudioTypography.secondary)
                if let commit = record.commitSHA {
                    LabeledContent("Commit") { Text(String(commit.prefix(12))).monospaced().textSelection(.enabled).help(commit) }
                        .font(StudioTypography.secondary)
                }
                if !record.changedPaths.isEmpty {
                    DisclosureGroup("Changed files") {
                        ForEach(record.changedPaths, id: \.self) { path in
                            Text(path).font(.caption.monospaced()).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                        }
                    }.font(StudioTypography.secondary)
                }
            }
        }
        detailSection("Commands", symbol: "checkmark.seal") {
            if record.commands.isEmpty {
                Text("No command results reported.").font(StudioTypography.secondary).foregroundStyle(.secondary)
            } else {
                ForEach(record.commands) { receipt in ExecutionCommandView(receipt: receipt) }
            }
        }
        executionControls(record)
    }

    @ViewBuilder private func publication(_ record: ExecutionRecord) -> some View {
        if let runtime {
            if let receipt = runtime.state.pullRequests.first(where: { $0.executionID == record.id }) {
                detailSection("Pull request", symbol: "arrow.triangle.pull") {
                    Link("Open PR #\(receipt.pullRequestNumber)", destination: receipt.url)
                        .buttonStyle(.glass).controlSize(.large)
                    Text("Created as draft · \(receipt.baseBranch)").font(StudioTypography.secondary).foregroundStyle(.secondary)
                    Text("GitHub commit \(receipt.remoteHeadSHA.prefix(12))")
                        .font(.caption.monospaced()).textSelection(.enabled)
                }
            } else if record.status == .completed, record.commitSHA != nil {
                Button("Create Draft PR", systemImage: "arrow.triangle.pull") {
                    guard !isPublishing else { return }
                    isPublishing = true; publicationError = nil
                    let expected = actionGeneration
                    Task {
                        defer { if actionGeneration == expected { isPublishing = false } }
                        do { _ = try await runtime.publish(record.key) }
                        catch { if actionGeneration == expected { publicationError = error.localizedDescription } }
                    }
                }.buttonStyle(.glassProminent).tint(.blue).disabled(isPublishing || !runtime.hasRuntime)
            }
            if isPublishing { ProgressView("Publishing verified changes…") }
            if let error = publicationError ?? runtime.publicationErrors[record.key] { Text(error).foregroundStyle(.red).textSelection(.enabled) }
        }
    }

    private var acceptance: some View {
        DisclosureGroup("Acceptance criteria", isExpanded: $showsRequirements) {
            VStack(alignment: .leading, spacing: StudioSpacing.small) {
                if matchingRecord?.result != nil {
                    Text("Reported by the developer. Review its commands and changes above.")
                        .font(StudioTypography.caption).foregroundStyle(.secondary)
                }
                ForEach(task.acceptance, id: \.self) { criterion in
                    let reported = matchingRecord?.result?.acceptedCriteria.contains(criterion) == true
                    Label(criterion, systemImage: reported ? "checkmark.circle" : "circle")
                        .foregroundStyle(reported ? Color.green : Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("\(criterion), \(reported ? "developer reported complete" : "not reported complete")")
                }
            }.font(StudioTypography.body).padding(.top, StudioSpacing.medium)
        }.font(StudioTypography.secondary)
    }

    @ViewBuilder
    private func executionControls(_ record: ExecutionRecord) -> some View {
        if let runtime {
            GlassEffectContainer(spacing: StudioSpacing.medium) {
                HStack(spacing: StudioSpacing.medium) {
                    if canCancel(record) {
                        Button {
                            perform(record: record, runtime: runtime, cancel: true)
                        } label: {
                            Label(cancelRequested ? "Cancel requested" : "Cancel task", systemImage: "stop.fill")
                                .frame(maxWidth: .infinity, minHeight: 34)
                        }.buttonStyle(.glass).tint(.orange)
                            .disabled(isActing || cancelRequested || !runtime.state.connected)
                            .accessibilityHint("Interrupt this developer and retain its work and results")
                    }
                    if canResume(record) {
                        Button {
                            perform(record: record, runtime: runtime, cancel: false)
                        } label: {
                            Label("Resume task", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 34)
                        }.buttonStyle(.glassProminent).tint(.green)
                            .disabled(isActing || !runtime.state.connected)
                            .accessibilityHint("Continue the saved developer conversation and worktree")
                    }
                }.font(StudioTypography.label).controlSize(.large)
                    .buttonBorderShape(.roundedRectangle(radius: 13))
            }
            if isActing { ProgressView("Contacting developer…").font(StudioTypography.caption) }
            if let actionError { Text(actionError).font(StudioTypography.secondary).foregroundStyle(.red).textSelection(.enabled) }
        }
    }

    private func canCancel(_ record: ExecutionRecord) -> Bool {
        record.status == .queued || (record.status == .running && record.threadID != nil && record.turnID != nil)
    }
    private func canResume(_ record: ExecutionRecord) -> Bool {
        ExecutionDeveloperCoordinator.canRequeueWithoutDelivery(record) ||
            ([.blocked, .cancelled, .interrupted].contains(record.status) && record.threadID != nil && record.worktree != nil)
    }
    private func perform(record: ExecutionRecord, runtime: DeveloperRuntimeConnection, cancel: Bool) {
        guard !isActing else { return }
        isActing = true; actionError = nil
        let expected = actionGeneration
        Task { @MainActor in
            defer { if actionGeneration == expected { isActing = false } }
            do {
                if cancel { _ = try await runtime.cancel(record.key) }
                else { _ = try await runtime.resume(record.key) }
                guard actionGeneration == expected else { return }
                if cancel, runtime.record(outcomeID: record.key.outcomeID, taskID: record.key.taskID)?.status == .running {
                    cancelRequested = true
                }
            } catch {
                if actionGeneration == expected { actionError = error.localizedDescription }
            }
        }
    }

    private func detailSection<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: StudioSpacing.standard) {
            SymbolBadge(symbol: symbol, size: 36)
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(StudioTypography.heading).accessibilityAddTraits(.isHeader)
                content()
            }.padding(.top, 3).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
