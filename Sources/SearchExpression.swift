import Foundation

struct SearchExpression {
    private let terms: [SearchTerm]
    private let matchesFullPath: Bool
    private let caseSensitive: Bool

    init(rawQuery: String, matchesFullPath: Bool, caseSensitive: Bool) {
        self.terms = SearchExpression.parse(rawQuery)
        self.matchesFullPath = matchesFullPath
        self.caseSensitive = caseSensitive
    }

    func matches(_ file: IndexedFile) -> Bool {
        guard !terms.isEmpty else {
            return true
        }

        let searchableText = matchesFullPath ? file.searchPath : file.name
        let normalizedText = caseSensitive ? searchableText : searchableText.lowercased()

        return terms.allSatisfy { term in
            term.matches(normalizedText, caseSensitive: caseSensitive)
        }
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
