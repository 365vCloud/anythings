import AppKit
import Combine
import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    private static let storedRootsKey = "IndexedRootPaths"

    @Published var query = "" {
        didSet {
            spotlightResults = []
            updateResults()
            scheduleSpotlightSearch()
        }
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
        didSet {
            spotlightResults = []
            updateResults()
            scheduleSpotlightSearch()
        }
    }
    @Published var caseSensitive = false {
        didSet {
            spotlightResults = []
            updateResults()
            scheduleSpotlightSearch()
        }
    }
    @Published var hidesSystemFiles = true {
        didSet {
            spotlightResults = []
            updateResults()
            scheduleSpotlightSearch()
        }
    }
    @Published var showingError = false
    @Published var errorMessage = ""

    private var index: [IndexedFile] = []
    private var spotlightResults: [IndexedFile] = []
    private var indexTask: Task<Void, Never>?
    private var spotlightTask: Task<Void, Never>?

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
            spotlightResults = []
            results = []
            statusText = "Add a folder to begin"
            return
        }

        isIndexing = true
        indexProgress = 0
        statusText = "Indexing files..."

        indexTask = Task {
            do {
                let files = try await FileScanner.scan(urls: rootURLs)

                guard !Task.isCancelled else {
                    return
                }

                index = files
                isIndexing = false
                indexProgress = 1
                statusText = "\(files.count.formatted()) items indexed"
                updateResults()
                scheduleSpotlightSearch()
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
            caseSensitive: caseSensitive,
            hidesSystemFiles: hidesSystemFiles
        )

        let searchableFiles = index + spotlightResults

        var nextResults: [SearchResult] = []
        var seenPaths = Set<String>()

        for file in searchableFiles {
            guard seenPaths.insert(file.url.path).inserted,
                  search.matches(file) else {
                continue
            }

            nextResults.append(SearchResult(file: file))

            if nextResults.count >= 2_000 {
                break
            }
        }

        results = nextResults
    }

    private func scheduleSpotlightSearch() {
        spotlightTask?.cancel()

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let rootURLs = roots.map(\.url)

        guard !trimmedQuery.isEmpty, !rootURLs.isEmpty else {
            return
        }

        let requestMatchesFullPath = matchesFullPath
        let requestCaseSensitive = caseSensitive

        spotlightTask = Task {
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
                statusText = isIndexing ? "Indexing files and searching..." : "Searching..."

                let files = try await SpotlightSearch.search(
                    query: trimmedQuery,
                    roots: rootURLs,
                    matchesFullPath: requestMatchesFullPath,
                    caseSensitive: requestCaseSensitive
                )

                guard !Task.isCancelled,
                      query.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedQuery,
                      matchesFullPath == requestMatchesFullPath,
                      caseSensitive == requestCaseSensitive else {
                    return
                }

                spotlightResults = files
                updateResults()

                if !isIndexing {
                    statusText = results.isEmpty ? "No matches found" : "\(results.count.formatted()) matches"
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                errorMessage = error.localizedDescription
                showingError = true
                if !isIndexing {
                    statusText = "Search failed"
                }
            }
        }
    }

    private func saveRoots() {
        UserDefaults.standard.set(roots.map(\.url.path), forKey: Self.storedRootsKey)
    }
}
