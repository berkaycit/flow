import Foundation
import SwiftUI

@Observable
final class NotebookLMService {
    var status: Status = .idle

    enum Status {
        case idle
        case settingUp
        case running
        case loggingIn
        case done(notebookURL: String)
        case authRequired
        case error(String)

        var isBusy: Bool {
            switch self {
            case .settingUp, .running, .loggingIn: return true
            default: return false
            }
        }

        var isSettingUp: Bool {
            if case .settingUp = self { return true }
            return false
        }
    }

    private let projectDir: String = {
        NSHomeDirectory() + "/flow"
    }()

    private var venvPython: String {
        projectDir + "/python-notebooklm/.venv/bin/python3"
    }

    private var setupScript: String {
        projectDir + "/python-notebooklm/setup.sh"
    }

    private let filteredEnv: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")
        return env
    }()

    private var venvVerified = false

    private var isVenvReady: Bool {
        if venvVerified { return true }
        let exists = FileManager.default.fileExists(atPath: venvPython)
        if exists { venvVerified = true }
        return exists
    }

    func login() {
        guard !status.isBusy else { return }
        status = .loggingIn

        let scriptPath = projectDir + "/python-notebooklm/login_notebooklm.py"

        Task.detached { [self] in
            if await ensureVenv() {
                await runLogin(scriptPath: scriptPath)
            }
        }
    }

    func openInNotebookLM(url: String, title: String, source: DigestSource) {
        guard !status.isBusy else { return }
        status = .running

        let scriptPath = projectDir + "/python-notebooklm/open_in_notebooklm.py"

        Task.detached { [self] in
            if await ensureVenv() {
                await runScript(scriptPath: scriptPath, url: url, title: title)
            }
        }
    }

    // MARK: - Venv Setup

    nonisolated private func ensureVenv() async -> Bool {
        if isVenvReady { return true }

        await MainActor.run { self.status = .settingUp }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [setupScript]
        process.currentDirectoryURL = URL(fileURLWithPath: projectDir)
        process.environment = filteredEnv

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        do {
            try process.run()

            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                process.terminationHandler = { _ in
                    continuation.resume()
                }
            }

            if process.terminationStatus == 0 {
                venvVerified = true
                return true
            } else {
                let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let errMsg = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Kurulum basarisiz."

                await MainActor.run { self.status = .error(errMsg) }
                return false
            }
        } catch {
            await MainActor.run { self.status = .error(error.localizedDescription) }
            return false
        }
    }

    // MARK: - Script Execution

    nonisolated private func runScript(scriptPath: String, url: String, title: String) async {
        await MainActor.run { self.status = .running }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: venvPython)
        process.arguments = [scriptPath, "--url", url, "--title", title]
        process.currentDirectoryURL = URL(fileURLWithPath: projectDir)
        process.environment = filteredEnv

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()

            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                process.terminationHandler = { _ in
                    continuation.resume()
                }
            }

            let exitCode = process.terminationStatus

            if exitCode == 0 {
                let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let notebookURL = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                await MainActor.run {
                    self.status = .done(notebookURL: notebookURL)
                    if let url = URL(string: notebookURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
            } else {
                await MainActor.run {
                    self.status = exitCode == 2 ? .authRequired : .error("Exit code \(exitCode)")
                }
            }
        } catch {
            await MainActor.run {
                self.status = .error(error.localizedDescription)
            }
        }
    }

    nonisolated private func runLogin(scriptPath: String) async {
        await MainActor.run { self.status = .loggingIn }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: venvPython)
        process.arguments = [scriptPath]
        process.currentDirectoryURL = URL(fileURLWithPath: projectDir)
        process.environment = filteredEnv

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        do {
            try process.run()

            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                process.terminationHandler = { _ in
                    continuation.resume()
                }
            }

            let exitCode = process.terminationStatus

            if exitCode == 0 {
                await MainActor.run { self.status = .idle }
            } else {
                let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let errMsg = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Cookie okuma basarisiz."

                await MainActor.run { self.status = .error(errMsg) }
            }
        } catch {
            await MainActor.run { self.status = .error(error.localizedDescription) }
        }
    }
}
