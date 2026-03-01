import SwiftUI

struct ScriptRunnerPanel: View {
    @Environment(ScriptRunnerService.self) private var runner
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Run Digests")
                    .font(.headline)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Status
            HStack(spacing: 24) {
                statusBadge(label: "YouTube", status: runner.ytStatus)
                statusBadge(label: "Hacker News", status: runner.hnStatus)
            }
            .padding()

            Divider()

            // Log stream
            LogStreamView(lines: runner.logLines)

            Divider()

            // Actions
            HStack {
                Spacer()
                if runner.isRunning {
                    Button("Cancel") {
                        runner.cancel()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Run Both") {
                        runner.runBothDigests()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(width: 600, height: 450)
    }

    private func statusBadge(label: String, status: ScriptRunnerService.RunStatus) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor(status))
                .frame(width: 8, height: 8)
            Text(label)
                .font(.subheadline.bold())
            Text(status.label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func statusColor(_ status: ScriptRunnerService.RunStatus) -> Color {
        switch status {
        case .idle: .gray
        case .running: .orange
        case .done: .green
        case .error: .red
        }
    }
}
