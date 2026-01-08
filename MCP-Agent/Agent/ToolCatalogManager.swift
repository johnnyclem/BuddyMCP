import Foundation
import OSLog

struct MCPCatalogItem: Identifiable, Equatable {
    enum Source: String {
        case curated
        case github
        case smithery
    }
    
    enum InstallMethod {
        case stdio(command: String)
        case sse(url: URL)
    }
    
    let id = UUID()
    let name: String
    let summary: String
    let source: Source
    let tags: [String]
    let install: InstallMethod
    let homepage: URL?
    let tintHex: String?
    let requiresAuth: Bool
}

@MainActor
final class ToolCatalogManager: ObservableObject {
    static let shared = ToolCatalogManager()
    
    @Published var curatedItems: [MCPCatalogItem] = []
    @Published var githubPackages: [MCPCatalogItem] = []
    @Published var smitheryPicks: [MCPCatalogItem] = []
    @Published var isLoadingGitHub = false
    @Published var isLoadingSmithery = false
    @Published var lastError: String?
    @Published var installingItems: Set<UUID> = []
    @Published var githubToken: String = ""
    
    private let logger = Logger(subsystem: "com.mcp.agent", category: "ToolCatalogManager")
    private let githubTokenKey = "com.mcp.agent.github.token"
    
    private init() {
        curatedItems = Self.defaultCuratedItems()
        githubToken = KeychainManager.shared.retrieveAPIKey(for: githubTokenKey, account: "github") ?? ""
        Task {
            await refreshCatalogs()
        }
    }
    
    func refreshCatalogs() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchGitHubPackages() }
            group.addTask { await self.loadSmitheryPicks() }
        }
    }
    
    func install(_ item: MCPCatalogItem) {
        guard !installingItems.contains(item.id) else { return }
        installingItems.insert(item.id)
        lastError = nil
        
        Task {
            defer { installingItems.remove(item.id) }
            if MCPManager.shared.servers.contains(where: { $0.name.lowercased() == item.name.lowercased() }) {
                return
            }
            
            switch item.install {
            case .stdio(let commandLine):
                let parts = commandLine.split(separator: " ").map { String($0) }
                guard let command = parts.first else { return }
                let args = Array(parts.dropFirst())
                MCPManager.shared.addServer(
                    name: item.name,
                    type: .stdio(command: command, arguments: args),
                    tintHex: item.tintHex ?? MCPManager.shared.nextAvailableTintHex()
                )
            case .sse(let url):
                MCPManager.shared.addServer(
                    name: item.name,
                    type: .sse(url: url),
                    tintHex: item.tintHex ?? MCPManager.shared.nextAvailableTintHex()
                )
            }
        }
    }
    
    func saveGitHubToken() {
        guard !githubToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            KeychainManager.shared.deleteAPIKey(for: githubTokenKey, account: "github")
            return
        }
        _ = KeychainManager.shared.storeAPIKey(githubToken, for: githubTokenKey, account: "github")
    }
    
    private func fetchGitHubPackages() async {
        isLoadingGitHub = true
        defer { isLoadingGitHub = false }
        lastError = nil
        
        guard let url = URL(string: "https://api.github.com/orgs/modelcontextprotocol/repos") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if !githubToken.isEmpty {
            request.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                lastError = "GitHub responded with status \(httpResponse.statusCode)."
                logger.error("GitHub fetch failed: status \(httpResponse.statusCode)")
                return
            }
            let repos = try JSONDecoder().decode([GitHubRepo].self, from: data)
            let items = repos.map { repo in
                MCPCatalogItem(
                    name: repo.name,
                    summary: repo.description ?? "Official MCP package maintained by modelcontextprotocol.",
                    source: .github,
                    tags: ["official", "@modelcontextprotocol"],
                    install: .stdio(command: "npx -y @modelcontextprotocol/\(repo.name)"),
                    homepage: URL(string: repo.html_url),
                    tintHex: MCPManager.shared.inferTintHex(forName: repo.name),
                    requiresAuth: false
                )
            }
            await MainActor.run {
                self.githubPackages = items.sorted { $0.name.lowercased() < $1.name.lowercased() }
            }
        } catch {
            logger.error("GitHub fetch failed: \(error.localizedDescription)")
            lastError = "Could not load GitHub packages. Try adding a token to raise rate limits."
        }
    }
    
    private func loadSmitheryPicks() async {
        isLoadingSmithery = true
        defer { isLoadingSmithery = false }
        
        // Placeholder curated picks until smithery publishes an API endpoint
        let picks: [MCPCatalogItem] = [
            MCPCatalogItem(
                name: "smithery-weather",
                summary: "Smithery curated forecast + air quality toolkit ready for MCP agents.",
                source: .smithery,
                tags: ["smithery", "weather", "community"],
                install: .stdio(command: "npx -y @smithery-ai/weather-mcp"),
                homepage: URL(string: "https://smithery.ai"),
                tintHex: "BFD7EA",
                requiresAuth: false
            ),
            MCPCatalogItem(
                name: "smithery-crypto",
                summary: "Community crypto price + news bundle from the Smithery index.",
                source: .smithery,
                tags: ["smithery", "crypto"],
                install: .stdio(command: "npx -y @smithery-ai/crypto-mcp"),
                homepage: URL(string: "https://smithery.ai"),
                tintHex: "F2D0A9",
                requiresAuth: false
            )
        ]
        smitheryPicks = picks
    }
    
    private static func defaultCuratedItems() -> [MCPCatalogItem] {
        return [
            MCPCatalogItem(
                name: "calendar-plus",
                summary: "Bring in a calendar-aware MCP with smart event creation.",
                source: .curated,
                tags: ["calendar", "productivity"],
                install: .stdio(command: "npx -y @modelcontextprotocol/calendar"),
                homepage: URL(string: "https://github.com/modelcontextprotocol/calendar"),
                tintHex: "D6EBD1",
                requiresAuth: false
            ),
            MCPCatalogItem(
                name: "research-kit",
                summary: "A research-focused MCP with web fetch + summarization helpers.",
                source: .curated,
                tags: ["research", "web"],
                install: .stdio(command: "npx -y @modelcontextprotocol/web"),
                homepage: URL(string: "https://github.com/modelcontextprotocol/web"),
                tintHex: "BFD7EA",
                requiresAuth: false
            ),
            MCPCatalogItem(
                name: "smithery-apps",
                summary: "Popular Smithery community picks in one bundle.",
                source: .curated,
                tags: ["smithery", "bundle"],
                install: .sse(url: URL(string: "https://smithery.ai/api/mcp/sse")!),
                homepage: URL(string: "https://smithery.ai"),
                tintHex: "E1C6D7",
                requiresAuth: true
            )
        ]
    }
}

private struct GitHubRepo: Decodable {
    let name: String
    let description: String?
    let html_url: String
}
