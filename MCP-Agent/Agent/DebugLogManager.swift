import Foundation

enum DebugLogLevel: String {
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

struct DebugLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: DebugLogLevel
    let category: String
    let message: String
    let details: String?
}

@MainActor
final class DebugLogManager: ObservableObject {
    static let shared = DebugLogManager()
    
    @Published private(set) var entries: [DebugLogEntry] = []
    
    private let maxEntries = 500
    
    private init() {}
    
    func log(_ level: DebugLogLevel, category: String, message: String, details: String? = nil) {
        let entry = DebugLogEntry(timestamp: Date(), level: level, category: category, message: message, details: details)
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }
    
    func clear() {
        entries.removeAll()
    }
    
    func exportText() -> String {
        entries.map { entry in
            var line = "[\(Self.formatTimestamp(entry.timestamp))] [\(entry.level.rawValue)] [\(entry.category)] \(entry.message)"
            if let details = entry.details, !details.isEmpty {
                line += "\n\(details)"
            }
            return line
        }
        .joined(separator: "\n\n")
    }
    
    func logNetworkRequest(context: String, request: URLRequest, bodyOverride: Data? = nil) {
        let method = request.httpMethod ?? "REQUEST"
        let url = request.url?.absoluteString ?? "unknown-url"
        let headers = sanitizeHeaders(request.allHTTPHeaderFields ?? [:])
        let bodyData = bodyOverride ?? request.httpBody
        
        var details: [String] = ["\(method) \(url)"]
        if !headers.isEmpty {
            details.append("Headers:\n\(prettyPrintedJSON(headers) ?? headers.description)")
        }
        if let bodyData = bodyData {
            let bodyString = prettyPrintedJSON(bodyData) ?? String(data: bodyData, encoding: .utf8) ?? "<non-utf8 body>"
            details.append("Body:\n\(truncate(bodyString))")
        }
        
        log(.info, category: "Network", message: "\(context) request", details: details.joined(separator: "\n\n"))
    }
    
    func logNetworkResponse(context: String, response: HTTPURLResponse, data: Data? = nil) {
        var details: [String] = ["Status: \(response.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: response.statusCode))"]
        if let data = data {
            let bodyString = prettyPrintedJSON(data) ?? String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            details.append("Body:\n\(truncate(bodyString))")
        }
        log(.info, category: "Network", message: "\(context) response", details: details.joined(separator: "\n\n"))
    }
    
    func logNetworkError(context: String, error: Error) {
        log(.error, category: "Network", message: "\(context) error", details: error.localizedDescription)
    }

    func exportJSONIfPossible(_ data: Data) -> String? {
        prettyPrintedJSON(data)
    }
    
    private func sanitizeHeaders(_ headers: [String: String]) -> [String: String] {
        var sanitized = headers
        for key in headers.keys {
            let lower = key.lowercased()
            if lower == "authorization" || lower.contains("api-key") {
                sanitized[key] = "**redacted**"
            }
        }
        return sanitized
    }
    
    private func prettyPrintedJSON(_ object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
    
    private func prettyPrintedJSON(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let pretty = prettyPrintedJSON(json) else {
            return nil
        }
        return pretty
    }
    
    private func truncate(_ text: String, limit: Int = 4000) -> String {
        guard text.count > limit else { return text }
        let index = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<index]) + "\n…(truncated)"
    }
    
    private static func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
