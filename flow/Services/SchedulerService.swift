import Foundation

struct ScheduleEntry: Identifiable, Comparable, Hashable {
    let id = UUID()
    var hour: Int
    var minute: Int

    static func < (lhs: ScheduleEntry, rhs: ScheduleEntry) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }

    var displayTime: String {
        String(format: "%02d:%02d", hour, minute)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(hour)
        hasher.combine(minute)
    }

    static func == (lhs: ScheduleEntry, rhs: ScheduleEntry) -> Bool {
        lhs.hour == rhs.hour && lhs.minute == rhs.minute
    }
}

@Observable
final class SchedulerService {
    var isScheduled = false
    var entries: [ScheduleEntry] = SchedulerService.defaultEntries

    static let defaultEntries: [ScheduleEntry] = [
        ScheduleEntry(hour: 6, minute: 0),
        ScheduleEntry(hour: 12, minute: 0),
        ScheduleEntry(hour: 18, minute: 0),
    ]

    private let plistLabel = "com.berkaycit.flow.digest"

    private static let projectURL: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private var projectDir: String { Self.projectURL.path(percentEncoded: false) }
    private var runScriptPath: String { Self.projectURL.appending(path: "run_digests.sh").path(percentEncoded: false) }
    private var logsDir: String { Self.projectURL.appending(path: "logs").path(percentEncoded: false) }
    private var stdoutLogPath: String { Self.projectURL.appending(path: "logs/digest-stdout.log").path(percentEncoded: false) }
    private var stderrLogPath: String { Self.projectURL.appending(path: "logs/digest-stderr.log").path(percentEncoded: false) }

    private var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/LaunchAgents/\(plistLabel).plist")
    }

    init() {
        if loadScheduleFromPlist() {
            isScheduled = true
        }
    }

    private func userPath() -> String {
        let home = NSHomeDirectory()
        return [
            "\(home)/.local/bin",
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ].joined(separator: ":")
    }

    func install() throws {
        let intervals: [[String: Int]] = entries.sorted().map { entry in
            ["Hour": entry.hour, "Minute": entry.minute]
        }

        let plist: [String: Any] = [
            "Label": plistLabel,
            "ProgramArguments": ["/bin/bash", runScriptPath],
            "StartCalendarInterval": intervals,
            "StandardOutPath": stdoutLogPath,
            "StandardErrorPath": stderrLogPath,
            "WorkingDirectory": projectDir,
            "EnvironmentVariables": [
                "PATH": userPath(),
                "HOME": NSHomeDirectory(),
                "CLAUDECODE": "",
            ],
        ]

        try FileManager.default.createDirectory(
            atPath: logsDir,
            withIntermediateDirectories: true
        )

        let launchAgentsDir = plistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: plistURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", plistURL.path(percentEncoded: false)]
        try process.run()
        process.waitUntilExit()

        isScheduled = true
    }

    func uninstall() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", plistURL.path(percentEncoded: false)]
        try process.run()
        process.waitUntilExit()

        try? FileManager.default.removeItem(at: plistURL)
        isScheduled = false
    }

    func updateSchedule(with newEntries: [ScheduleEntry]) throws {
        entries = newEntries.sorted()
        if isScheduled {
            try uninstall()
            try install()
        }
    }

    @discardableResult
    private func loadScheduleFromPlist() -> Bool {
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return false }

        let loaded: [ScheduleEntry]

        if let intervals = plist["StartCalendarInterval"] as? [[String: Int]] {
            loaded = intervals.compactMap { dict in
                guard let hour = dict["Hour"], let minute = dict["Minute"] else { return nil }
                return ScheduleEntry(hour: hour, minute: minute)
            }
        } else if let interval = plist["StartCalendarInterval"] as? [String: Int] {
            let hour = interval["Hour"] ?? 9
            let minute = interval["Minute"] ?? 0
            loaded = [ScheduleEntry(hour: hour, minute: minute)]
        } else {
            return false
        }

        guard !loaded.isEmpty else { return false }
        entries = loaded.sorted()
        return true
    }
}
