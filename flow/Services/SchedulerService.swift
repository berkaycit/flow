import Foundation

@Observable
final class SchedulerService {
    var isScheduled = false
    var scheduledHour: Int = 9
    var scheduledMinute: Int = 0

    private let plistLabel = "com.berkaycit.flow.digest"
    private let projectDir = NSHomeDirectory() + "/Documents/GitHub/utility/flow"

    private var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/LaunchAgents/\(plistLabel).plist")
    }

    private var wrapperScriptURL: URL {
        URL(fileURLWithPath: projectDir + "/run_digests.sh")
    }

    init() {
        if loadScheduleFromPlist() {
            isScheduled = true
        }
    }

    func install() throws {
        // Ensure wrapper script exists
        try ensureWrapperScript()

        let plist: [String: Any] = [
            "Label": plistLabel,
            "ProgramArguments": ["/bin/bash", wrapperScriptURL.path(percentEncoded: false)],
            "StartCalendarInterval": [
                "Hour": scheduledHour,
                "Minute": scheduledMinute
            ],
            "StandardOutPath": projectDir + "/logs/digest-stdout.log",
            "StandardErrorPath": projectDir + "/logs/digest-stderr.log",
            "WorkingDirectory": projectDir
        ]

        // Create logs dir
        try FileManager.default.createDirectory(
            atPath: projectDir + "/logs",
            withIntermediateDirectories: true
        )

        // Create LaunchAgents dir if needed
        let launchAgentsDir = plistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)

        // Write plist
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: plistURL)

        // Load the agent
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", plistURL.path(percentEncoded: false)]
        try process.run()
        process.waitUntilExit()

        isScheduled = true
    }

    func uninstall() throws {
        // Unload the agent
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", plistURL.path(percentEncoded: false)]
        try process.run()
        process.waitUntilExit()

        // Remove plist
        try? FileManager.default.removeItem(at: plistURL)

        isScheduled = false
    }

    private func ensureWrapperScript() throws {
        let script = """
        #!/bin/bash
        cd "\(projectDir)"
        /usr/bin/env python3 python-yt-digest/yt_digest.py &
        /usr/bin/env python3 python-hn-digest/hn_digest.py &
        wait
        """
        try script.write(to: wrapperScriptURL, atomically: true, encoding: .utf8)

        // Make executable
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["+x", wrapperScriptURL.path(percentEncoded: false)]
        try process.run()
        process.waitUntilExit()
    }

    @discardableResult
    private func loadScheduleFromPlist() -> Bool {
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let interval = plist["StartCalendarInterval"] as? [String: Int] else { return false }
        scheduledHour = interval["Hour"] ?? 9
        scheduledMinute = interval["Minute"] ?? 0
        return true
    }
}
