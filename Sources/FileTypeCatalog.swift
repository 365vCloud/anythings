import Foundation

struct FileTypeCategory: Identifiable, Hashable {
    let id: String
    let name: String
    let extensions: Set<String>
}

/// Well-known file type groups used by the advanced filter. Extensions are lowercase and without the leading dot.
enum FileTypeCatalog {
    static let categories: [FileTypeCategory] = [
        FileTypeCategory(id: "pdf", name: "PDF", extensions: ["pdf"]),
        FileTypeCategory(
            id: "documents",
            name: "Documents",
            extensions: ["doc", "docx", "rtf", "rtfd", "txt", "pages", "odt", "md", "csv", "xls", "xlsx", "ppt", "pptx", "key", "numbers"]
        ),
        FileTypeCategory(
            id: "images",
            name: "Images",
            extensions: ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "heic", "heif", "svg", "webp", "raw", "psd", "ai"]
        ),
        FileTypeCategory(
            id: "audio",
            name: "Audio",
            extensions: ["mp3", "wav", "aac", "flac", "m4a", "ogg", "wma", "aiff"]
        ),
        FileTypeCategory(
            id: "video",
            name: "Video",
            extensions: ["mp4", "mov", "avi", "mkv", "wmv", "flv", "webm", "m4v", "mpg", "mpeg"]
        ),
        FileTypeCategory(
            id: "archives",
            name: "Archives",
            extensions: ["zip", "rar", "7z", "tar", "gz", "bz2", "xz", "dmg", "iso"]
        ),
        FileTypeCategory(
            id: "code",
            name: "Code",
            extensions: ["swift", "py", "js", "ts", "tsx", "jsx", "java", "c", "cpp", "h", "hpp", "go", "rb", "php", "html", "css", "json", "xml", "yaml", "yml", "sh", "sql", "rs", "kt"]
        ),
        FileTypeCategory(
            id: "apps",
            name: "Apps & Installers",
            extensions: ["app", "pkg", "exe", "msi", "apk"]
        )
    ]
}
