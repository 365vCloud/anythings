import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: SearchViewModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            VStack(spacing: 0) {
                SearchBar()
                    .focused($searchFocused)
                    .padding()

                Divider()

                ResultList()
            }
            .navigationTitle("Anythings")
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        viewModel.presentFolderPicker()
                    } label: {
                        Label("Add Folder", systemImage: "folder.badge.plus")
                    }

                    Button {
                        viewModel.reindex()
                    } label: {
                        Label("Re-index", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.roots.isEmpty || viewModel.isIndexing)

                    Menu {
                        Button("Select All") {
                            viewModel.selectAll()
                        }
                        Button("Deselect All") {
                            viewModel.deselectAll()
                        }
                        Button("Invert Selection") {
                            viewModel.invertSelection()
                        }
                    } label: {
                        Label("Selection", systemImage: "checkmark.circle")
                    }
                    .disabled(viewModel.results.isEmpty)

                    Picker("View", selection: $viewModel.viewMode) {
                        ForEach(ResultViewMode.allCases) { mode in
                            Label(mode.label, systemImage: mode.systemImage)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)

                    Menu {
                        Picker("Sort By", selection: $viewModel.sortField) {
                            ForEach(SortField.allCases) { field in
                                Text(field.label).tag(field)
                            }
                        }

                        Divider()

                        Toggle("Ascending", isOn: $viewModel.sortAscending)
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                }
            }
            .onAppear {
                searchFocused = true
            }
        }
        .alert(viewModel.errorTitle, isPresented: $viewModel.showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var viewModel: SearchViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Indexed Folders")
                        .font(.headline)

                    if viewModel.roots.isEmpty {
                        EmptyStateView(
                            title: "No folders indexed",
                            systemImage: "folder",
                            description: "Add a folder to start searching files."
                        )
                        .frame(maxWidth: .infinity, maxHeight: 180)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(viewModel.roots) { root in
                                HStack {
                                    Image(systemName: "folder")
                                        .foregroundStyle(.secondary)
                                    Text(root.url.path)
                                        .lineLimit(1)
                                        .truncationMode(.middle)

                                    Spacer()

                                    Button {
                                        viewModel.removeRoot(root)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                    .help("Remove this folder from the index")
                                }
                                .contextMenu {
                                    Button("Reveal in Finder") {
                                        NSWorkspace.shared.activateFileViewerSelecting([root.url])
                                    }
                                    Button("Remove", role: .destructive) {
                                        viewModel.removeRoot(root)
                                    }
                                }
                            }
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Match full path", isOn: $viewModel.matchesFullPath)
                    Toggle("Case sensitive", isOn: $viewModel.caseSensitive)
                    Toggle("Hide system & log files", isOn: $viewModel.hidesSystemFiles)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("File Type Filter")
                            .font(.subheadline.weight(.semibold))

                        Spacer()

                        if !viewModel.selectedFileTypeCategoryIDs.isEmpty || !viewModel.customExtensionsText.isEmpty {
                            Button("Clear") {
                                viewModel.selectedFileTypeCategoryIDs = []
                                viewModel.customExtensionsText = ""
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                    }

                    ForEach(FileTypeCatalog.categories) { category in
                        Toggle(
                            category.name,
                            isOn: Binding(
                                get: { viewModel.selectedFileTypeCategoryIDs.contains(category.id) },
                                set: { isOn in
                                    if isOn {
                                        viewModel.selectedFileTypeCategoryIDs.insert(category.id)
                                    } else {
                                        viewModel.selectedFileTypeCategoryIDs.remove(category.id)
                                    }
                                }
                            )
                        )
                        .toggleStyle(.checkbox)
                    }

                    TextField("Custom extensions, e.g. psd, ai", text: $viewModel.customExtensionsText)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    if viewModel.isIndexing {
                        ProgressView(value: viewModel.indexProgress)
                        Text(viewModel.statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    } else {
                        Label("\(viewModel.indexedItemCount.formatted()) items indexed", systemImage: "externaldrive")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Label("\(viewModel.results.count.formatted()) matches", systemImage: "magnifyingglass")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
    }
}

private struct SearchBar: View {
    @EnvironmentObject private var viewModel: SearchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search files by name, wildcard, or quoted phrase", text: $viewModel.query)
                    .textFieldStyle(.plain)
                    .font(.title3)

                if !viewModel.query.isEmpty {
                    Button {
                        viewModel.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))

            Text("Tips: use `*.pdf`, `report ?2026`, or quoted phrases like `\"tax return\"`.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ResultList: View {
    @EnvironmentObject private var viewModel: SearchViewModel

    var body: some View {
        Group {
            if viewModel.roots.isEmpty {
                EmptyStateView(
                    title: "Add a folder",
                    systemImage: "folder.badge.plus",
                    description: "Choose one or more folders to build a local search index."
                )
            } else if viewModel.results.isEmpty {
                EmptyStateView(
                    title: "No results",
                    systemImage: "magnifyingglass",
                    description: viewModel.query.isEmpty ? "Start typing to search the current index." : "No indexed item matches \"\(viewModel.query)\"."
                )
            } else {
                switch viewModel.viewMode {
                case .table:
                    TableResultsView()
                case .largeIcons:
                    IconGridResultsView(iconSize: 72, minimumColumnWidth: 120)
                case .smallIcons:
                    IconGridResultsView(iconSize: 32, minimumColumnWidth: 200)
                }
            }
        }
    }
}

private struct TableResultsView: View {
    @EnvironmentObject private var viewModel: SearchViewModel

    var body: some View {
        Table(viewModel.results, selection: $viewModel.selectedResultIDs) {
            TableColumn("Name") { result in
                HStack {
                    Image(systemName: result.isDirectory ? "folder" : "doc")
                        .foregroundStyle(result.isDirectory ? .blue : .secondary)
                    Text(result.name)
                        .lineLimit(1)
                }
            }
            .width(min: 220, ideal: 320)

            TableColumn("Path") { result in
                Text(result.parentPath)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .width(min: 280, ideal: 520)

            TableColumn("Modified") { result in
                Text(result.modifiedAt, style: .date)
                    .foregroundStyle(.secondary)
            }
            .width(120)

            TableColumn("Size") { result in
                Text(result.sizeDescription)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(90)
        }
        .contextMenu(forSelectionType: SearchResult.ID.self) { ids in
            let items = ids.isEmpty ? viewModel.selectedResults : viewModel.results(for: ids)
            ResultContextMenuItems(items: items)
        } primaryAction: { ids in
            for result in viewModel.results(for: ids) {
                NSWorkspace.shared.open(result.url)
            }
        }
    }
}

private struct IconGridResultsView: View {
    @EnvironmentObject private var viewModel: SearchViewModel
    let iconSize: CGFloat
    let minimumColumnWidth: CGFloat

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: minimumColumnWidth), spacing: 16)]
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(viewModel.results) { result in
                    IconResultCell(
                        result: result,
                        iconSize: iconSize,
                        isSelected: viewModel.selectedResultIDs.contains(result.id)
                    )
                    .gesture(
                        TapGesture(count: 2)
                            .onEnded { NSWorkspace.shared.open(result.url) }
                            .exclusively(before: TapGesture(count: 1).onEnded { toggleSelection(for: result) })
                    )
                    .contextMenu {
                        let items = viewModel.selectedResultIDs.contains(result.id) ? viewModel.selectedResults : [result]
                        ResultContextMenuItems(items: items)
                    }
                }
            }
            .padding()
        }
    }

    private func toggleSelection(for result: SearchResult) {
        if NSEvent.modifierFlags.contains(.command) {
            if viewModel.selectedResultIDs.contains(result.id) {
                viewModel.selectedResultIDs.remove(result.id)
            } else {
                viewModel.selectedResultIDs.insert(result.id)
            }
        } else {
            viewModel.selectedResultIDs = [result.id]
        }
    }
}

private struct IconResultCell: View {
    let result: SearchResult
    let iconSize: CGFloat
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: result.url.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize, height: iconSize)

            Text(result.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(
            isSelected ? Color.accentColor.opacity(0.25) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
    }
}

private struct ResultContextMenuItems: View {
    @EnvironmentObject private var viewModel: SearchViewModel
    let items: [SearchResult]

    var body: some View {
        Group {
            if items.count == 1, let single = items.first {
                Button("Open") {
                    NSWorkspace.shared.open(single.url)
                }
            }

            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(items.map(\.url))
            }

            Button("Open Containing Folder") {
                viewModel.openContainingFolders(items)
            }

            Divider()

            Button("Copy to Folder...") {
                viewModel.copyResults(items)
            }

            Button("Move to Folder...") {
                viewModel.moveResults(items)
            }

            Divider()

            Button(items.count > 1 ? "Copy Paths" : "Copy Path") {
                let paths = items.map(\.url.path).joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(paths, forType: .string)
            }
        }
        .disabled(items.isEmpty)
    }
}

private struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 42))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
