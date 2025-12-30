import Foundation

enum TaskStatus: String, Codable, CaseIterable {
    case pending
    case inProgress
    case completed
    case failed
    case skipped
}

enum TaskAssignee: String, Codable, CaseIterable {
    case user
    case agent
}

struct TaskItem: Identifiable, Codable {
    let id: UUID
    var title: String
    var description: String
    var assignee: TaskAssignee
    var status: TaskStatus
    var scheduledDate: Date?
    var dueDate: Date?
    var createdAt: Date
    
    init(id: UUID = UUID(), title: String, description: String = "", assignee: TaskAssignee, status: TaskStatus = .pending, scheduledDate: Date? = nil, dueDate: Date? = nil) {
        self.id = id
        self.title = title
        self.description = description
        self.assignee = assignee
        self.status = status
        self.scheduledDate = scheduledDate
        self.dueDate = dueDate
        self.createdAt = Date()
    }
}

class TaskManager: ObservableObject {
    static let shared = TaskManager()
    
    @Published var tasks: [TaskItem] = []
    private let defaultsKey = "BuddyMCPTasks"
    
    private init() {
        loadTasks()
        
        // Add sample tasks if empty
        if tasks.isEmpty {
            addSampleTasks()
        }
    }
    
    func addTask(title: String, description: String = "", assignee: TaskAssignee, scheduledDate: Date? = nil) {
        let task = TaskItem(title: title, description: description, assignee: assignee, scheduledDate: scheduledDate)
        tasks.append(task)
        saveTasks()
    }
    
    func updateTaskStatus(id: UUID, status: TaskStatus) {
        if let index = tasks.firstIndex(where: { $0.id == id }) {
            tasks[index].status = status
            saveTasks()
        }
    }
    
    func deleteTask(id: UUID) {
        tasks.removeAll { $0.id == id }
        saveTasks()
    }
    
    private func saveTasks() {
        if let data = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
    
    private func loadTasks() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let loadedTasks = try? JSONDecoder().decode([TaskItem].self, from: data) else {
            return
        }
        tasks = loadedTasks
    }
    
    private func addSampleTasks() {
        tasks = [
            TaskItem(title: "Review PR #42", description: "Check code style and tests", assignee: .user, status: .pending, scheduledDate: Date()),
            TaskItem(title: "Monitor server logs", description: "Watch for errors in production", assignee: .agent, status: .inProgress, scheduledDate: Date()),
            TaskItem(title: "Draft weekly report", description: "Summarize key metrics", assignee: .user, status: .pending, scheduledDate: Date().addingTimeInterval(3600))
        ]
        saveTasks()
    }
    
    func getContextString() -> String {
        let userTasks = tasks.filter { $0.assignee == .user && $0.status != .completed }.map { "- \($0.title) (\($0.status))" }.joined(separator: "\n")
        let agentTasks = tasks.filter { $0.assignee == .agent && $0.status != .completed }.map { "- \($0.title) (\($0.status))" }.joined(separator: "\n")
        
        return """
        USER TASKS:
        \(userTasks.isEmpty ? "(None)" : userTasks)
        
        AGENT TASKS:
        \(agentTasks.isEmpty ? "(None)" : agentTasks)
        """
    }
}
