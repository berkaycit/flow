import SwiftUI

struct ScheduleSettingsView: View {
    @Environment(SchedulerService.self) private var scheduler
    @Environment(\.dismiss) private var dismiss

    @State private var draft: [ScheduleEntry] = []
    @State private var newHour = 9
    @State private var newMinute = 0
    @State private var errorMessage: String?

    private var hasDuplicate: Bool {
        draft.contains { $0.hour == newHour && $0.minute == newMinute }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            entryList
            Divider()
            addRow
            Divider()
            footer
        }
        .frame(width: 280)
        .onAppear {
            draft = scheduler.entries
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Schedule")
                .font(.headline)
            Spacer()
            Toggle(isOn: toggleBinding) {
                Text(scheduler.isScheduled ? "Active" : "Inactive")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding()
    }

    // MARK: - Entry List

    private var entryList: some View {
        List {
            ForEach(draft.sorted()) { entry in
                HStack {
                    Text(entry.displayTime)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Button {
                        draft.removeAll { $0.id == entry.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 140)
    }

    // MARK: - Add Row

    private var addRow: some View {
        HStack {
            Picker("Hour", selection: $newHour) {
                ForEach(0..<24, id: \.self) { h in
                    Text(String(format: "%02d", h)).tag(h)
                }
            }
            .labelsHidden()
            .frame(width: 60)

            Text(":")
                .font(.headline)

            Picker("Minute", selection: $newMinute) {
                ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { m in
                    Text(String(format: "%02d", m)).tag(m)
                }
            }
            .labelsHidden()
            .frame(width: 60)

            Button {
                let entry = ScheduleEntry(hour: newHour, minute: newMinute)
                if !hasDuplicate {
                    draft.append(entry)
                }
            } label: {
                Image(systemName: "plus.circle.fill")
            }
            .buttonStyle(.plain)
            .disabled(hasDuplicate)
        }
        .padding()
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 8) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Apply") {
                    do {
                        try scheduler.updateSchedule(with: draft)
                        errorMessage = nil
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.isEmpty)
            }
        }
        .padding()
    }

    // MARK: - Toggle Binding

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { scheduler.isScheduled },
            set: { newValue in
                do {
                    if newValue {
                        try scheduler.install()
                    } else {
                        try scheduler.uninstall()
                    }
                    errorMessage = nil
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        )
    }
}
