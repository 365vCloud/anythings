import Foundation

struct IndexedRoot: Identifiable, Hashable {
    let id: String
    let url: URL

    init(url: URL) {
        self.url = url
        self.id = url.path
    }
}

struct IndexedFile: Hashable, Sendable {
    let url: URL
    let name: String
    let parentPath: String
    let searchPath: String
    let isDirectory: Bool
    let size: Int64
    let modifiedAt: Date

    init?(url: URL, resourceKeys: [URLResourceKey]) {
        guard let values = try? url.resourceValues(forKeys: Set(resourceKeys)),
              values.isReadable != false else {
            return nil
        }

        self.url = url
        self.name = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        self.parentPath = url.deletingLastPathComponent().path
        self.searchPath = url.path
        self.isDirectory = values.isDirectory == true
        self.size = Int64(values.fileSize ?? 0)
        self.modifiedAt = values.contentModificationDate ?? .distantPast
    }

    var fileExtension: String {
        (name as NSString).pathExtension.lowercased()
    }
}

struct SearchResult: Identifiable, Hashable, Sendable {
    let id: String
    let url: URL
    let name: String
    let parentPath: String
    let isDirectory: Bool
    let size: Int64
    let modifiedAt: Date

    init(file: IndexedFile) {
        self.id = file.url.path
        self.url = file.url
        self.name = file.name
        self.parentPath = file.parentPath
        self.isDirectory = file.isDirectory
        self.size = file.size
        self.modifiedAt = file.modifiedAt
    }

    var fileExtension: String {
        (name as NSString).pathExtension.lowercased()
    }

    var sizeDescription: String {
        guard !isDirectory else {
            return "-"
        }

        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
