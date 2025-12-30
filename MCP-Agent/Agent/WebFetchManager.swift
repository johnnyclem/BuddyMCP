import Foundation

class WebFetchManager {
    static let shared = WebFetchManager()
    
    private init() {}
    
    func fetchContent(url: String, selector: String?) async throws -> [String: Any] {
        guard let urlObj = URL(string: url) else {
            throw NSError(domain: "WebFetchManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        let (data, _) = try await URLSession.shared.data(from: urlObj)
        let content = String(data: data, encoding: .utf8) ?? ""
        
        // In a real implementation, use SwiftSoup or similar to parse HTML with selector
        // For now, return raw content or a placeholder if selector is present
        
        return [
            "url": url,
            "content_length": content.count,
            "content_snippet": String(content.prefix(200)),
            "selector": selector ?? "none"
        ]
    }
}
