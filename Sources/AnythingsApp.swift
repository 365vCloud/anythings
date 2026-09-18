import SwiftUI

@main
struct AnythingsApp: App {
    @StateObject private var viewModel = SearchViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 920, minHeight: 620)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add Folder...") {
                    viewModel.presentFolderPicker()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Re-index") {
                    viewModel.reindex()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(viewModel.roots.isEmpty || viewModel.isIndexing)
            }

            CommandMenu("Selection") {
                Button("Select All") {
                    viewModel.selectAll()
                }
                .keyboardShortcut("a", modifiers: [.command])
                .disabled(viewModel.results.isEmpty)

                Button("Deselect All") {
                    viewModel.deselectAll()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(viewModel.selectedResultIDs.isEmpty)

                Button("Invert Selection") {
                    viewModel.invertSelection()
                }
                .keyboardShortcut("i", modifiers: [.command])
                .disabled(viewModel.results.isEmpty)

                Divider()

                Button("Copy to Folder...") {
                    viewModel.copyResults(viewModel.selectedResults)
                }
                .disabled(viewModel.selectedResultIDs.isEmpty)

                Button("Move to Folder...") {
                    viewModel.moveResults(viewModel.selectedResults)
                }
                .disabled(viewModel.selectedResultIDs.isEmpty)

                Button("Open Containing Folder") {
                    viewModel.openContainingFolders(viewModel.selectedResults)
                }
                .disabled(viewModel.selectedResultIDs.isEmpty)
            }
        }
    }
}
