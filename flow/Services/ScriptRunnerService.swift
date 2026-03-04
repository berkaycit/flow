import Foundation

@Observable
final class ScriptRunnerService {
    var isRunning = false
    var logLines: [LogLine] = []
    var ytStatus: RunStatus = .idle
    var hnStatus: RunStatus = .idle
    var redditStatus: RunStatus = .idle

    private var processes: [Process] = []
    private let maxLogLines = 1000
    private var nextLogId = 0

    enum RunStatus: Sendable {
        case idle
        case running
        case done
        case error(String)

        var label: String {
            switch self {
            case .idle: "Idle"
            case .running: "Running..."
            case .done: "Done"
            case .error(let msg): "Error: \(msg)"
            }
        }
    }

    private let projectDir: String = {
        NSHomeDirectory() + "/flow"
    }()

    private let filteredEnv: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")
        return env
    }()

    func runAllDigests() {
        guard !isRunning else { return }
        isRunning = true
        logLines = []
        nextLogId = 0
        processes = []
        ytStatus = .running
        hnStatus = .running
        redditStatus = .running

        Task.detached { [self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.runScript(name: "yt_digest.py", path: "python-yt-digest/yt_digest.py", source: .yt) }
                group.addTask { await self.runScript(name: "hn_digest.py", path: "python-hn-digest/hn_digest.py", source: .hn) }
                group.addTask { await self.runScript(name: "reddit_digest.py", path: "python-reddit-digest/reddit_digest.py", source: .reddit) }
            }
            await MainActor.run {
                self.isRunning = false
            }
        }
    }

    func cancel() {
        for process in processes {
            if process.isRunning {
                process.terminate()
            }
        }
        processes.removeAll()
        isRunning = false
        if case .running = ytStatus { ytStatus = .idle }
        if case .running = hnStatus { hnStatus = .idle }
        if case .running = redditStatus { redditStatus = .idle }
        appendLog("[Cancelled]")
    }

    nonisolated private func runScript(name: String, path: String, source: DigestSource) async {
        let fullPath = projectDir + "/" + path

        await MainActor.run {
            self.appendLog("[\(name)] Starting...")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", fullPath]
        process.currentDirectoryURL = URL(fileURLWithPath: projectDir)
        process.environment = filteredEnv

        let stderrPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = stdoutPipe

        await MainActor.run {
            processes.append(process)
        }

        // Stream stderr — dispatch to MainActor for thread safety
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                Task { @MainActor [weak self] in
                    self?.appendLog("[\(name)] \(trimmed)")
                }
            }
        }

        defer {
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
        }

        do {
            try process.run()

            // Yield the cooperative thread instead of blocking with waitUntilExit()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                process.terminationHandler = { _ in
                    continuation.resume()
                }
            }

            let status = process.terminationStatus
            await MainActor.run { [self] in
                if status == 0 {
                    setStatus(.done, for: source)
                    appendLog("[\(name)] Completed successfully.")
                } else {
                    let msg = "Exit code \(status)"
                    setStatus(.error(msg), for: source)
                    appendLog("[\(name)] Failed with \(msg)")
                }
            }
        } catch {
            await MainActor.run { [self] in
                let msg = error.localizedDescription
                setStatus(.error(msg), for: source)
                appendLog("[\(name)] Error: \(msg)")
            }
        }
    }

    private func setStatus(_ status: RunStatus, for source: DigestSource) {
        switch source {
        case .yt: ytStatus = status
        case .hn: hnStatus = status
        case .reddit: redditStatus = status
        }
    }

    private func appendLog(_ line: String) {
        let logLine = LogLine(id: nextLogId, text: line)
        nextLogId += 1
        logLines.append(logLine)
        if logLines.count > maxLogLines {
            logLines.removeSubrange(0..<(logLines.count - maxLogLines))
        }
    }
}
