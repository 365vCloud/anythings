import AppKit
import Combine
import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    private static let storedRootsKey = "IndexedRootPaths"

    @Published var query = "" {
        didSet { updateResults() }
    }
    @Published var roots: [IndexedRoot] = [] {
        didSet { saveRoots() }
    }
    @Published var results: [SearchResult] = []
    @Published var selectedResultID: SearchResult.ID?
    @Published var isIndexing = false
    @Published var indexProgress = 0.0
    @Published var statusText = "Ready"
    @Published var matchesFullPath = false {
        didSet { updateResults() }
    }
    @Published var caseSensitive = false {
        didSet { updateResults() }
    }
    @Published var showingError = false
    @Published var errorMessage = ""

    private var index: [IndexedFile] = []
    private var indexTask: Task<Void, Never>?

    init() {
        let savedPaths = UserDefaults.standard.stringArray(forKey: Self.storedRootsKey) ?? []
        roots = savedPaths.map { IndexedRoot(url: URL(fileURLWithPath: $0, isDirectory: true)) }

        if !roots.isEmpty {
            reindex()
        }
    }

    var indexedItemCount: Int {
        index.count
    }

    func presentFolderPicker() {
        let panel = NSOpenPanel()
        panel.title = "Choose folders to index"
        panel.prompt = "Index"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true

        guard panel.runModal() == .OK else {
            return
        }

        let newRoots = panel.urls
            .map(\.standardizedFileURL)
            .filter { selectedURL in !roots.contains { $0.url == selectedURL } }
            .map(IndexedRoot.init)

        guard !newRoots.isEmpty else {
            return
        }

        roots.append(contentsOf: newRoots)
        reindex()
    }

    func removeRoot(_ root: IndexedRoot) {
        roots.removeAll { $0.id == root.id }
        index.removeAll { file in
            file.url.path == root.url.path || file.url.path.hasPrefix(root.url.path + "/")
        }
        updateResults()
        statusText = "\(index.count.formatted()) items indexed"
    }

    func reindex() {
        indexTask?.cancel()
        let rootURLs = roots.map(\.url)

        guard !rootURLs.isEmpty else {
            index = []
            results = []
            statusText = "Add a folder to begin"
            return
        }

        isIndexing = true
        indexProgress = 0
        statusText = "Preparing index..."

        indexTask = Task {
            do {
                let files = try await FileScanner.scan(urls: rootURLs) { [weak self] progress in
                    Task { @MainActor in
                        self?.indexProgress = progress.fractionCompleted
                        self?.statusText = progress.message
                    }
                }

                guard !Task.isCancelled else {
                    return
                }

                index = files
                isIndexing = false
                indexProgress = 1
                statusText = "\(files.count.formatted()) items indexed"
                updateResults()
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                isIndexing = false
                statusText = "Indexing failed"
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    func result(for ids: Set<SearchResult.ID>) -> SearchResult? {
        guard let id = ids.first else {
            return nil
        }

        return results.first { $0.id == id }
    }

    private func updateResults() {
        let search = SearchExpression(
            rawQuery: query,
            matchesFullPath: matchesFullPath,
            caseSensitive: caseSensitive
        )

        results = index.lazy
            .filter { search.matches($0) }
            .prefix(2_000)
            .map(SearchResult.init)
    }

    private func saveRoots() {
        UserDefaults.standard.set(roots.map(\.url.path), forKey: Self.storedRootsKey)
    }
}
