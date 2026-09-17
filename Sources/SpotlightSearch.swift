import Foundation

enum SpotlightSearch {
    static func search(
        query: String,
        roots: [URL],
        matchesFullPath: Bool,
        caseSensitive: Bool
    ) async throws -> [IndexedFile] {
        let predicate = buildPredicate(
            query: query,
            matchesFullPath: matchesFullPath,
            caseSensitive: caseSensitive
        )

        return try await Task.detached(priority: .userInitiated) {
            var files: [IndexedFile] = []
            var seenPaths = Set<String>()
            let resourceKeys: [URLResourceKey] = [
                .isDirectoryKey,
                .fileSizeKey,
                .contentModificationDateKey,
                .isReadableKey
            ]

            for root in roots {
                try Task.checkCancellation()

                let output = try runMDFind(predicate: predicate, root: root)
                for path in output.split(separator: "\n", omittingEmptySubsequences: true) {
                    try Task.checkCancellation()

                    let normalizedPath = String(path)
                    guard seenPaths.insert(normalizedPath).inserted else {
                        continue
                    }

                    let url = URL(fileURLWithPath: normalizedPath)
                    if let file = IndexedFile(url: url, resourceKeys: resourceKeys) {
                        files.append(file)
                    }

                    if files.count >= 5_000 {
                        return files
                    }
                }
            }

            return files
        }.value
    }

    private static func buildPredicate(query: String, matchesFullPath: Bool, caseSensitive: Bool) -> String {
        let terms = tokenize(query)
        let modifier = caseSensitive ? "d" : "cd"
        let fields = matchesFullPath ? ["kMDItemFSName", "kMDItemDisplayName", "kMDItemPath"] : ["kMDItemFSName", "kMDItemDisplayName"]

        return terms.map { term in
            let pattern = wildcardPattern(for: term)
            let clauses = fields.map { field in
                "\(field) == \"\(pattern)\"\(modifier)"
            }
            return "(" + clauses.joined(separator: " || ") + ")"
        }.joined(separator: " && ")
    }

    private static func wildcardPattern(for term: String) -> String {
        var escaped = ""

        for character in term {
            switch character {
            case "\"", "\\":
                escaped.append("\\")
                escaped.append(character)
            case "?":
                escaped.append("*")
            default:
                escaped.append(character)
            }
        }

        if !escaped.contains("*") {
            escaped = "*\(escaped)*"
        }

        return escaped
    }

    private static func tokenize(_ query: String) -> [String] {
        var terms: [String] = []
        var current = ""
        var inQuotes = false

        for character in query {
            switch character {
            case "\"":
                if inQuotes, !current.isEmpty {
                    terms.append(current)
                    current = ""
                }
                inQuotes.toggle()
            case " " where !inQuotes,
                 "\t" where !inQuotes,
                 "\n" where !inQuotes:
                if !current.isEmpty {
                    terms.append(current)
                    current = ""
                }
            default:
                current.append(character)
            }
        }

        if !current.isEmpty {
            terms.append(current)
        }

        return terms
    }

    private static func runMDFind(predicate: String, root: URL) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["-onlyin", root.path, predicate]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8) ?? "mdfind exited with status \(process.terminationStatus)"
            throw NSError(
                domain: "Anythings.SpotlightSearch",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        return String(data: outputData, encoding: .utf8) ?? ""
    }
}
