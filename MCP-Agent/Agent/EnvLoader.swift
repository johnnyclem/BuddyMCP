import Foundation

enum EnvLoader {
    static func loadMergedEnvironment() -> [String: String] {
        var merged = ProcessInfo.processInfo.environment
        if let fileEnv = loadEnvFile() {
            for (key, value) in fileEnv {
                if merged[key] == nil {
                    merged[key] = value
                }
            }
        }
        return merged
    }
    
    private static func loadEnvFile() -> [String: String]? {
        guard let url = findEnvFile() else { return nil }
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var values: [String: String] = [:]
        
        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            var trimmed = line
            if trimmed.hasPrefix("export ") {
                trimmed = String(trimmed.dropFirst(7))
            }
            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            var value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            if !key.isEmpty {
                values[key] = value
            }
        }
        
        return values
    }
    
    private static func findEnvFile(maxDepth: Int = 4) -> URL? {
        var current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0...maxDepth {
            let candidate = current.appendingPathComponent(".env")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                break
            }
            current = parent
        }
        return nil
    }
}
