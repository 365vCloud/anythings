import Foundation

struct SearchExpression: Sendable {
    /// File extensions treated as system, log, or transient artifacts and hidden from results by default.
    private static let excludedExtensions: Set<String> = [
        "log", "logs", "tmp", "temp", "cache", "bak", "swp", "swo",
        "pid", "lock", "pyc", "o", "obj", "class", "crash", "dmp", "diagpb"
    ]

    /// Exact file names treated as system artifacts regardless of extension.
    private static let excludedNames: Set<String> = [
        ".ds_store", "thumbs.db", "desktop.ini", ".localized"
    ]

    private let terms: [SearchTerm]
    private let matchesFullPath: Bool
    private let caseSensitive: Bool
    private let hidesSystemFiles: Bool
    private let allowedExtensions: Set<String>

    init(
        rawQuery: String,
        matchesFullPath: Bool,
        caseSensitive: Bool,
        hidesSystemFiles: Bool = true,
        allowedExtensions: Set<String> = []
    ) {
        self.terms = SearchExpression.parse(rawQuery)
        self.matchesFullPath = matchesFullPath
        self.caseSensitive = caseSensitive
        self.hidesSystemFiles = hidesSystemFiles
        self.allowedExtensions = allowedExtensions
    }

    func matches(_ file: IndexedFile) -> Bool {
        if hidesSystemFiles, !file.isDirectory, Self.isSystemFile(file) {
            return false
        }

        if !allowedExtensions.isEmpty, !file.isDirectory, !allowedExtensions.contains(file.fileExtension) {
            return false
        }

        guard !terms.isEmpty else {
            return true
        }

        let searchableText = matchesFullPath ? file.searchPath : file.name
        let normalizedText = caseSensitive ? searchableText : searchableText.lowercased()

        return terms.allSatisfy { term in
            term.matches(normalizedText, caseSensitive: caseSensitive)
        }
    }

    private static func isSystemFile(_ file: IndexedFile) -> Bool {
        let lowercasedName = file.name.lowercased()

        if excludedNames.contains(lowercasedName) {
            return true
        }

        if lowercasedName.hasPrefix(".") {
            return true
        }

        let fileExtension = (file.name as NSString).pathExtension.lowercased()
        return !fileExtension.isEmpty && excludedExtensions.contains(fileExtension)
    }

    private static func parse(_ query: String) -> [SearchTerm] {
        var terms: [SearchTerm] = []
        var current = ""
        var inQuotes = false

        for character in query {
            switch character {
            case "\"":
                if inQuotes, !current.isEmpty {
                    terms.append(SearchTerm(rawValue: current))
                    current = ""
                }
                inQuotes.toggle()
            case " " where !inQuotes,
                 "\t" where !inQuotes,
                 "\n" where !inQuotes:
                if !current.isEmpty {
                    terms.append(SearchTerm(rawValue: current))
                    current = ""
                }
            default:
                current.append(character)
            }
        }

        if !current.isEmpty {
            terms.append(SearchTerm(rawValue: current))
        }

        return terms
    }
}

private struct SearchTerm {
    let rawValue: String

    func matches(_ text: String, caseSensitive: Bool) -> Bool {
        let value = caseSensitive ? rawValue : rawValue.lowercased()

        guard value.contains("*") || value.contains("?") else {
            return text.range(of: value, options: caseSensitive ? [] : [.caseInsensitive, .diacriticInsensitive]) != nil
        }

        let pattern = "^" + NSRegularExpression.escapedPattern(for: value)
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".") + "$"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: caseSensitive ? [] : [.caseInsensitive]) else {
            return false
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }
}
