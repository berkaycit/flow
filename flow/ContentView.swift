import SwiftUI

struct ContentView: View {
    @Environment(DigestViewModel.self) private var viewModel
    @Environment(ScriptRunnerService.self) private var runner
    @State private var showingRunner = false

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
        }
        .sheet(isPresented: $showingRunner) {
            ScriptRunnerPanel()
        }
    }
}
