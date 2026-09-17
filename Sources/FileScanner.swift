import Foundation

enum FileScanner {
    static func scan(urls: [URL]) async throws -> [IndexedFile] {
        try await Task.detached(priority: .userInitiated) {
            var files: [IndexedFile] = []
            let resourceKeys: [URLResourceKey] = [
                .isDirectoryKey,
                .fileSizeKey,
                .contentModificationDateKey,
                .isPackageKey,
                .isReadableKey
            ]

            for root in urls {
                try Task.checkCancellation()

                guard root.hasDirectoryPath else {
                    continue
                }

                if let rootFile = IndexedFile(url: root, resourceKeys: resourceKeys) {
                    files.append(rootFile)
                }

                guard let enumerator = FileManager.default.enumerator(
                    at: root,
                    includingPropertiesForKeys: resourceKeys,
                    options: [.skipsPackageDescendants],
                    errorHandler: { url, error in
                        NSLog("Skipping %@: %@", url.path, error.localizedDescription)
                        return true
                    }
                ) else {
                    continue
                }

                for case let fileURL as URL in enumerator {
                    try Task.checkCancellation()

                    if let file = IndexedFile(url: fileURL, resourceKeys: resourceKeys) {
                        files.append(file)
                    }
                }
            }

            return files
        }.value
    }
}
