import SwiftUI

struct TimelineView: View {
    @ObservedObject var taskManager = TaskManager.shared
    @ObservedObject var approvalManager = ApprovalManager.shared
    @ObservedObject var themeManager = ThemeManager.shared
    @State private var showingAddTask = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Main Timeline
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("UP NEXT")
                        .font(Theme.headlineFont(size: 20))
                        .tracking(1)
                    Spacer()
                    Button(action: { showingAddTask = true }) {
                        Label("NEW TASK", systemImage: "plus")
                            .font(Theme.uiFont(size: 12, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .border(Theme.inkBlack, width: 1)
                }
                .padding()
                .background(Theme.background)
                .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.inkBlack), alignment: .bottom)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if !approvalManager.pendingRequests.isEmpty {
                            ApprovalSection(requests: approvalManager.pendingRequests)
                        }
                        
                        TaskSection(title: "Working On", tasks: taskManager.tasks.filter { $0.assignee == .agent && $0.status == .inProgress })
                        
                        TaskSection(title: "Your To-Do", tasks: taskManager.tasks.filter { $0.assignee == .user && $0.status != .completed })
                        
                        TaskSection(title: "Upcoming", tasks: taskManager.tasks.filter { $0.assignee == .agent && $0.status == .pending })
                        
                        if taskManager.tasks.isEmpty {
                            Text("No tasks scheduled.")
                                .font(Theme.bodyFont(size: 16))
                                .italic()
                                .foregroundColor(Theme.inkBlack.opacity(0.6))
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 40)
                        }
                    }
                    .padding()
                }
                .background(Theme.background)
            }
            .frame(minWidth: 400)
            .background(Theme.background)
            
            Rectangle().frame(width: 1).foregroundColor(Theme.inkBlack)
            
            // Sidebar / Chat Placeholder
            ChatView()
                .frame(width: 350)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Rectangle()
                    .fill(Theme.editorialRed)
                    .frame(width: 4, height: 16)
                Text("APPROVALS REQUIRED")
                    .font(Theme.uiFont(size: 12, weight: .bold))
                    .tracking(2)
                    .foregroundColor(Theme.editorialRed)
            }
            
            ForEach(requests) { request in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(request.toolName)
                            .font(Theme.headlineFont(size: 16))
                        Text(request.arguments.description)
                            .font(Theme.monoFont(size: 12))
                            .foregroundColor(Theme.inkBlack.opacity(0.7))
                            .lineLimit(2)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        Button("DENY") {
                            approvalManager.denyRequest(request)
                        }
                        .newsprintButton(isPrimary: false)
                        
                        Button("APPROVE") {
                            approvalManager.approveRequest(request)
                        }
                        .newsprintButton(isPrimary: true)
                    }
                }
                .padding()
                .background(Theme.background)
                .overlay(Rectangle().stroke(Theme.editorialRed, lineWidth: 1))
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
            VStack(alignment: .leading, spacing: 12) {
                Text(title.uppercased())
                    .font(Theme.uiFont(size: 12, weight: .bold))
                    .tracking(2)
                    .foregroundColor(Theme.inkBlack.opacity(0.6))
                    .padding(.bottom, 4)
                    .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.inkBlack.opacity(0.3)), alignment: .bottom)
                
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
                .foregroundColor(Theme.inkBlack)
            
            VStack(alignment: .leading) {
                Text(task.title)
                    .font(Theme.bodyFont(size: 16))
                    .strikethrough(task.status == .completed)
                if !task.description.isEmpty {
                    Text(task.description)
                        .font(Theme.bodyFont(size: 14))
                        .foregroundColor(Theme.inkBlack.opacity(0.7))
                }
            }
            
            Spacer()
            
            if task.assignee == .user {
                Button(action: {
                    toggleStatus()
                }) {
                    Image(systemName: task.status == .completed ? "checkmark.square.fill" : "square")
                        .foregroundColor(Theme.inkBlack)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .newsprintCard()
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
}

struct AddTaskView: View {
    @Binding var isPresented: Bool
    @State private var title = ""
    @State private var description = ""
    @State private var assignee: TaskAssignee = .user
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("ADD TASK")
                    .font(Theme.headlineFont(size: 18))
                Spacer()
            }
            .padding()
            .background(Theme.background)
            .border(width: 1, edges: [.bottom], color: Theme.inkBlack)
            
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TITLE")
                        .font(Theme.uiFont(size: 10, weight: .bold))
                    TextField("", text: $title)
                        .newsprintInput()
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("DESCRIPTION")
                        .font(Theme.uiFont(size: 10, weight: .bold))
                    TextField("", text: $description)
                        .newsprintInput()
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("ASSIGNEE")
                        .font(Theme.uiFont(size: 10, weight: .bold))
                    Picker("", selection: $assignee) {
                        Text("User").tag(TaskAssignee.user)
                        Text("Agent").tag(TaskAssignee.agent)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .padding(24)
            .background(Theme.background)
            
            Spacer()
            
            HStack {
                Button("CANCEL") { isPresented = false }
                    .newsprintButton(isPrimary: false)
                Spacer()
                Button("ADD TASK") {
                    TaskManager.shared.addTask(title: title, description: description, assignee: assignee)
                    isPresented = false
                }
                .newsprintButton(isPrimary: true)
                .disabled(title.isEmpty)
            }
            .padding()
            .background(Theme.background)
            .border(width: 1, edges: [.top], color: Theme.inkBlack)
        }
        .frame(width: 400, height: 350)
        .background(Theme.background)
    }
}
