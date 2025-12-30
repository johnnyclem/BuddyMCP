import SwiftUI

struct TimelineView: View {
    @ObservedObject var taskManager = TaskManager.shared
    @ObservedObject var approvalManager = ApprovalManager.shared
    @State private var showingAddTask = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Main Timeline
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Up Next")
                        .font(.title2)
                        .bold()
                    Spacer()
                    Button(action: { showingAddTask = true }) {
                        Label("New Task", systemImage: "plus")
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                
                Divider()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !approvalManager.pendingRequests.isEmpty {
                            ApprovalSection(requests: approvalManager.pendingRequests)
                        }
                        
                        TaskSection(title: "Agent Working On", tasks: taskManager.tasks.filter { $0.assignee == .agent && $0.status == .inProgress })
                        
                        TaskSection(title: "User To-Do", tasks: taskManager.tasks.filter { $0.assignee == .user && $0.status != .completed })
                        
                        TaskSection(title: "Upcoming (Agent)", tasks: taskManager.tasks.filter { $0.assignee == .agent && $0.status == .pending })
                        
                        if taskManager.tasks.isEmpty {
                            Text("No tasks scheduled.")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 40)
                        }
                    }
                    .padding()
                }
            }
            .frame(minWidth: 400)
            
            Divider()
            
            // Sidebar / Chat Placeholder
            ChatView()
                .frame(width: 300)
        }
        .sheet(isPresented: $showingAddTask) {
            AddTaskView(isPresented: $showingAddTask)
        }
    }
}

struct ApprovalSection: View {
    let requests: [ApprovalRequest]
    @ObservedObject var approvalManager = ApprovalManager.shared
    
    var body: some View {
        VStack(alignment: .leading) {
            Label("Approvals Required", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundColor(.orange)
            
            ForEach(requests) { request in
                HStack {
                    VStack(alignment: .leading) {
                        Text(request.toolName).font(.headline)
                        Text(request.arguments.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    Spacer()
                    
                    HStack {
                        Button("Deny") {
                            approvalManager.denyRequest(request)
                        }
                        Button("Approve") {
                            approvalManager.approveRequest(request)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.3), lineWidth: 1))
            }
        }
        .padding(.bottom)
    }
}

struct TaskSection: View {
    let title: String
    let tasks: [TaskItem]
    
    var body: some View {
        if !tasks.isEmpty {
            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                ForEach(tasks) { task in
                    TaskRow(task: task)
                }
            }
        }
    }
}

struct TaskRow: View {
    let task: TaskItem
    @ObservedObject var taskManager = TaskManager.shared
    
    var body: some View {
        HStack {
            Image(systemName: iconForStatus(task.status))
                .foregroundColor(colorForStatus(task.status))
            
            VStack(alignment: .leading) {
                Text(task.title)
                    .strikethrough(task.status == .completed)
                if !task.description.isEmpty {
                    Text(task.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if task.assignee == .user {
                Button(action: {
                    toggleStatus()
                }) {
                    Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }
    
    func toggleStatus() {
        let newStatus: TaskStatus = task.status == .completed ? .pending : .completed
        taskManager.updateTaskStatus(id: task.id, status: newStatus)
    }
    
    func iconForStatus(_ status: TaskStatus) -> String {
        switch status {
        case .pending: return "circle"
        case .inProgress: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle"
        case .skipped: return "arrowshape.turn.up.right.circle"
        }
    }
    
    func colorForStatus(_ status: TaskStatus) -> Color {
        switch status {
        case .inProgress: return .blue
        case .completed: return .green
        case .failed: return .red
        default: return .primary
    }
    }
}

struct AddTaskView: View {
    @Binding var isPresented: Bool
    @State private var title = ""
    @State private var description = ""
    @State private var assignee: TaskAssignee = .user
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add Task").font(.headline)
            
            Form {
                TextField("Title", text: $title)
                TextField("Description", text: $description)
                Picker("Assignee", selection: $assignee) {
                    Text("User").tag(TaskAssignee.user)
                    Text("Agent").tag(TaskAssignee.agent)
                }
            }
            .padding()
            
            HStack {
                Button("Cancel") { isPresented = false }
                Button("Add") {
                    TaskManager.shared.addTask(title: title, description: description, assignee: assignee)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.isEmpty)
            }
        }
        .frame(width: 300, height: 200)
        .padding()
    }
}
