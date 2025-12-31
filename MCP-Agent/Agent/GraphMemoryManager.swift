import Foundation
import OSLog

// MARK: - Models
struct MemoryNode: Identifiable, Codable {
    let id: UUID
    var name: String
    var type: String
    var properties: [String: String]
    var createdAt: Date
    var updatedAt: Date
    
    init(name: String, type: String, properties: [String: String] = [:]) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.properties = properties
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

struct MemoryEdge: Identifiable, Codable {
    let id: UUID
    let sourceId: UUID
    let targetId: UUID
    let relation: String
    var createdAt: Date
    
    init(sourceId: UUID, targetId: UUID, relation: String) {
        self.id = UUID()
        self.sourceId = sourceId
        self.targetId = targetId
        self.relation = relation
        self.createdAt = Date()
    }
}

// MARK: - Manager
class GraphMemoryManager: ObservableObject {
    static let shared = GraphMemoryManager()
    
    @Published var nodes: [MemoryNode] = []
    @Published var edges: [MemoryEdge] = []
    
    private let logger = Logger(subsystem: "com.mcp.agent", category: "GraphMemoryManager")
    private let defaultsKey = "BuddyMCPGraphMemory"
    
    private init() {
        loadMemory()
    }
    
    // MARK: - CRUD
    
    func addNode(name: String, type: String, properties: [String: String] = [:]) -> MemoryNode {
        // Check for duplicate node by name/type to avoid clutter
        if let existing = nodes.first(where: { $0.name.lowercased() == name.lowercased() && $0.type.lowercased() == type.lowercased() }) {
            return existing
        }
        
        let node = MemoryNode(name: name, type: type, properties: properties)
        nodes.append(node)
        saveMemory()
        logger.info("Added memory node: \(name) (\(type))")
        return node
    }
    
    func addEdge(from sourceName: String, to targetName: String, relation: String) -> MemoryEdge? {
        // Simple resolution by name for V1 convenience
        guard let source = nodes.first(where: { $0.name.lowercased() == sourceName.lowercased() }),
              let target = nodes.first(where: { $0.name.lowercased() == targetName.lowercased() }) else {
            logger.warning("Could not create edge: nodes not found")
            return nil
        }
        
        // Check for duplicates
        if let existing = edges.first(where: { $0.sourceId == source.id && $0.targetId == target.id && $0.relation.lowercased() == relation.lowercased() }) {
            return existing
        }
        
        let edge = MemoryEdge(sourceId: source.id, targetId: target.id, relation: relation)
        edges.append(edge)
        saveMemory()
        logger.info("Added memory edge: \(source.name) -> \(relation) -> \(target.name)")
        return edge
    }
    
    func search(query: String) -> [String: Any] {
        let lowerQuery = query.lowercased()
        
        let matchingNodes = nodes.filter { node in
            node.name.lowercased().contains(lowerQuery) ||
            node.type.lowercased().contains(lowerQuery) ||
            node.properties.values.contains { $0.lowercased().contains(lowerQuery) }
        }
        
        var results: [String: Any] = [:]
        var relatedNodes: Set<UUID> = []
        
        // Format nodes
        let nodesData = matchingNodes.map { node -> [String: Any] in
            relatedNodes.insert(node.id)
            return [
                "id": node.id.uuidString,
                "name": node.name,
                "type": node.type,
                "properties": node.properties
            ]
        }
        results["nodes"] = nodesData
        
        // Find edges connected to these nodes
        let matchingEdges = edges.filter { edge in
            relatedNodes.contains(edge.sourceId) || relatedNodes.contains(edge.targetId)
        }
        
        let edgesData = matchingEdges.map { edge -> [String: Any] in
            let sourceName = nodes.first(where: { $0.id == edge.sourceId })?.name ?? "Unknown"
            let targetName = nodes.first(where: { $0.id == edge.targetId })?.name ?? "Unknown"
            
            return [
                "source": sourceName,
                "target": targetName,
                "relation": edge.relation
            ]
        }
        results["edges"] = edgesData
        
        return results
    }
    
    func getAllMemory() -> [String: Any] {
        return [
            "nodes": nodes.map { ["name": $0.name, "type": $0.type] },
            "edge_count": edges.count
        ]
    }
    
    // MARK: - Persistence
    
    private struct StorageContainer: Codable {
        let nodes: [MemoryNode]
        let edges: [MemoryEdge]
    }
    
    private func saveMemory() {
        let container = StorageContainer(nodes: nodes, edges: edges)
        if let data = try? JSONEncoder().encode(container) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
    
    private func loadMemory() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let container = try? JSONDecoder().decode(StorageContainer.self, from: data) else {
            return
        }
        self.nodes = container.nodes
        self.edges = container.edges
    }
}
