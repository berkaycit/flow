import SwiftUI

struct ContentView: View {
    @Environment(DigestViewModel.self) private var viewModel
    @Environment(ScriptRunnerService.self) private var runner
    @Environment(SchedulerService.self) private var scheduler
    @State private var showingRunner = false
    @State private var showingSchedule = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } content: {
            ItemListView()
                .navigationSplitViewColumnWidth(min: 280, ideal: 320)
        } detail: {
            if viewModel.selectedItem != nil {
                DetailView()
            } else {
                EmptyDetailView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingRunner = true
                } label: {
                    Label("Run Digests", systemImage: runner.isRunning ? "stop.fill" : "play.fill")
                }
                .help("Run digest scripts")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingSchedule.toggle()
                } label: {
                    Label("Schedule", systemImage: scheduler.isScheduled ? "clock.fill" : "clock")
                }
                .help("Configure digest schedule")
                .popover(isPresented: $showingSchedule) {
                    ScheduleSettingsView()
                }
            }
        }
        .sheet(isPresented: $showingRunner) {
            ScriptRunnerPanel()
        }
    }
}
