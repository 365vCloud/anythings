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
        }
    }
}
