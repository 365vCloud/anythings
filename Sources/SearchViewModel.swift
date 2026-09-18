import AppKit
import Combine
import Foundation

enum ResultViewMode: String, CaseIterable, Identifiable {
    case table
    case largeIcons
    case smallIcons

    var id: String { rawValue }

    var label: String {
        switch self {
        case .table: return "Details"
        case .largeIcons: return "Large Icons"
        case .smallIcons: return "Small Icons"
        }
    }

    var systemImage: String {
        switch self {
        case .table: return "list.bullet"
        case .largeIcons: return "square.grid.2x2"
        case .smallIcons: return "square.grid.3x3"
        }
    }
}

enum SortField: String, CaseIterable, Identifiable, Sendable {
    case name
    case path
    case modified
    case size

    var id: String { rawValue }

    var label: String {
        switch self {
        case .name: return "Name"
        case .path: return "Path"
        case .modified: return "Date Modified"
        case .size: return "Size"
        }
    }
}

enum FileTransferAction {
    case copy
    case move
}

@MainActor
final class SearchViewModel: ObservableObject {
    private static let storedRootsKey = "IndexedRootPaths"

    @Published var query = "" {
        didSet {
            spotlightResults = []
            scheduleUpdateResults(debounce: true)
            scheduleSpotlightSearch()
        }
    }
    @Published var roots: [IndexedRoot] = [] {
        didSet { saveRoots() }
    }
    @Published var results: [SearchResult] = []
    @Published var selectedResultIDs: Set<SearchResult.ID> = []
    @Published var isIndexing = false
    @Published var indexProgress = 0.0
    @Published var statusText = "Ready"
    @Published var matchesFullPath = false {
        didSet {
            spotlightResults = []
            scheduleUpdateResults(debounce: false)
            scheduleSpotlightSearch()
        }
    }
    @Published var caseSensitive = false {
        didSet {
            spotlightResults = []
            scheduleUpdateResults(debounce: false)
            scheduleSpotlightSearch()
        }
    }
    @Published var hidesSystemFiles = true {
        didSet {
            spotlightResults = []
            scheduleUpdateResults(debounce: false)
            scheduleSpotlightSearch()
        }
    }
    @Published var selectedFileTypeCategoryIDs: Set<String> = [] {
        didSet {
            spotlightResults = []
            scheduleUpdateResults(debounce: false)
            scheduleSpotlightSearch()
        }
    }
    @Published var customExtensionsText = "" {
        didSet {
            spotlightResults = []
            scheduleUpdateResults(debounce: true)
            scheduleSpotlightSearch()
        }
    }
    @Published var viewMode: ResultViewMode = .table
    @Published var sortField: SortField = .name {
        didSet { scheduleUpdateResults(debounce: false) }
    }
    @Published var sortAscending = true {
        didSet { scheduleUpdateResults(debounce: false) }
    }
    @Published var showingError = false
    @Published var errorTitle = "Error"
    @Published var errorMessage = ""

    private var index: [IndexedFile] = []
    private var spotlightResults: [IndexedFile] = []
    private var indexTask: Task<Void, Never>?
    private var spotlightTask: Task<Void, Never>?
    private var updateResultsTask: Task<Void, Never>?

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

        func belongsToRoot(_ file: IndexedFile) -> Bool {
            file.url.path == root.url.path || file.url.path.hasPrefix(root.url.path + "/")
        }

        index.removeAll(where: belongsToRoot)
        spotlightResults.removeAll(where: belongsToRoot)

        if isIndexing {
            // The in-flight scan still includes the removed root; restart it so its files do not reappear.
            reindex()
            return
        }

        scheduleUpdateResults(debounce: false)
        scheduleSpotlightSearch()
        statusText = "\(index.count.formatted()) items indexed"
    }

    func reindex() {
        indexTask?.cancel()
        let rootURLs = roots.map(\.url)

        guard !rootURLs.isEmpty else {
            spotlightTask?.cancel()
            updateResultsTask?.cancel()
            isIndexing = false
            index = []
            spotlightResults = []
            results = []
            selectedResultIDs = []
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
                scheduleUpdateResults(debounce: false)
                scheduleSpotlightSearch()
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                isIndexing = false
                statusText = "Indexing failed"
                errorTitle = "Indexing Error"
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    func results(for ids: Set<SearchResult.ID>) -> [SearchResult] {
        results.filter { ids.contains($0.id) }
    }

    var selectedResults: [SearchResult] {
        results.filter { selectedResultIDs.contains($0.id) }
    }

    func selectAll() {
        selectedResultIDs = Set(results.map(\.id))
    }

    func deselectAll() {
        selectedResultIDs = []
    }

    func invertSelection() {
        let allIDs = Set(results.map(\.id))
        selectedResultIDs = allIDs.symmetricDifference(selectedResultIDs)
    }

    func openContainingFolders(_ items: [SearchResult]) {
        let parentFolders = Set(items.map { $0.url.deletingLastPathComponent() })
        for folder in parentFolders {
            NSWorkspace.shared.open(folder)
        }
    }

    func copyResults(_ items: [SearchResult]) {
        performTransfer(action: .copy, on: items)
    }

    func moveResults(_ items: [SearchResult]) {
        performTransfer(action: .move, on: items)
    }

    private func performTransfer(action: FileTransferAction, on items: [SearchResult]) {
        guard !items.isEmpty else {
            return
        }

        let panel = NSOpenPanel()
        panel.title = action == .copy ? "Choose Destination to Copy" : "Choose Destination to Move"
        panel.prompt = action == .copy ? "Copy" : "Move"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let destination = panel.urls.first else {
            return
        }

        var failures: [String] = []
        let destinationPath = destination.standardizedFileURL.path

        for item in items {
            let destinationURL = destination.appendingPathComponent(item.url.lastPathComponent)
            let sourcePath = item.url.standardizedFileURL.path

            do {
                if item.isDirectory,
                   destinationPath == sourcePath || destinationPath.hasPrefix(sourcePath + "/") {
                    throw NSError(
                        domain: "Anythings.FileTransfer",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Cannot place a folder inside itself."]
                    )
                }

                guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
                    throw CocoaError(.fileWriteFileExists)
                }

                switch action {
                case .copy:
                    try FileManager.default.copyItem(at: item.url, to: destinationURL)
                case .move:
                    try FileManager.default.moveItem(at: item.url, to: destinationURL)
                }
            } catch {
                failures.append("\(item.name): \(error.localizedDescription)")
            }
        }

        let destinationIsIndexed = roots.contains { root in
            destinationPath == root.url.path || destinationPath.hasPrefix(root.url.path + "/")
        }

        if action == .move || destinationIsIndexed {
            reindex()
        }

        if !failures.isEmpty {
            errorTitle = action == .copy ? "Copy Failed" : "Move Failed"
            errorMessage = failures.joined(separator: "\n")
            showingError = true
        } else {
            statusText = action == .copy
                ? "Copied \(items.count) item(s) to \(destination.lastPathComponent)"
                : "Moved \(items.count) item(s) to \(destination.lastPathComponent)"
        }
    }

    private var allowedExtensions: Set<String> {
        var extensions = Set<String>()

        for category in FileTypeCatalog.categories where selectedFileTypeCategoryIDs.contains(category.id) {
            extensions.formUnion(category.extensions)
        }

        let customExtensions = customExtensionsText
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == ";" })
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased() }
            .filter { !$0.isEmpty }

        extensions.formUnion(customExtensions)

        return extensions
    }

    private func updateResults() {
        scheduleUpdateResults(debounce: false)
    }

    private func scheduleUpdateResults(debounce: Bool) {
        updateResultsTask?.cancel()

        let snapshotIndex = index
        let snapshotSpotlight = spotlightResults
        let snapshotQuery = query
        let snapshotMatchesFullPath = matchesFullPath
        let snapshotCaseSensitive = caseSensitive
        let snapshotHidesSystemFiles = hidesSystemFiles
        let snapshotAllowedExtensions = allowedExtensions
        let snapshotSortField = sortField
        let snapshotSortAscending = sortAscending

        updateResultsTask = Task {
            if debounce {
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled else { return }
            }

            let computedResults = await Task.detached(priority: .userInitiated) {
                SearchViewModel.computeResults(
                    index: snapshotIndex,
                    spotlightResults: snapshotSpotlight,
                    query: snapshotQuery,
                    matchesFullPath: snapshotMatchesFullPath,
                    caseSensitive: snapshotCaseSensitive,
                    hidesSystemFiles: snapshotHidesSystemFiles,
                    allowedExtensions: snapshotAllowedExtensions,
                    sortField: snapshotSortField,
                    sortAscending: snapshotSortAscending
                )
            }.value

            guard !Task.isCancelled else { return }

            results = computedResults
            selectedResultIDs = selectedResultIDs.intersection(Set(results.map(\.id)))
        }
    }

    private nonisolated static func computeResults(
        index: [IndexedFile],
        spotlightResults: [IndexedFile],
        query: String,
        matchesFullPath: Bool,
        caseSensitive: Bool,
        hidesSystemFiles: Bool,
        allowedExtensions: Set<String>,
        sortField: SortField,
        sortAscending: Bool
    ) -> [SearchResult] {
        let search = SearchExpression(
            rawQuery: query,
            matchesFullPath: matchesFullPath,
            caseSensitive: caseSensitive,
            hidesSystemFiles: hidesSystemFiles,
            allowedExtensions: allowedExtensions
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

        return applySort(to: nextResults, field: sortField, ascending: sortAscending)
    }

    private nonisolated static func applySort(to items: [SearchResult], field: SortField, ascending: Bool) -> [SearchResult] {
        let sortedItems: [SearchResult]

        switch field {
        case .name:
            sortedItems = items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .path:
            sortedItems = items.sorted { $0.parentPath.localizedStandardCompare($1.parentPath) == .orderedAscending }
        case .modified:
            sortedItems = items.sorted { $0.modifiedAt < $1.modifiedAt }
        case .size:
            sortedItems = items.sorted { $0.size < $1.size }
        }

        return ascending ? sortedItems : sortedItems.reversed()
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
                      caseSensitive == requestCaseSensitive,
                      roots.map(\.url) == rootURLs else {
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

                errorTitle = "Search Error"
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
