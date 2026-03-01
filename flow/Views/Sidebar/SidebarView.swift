import SwiftUI

struct SidebarView: View {
    @Environment(DigestViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        VStack(spacing: 0) {
            // Source picker
            Picker("Source", selection: $vm.selectedSource) {
                ForEach(DigestSource.allCases) { source in
                    Label(source.displayName, systemImage: source.iconName)
                        .tag(source)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            .onChange(of: viewModel.selectedSource) {
                viewModel.sourceChanged()
            }

            Divider()

            // Calendar
            CalendarView()

            Spacer()
        }
        .navigationTitle("Flow")
    }
}
