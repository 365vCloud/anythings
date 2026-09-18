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

                guard root.hasDirectoryPath else {
                    continue
                }

                let output: String
                do {
                    output = try runMDFind(predicate: predicate, root: root)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // A single unreachable or unmounted root should not abort the whole search.
                    NSLog("Spotlight search skipped for %@: %@", root.path, error.localizedDescription)
                    continue
                }

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

        // Drain stderr concurrently so a chatty mdfind cannot block on a full pipe.
        let errorReader = Thread {
            _ = errorPipe.fileHandleForReading.readDataToEndOfFile()
        }
        errorReader.start()

        // Read stdout to EOF before waiting; reading after waitUntilExit() deadlocks
        // once mdfind emits more than the pipe buffer (~64 KB) of results.
        var outputData = Data()
        let reader = outputPipe.fileHandleForReading
        while true {
            if Task.isCancelled {
                process.terminate()
                throw CancellationError()
            }

            let chunk = reader.availableData
            if chunk.isEmpty {
                break
            }
            outputData.append(chunk)
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "Anythings.SpotlightSearch",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "mdfind exited with status \(process.terminationStatus)"]
            )
        }

        return String(data: outputData, encoding: .utf8) ?? ""
    }
}
