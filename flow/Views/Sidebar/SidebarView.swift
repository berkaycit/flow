import SwiftUI

struct SidebarView: View {
    @Environment(DigestViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        VStack(spacing: 0) {
            // Source picker
            Picker("", selection: $vm.selectedSource) {
                ForEach(DigestSource.allCases) { source in
                    Label(source.displayName, systemImage: source.iconName)
                        .tag(source)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .padding()
            .disabled(viewModel.showingNotebooks)
            .onChange(of: viewModel.selectedSource) {
                viewModel.sourceChanged()
            }

            // Notebooks button
            Button {
                viewModel.toggleNotebooks()
            } label: {
                Label("Notebooks", systemImage: "book.and.wrench.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        viewModel.showingNotebooks
                            ? Color.accentColor.opacity(0.15)
                            : Color.clear
                    )
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .foregroundColor(viewModel.showingNotebooks ? .accentColor : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Divider()

            if !viewModel.showingNotebooks {
                // Calendar
                CalendarView()
            }

            Spacer()
        }
        .navigationTitle("Flow")
    }
}
