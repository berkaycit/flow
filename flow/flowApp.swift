import SwiftUI

@main
struct flowApp: App {
    @State private var db: DatabaseService? = nil
    @State private var viewModel: DigestViewModel? = nil
    @State private var scriptRunner: ScriptRunnerService? = nil
    @State private var scheduler: SchedulerService? = nil
    @State private var initError: String? = nil

    var body: some Scene {
        WindowGroup {
            Group {
                if let viewModel, let db, let scriptRunner, let scheduler {
                    ContentView()
                        .environment(viewModel)
                        .environment(db)
                        .environment(scriptRunner)
                        .environment(scheduler)
                } else if let initError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.red)
                        Text("Failed to initialize database")
                            .font(.headline)
                        Text(initError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                } else {
                    ProgressView("Loading...")
                }
            }
            .task {
                do {
                    let database = try DatabaseService()
                    let vm = DigestViewModel(db: database)
                    let runner = ScriptRunnerService()
                    let sched = SchedulerService()
                    self.db = database
                    self.viewModel = vm
                    self.scriptRunner = runner
                    self.scheduler = sched
                    // Run cleanup in background after UI is showing
                    Task.detached { try? database.cleanupOld() }
                } catch {
                    self.initError = error.localizedDescription
                }
            }
        }
        .defaultSize(width: 1100, height: 700)
    }
}
