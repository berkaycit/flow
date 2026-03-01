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
    private let projectDir = NSHomeDirectory() + "/Documents/GitHub/utility/flow"

    private var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/LaunchAgents/\(plistLabel).plist")
    }

    init() {
        if loadScheduleFromPlist() {
            isScheduled = true
        }
    }

    private var inlineScript: String {
        """
        cd "\(projectDir)" && \
        /usr/bin/python3 python-yt-digest/yt_digest.py & \
        /usr/bin/python3 python-hn-digest/hn_digest.py & \
        wait
        """
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
            "ProgramArguments": ["/bin/bash", "-c", inlineScript],
            "StartCalendarInterval": intervals,
            "StandardOutPath": projectDir + "/logs/digest-stdout.log",
            "StandardErrorPath": projectDir + "/logs/digest-stderr.log",
            "WorkingDirectory": projectDir,
            "EnvironmentVariables": [
                "PATH": userPath(),
                "HOME": NSHomeDirectory(),
                "CLAUDECODE": "",
            ],
        ]

        try FileManager.default.createDirectory(
            atPath: projectDir + "/logs",
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
