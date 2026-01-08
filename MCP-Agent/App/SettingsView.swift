import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var mcpManager = MCPManager.shared
    @State private var showingAddServerSheet = false
    @State private var newServerName = ""
    @State private var newServerCommand = "" // For Stdio
    @State private var newServerURL = "" // For SSE
    @State private var newServerTypeString = "stdio" // "stdio" or "sse"
    @State private var newServerTintHex = ""
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom Tab Bar
            HStack(spacing: 0) {
                TabButton(title: "SERVERS", icon: "server.rack", isSelected: selectedTab == 0) { selectedTab = 0 }
                Rectangle().frame(width: 1).foregroundColor(Theme.borderColor)
                TabButton(title: "TOOLS", icon: "hammer", isSelected: selectedTab == 1) { selectedTab = 1 }
                Rectangle().frame(width: 1).foregroundColor(Theme.borderColor)
                TabButton(title: "LLM", icon: "sparkles", isSelected: selectedTab == 2) { selectedTab = 2 }
                Rectangle().frame(width: 1).foregroundColor(Theme.borderColor)
                TabButton(title: "DEBUG", icon: "ladybug", isSelected: selectedTab == 3) { selectedTab = 3 }
                Rectangle().frame(width: 1).foregroundColor(Theme.borderColor)
                TabButton(title: "THEME", icon: "paintbrush", isSelected: selectedTab == 4) { selectedTab = 4 }
                Rectangle().frame(width: 1).foregroundColor(Theme.borderColor)
                Spacer()
            }
            .frame(height: 44)
            .background(Theme.background)
            .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.borderColor), alignment: .bottom)
            
            // Content
            Group {
                if selectedTab == 0 {
                    ServerListView(
                        showingAddServerSheet: $showingAddServerSheet,
                        newServerName: $newServerName,
                        newServerCommand: $newServerCommand,
                        newServerURL: $newServerURL,
                        newServerTypeString: $newServerTypeString,
                        newServerTintHex: $newServerTintHex
                    )
                } else if selectedTab == 1 {
                    ToolListView()
                } else if selectedTab == 2 {
                    LLMSettingsView()
                } else if selectedTab == 3 {
                    DebugSettingsView()
                } else {
                    ThemeSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            
            Rectangle().frame(height: 1).foregroundColor(Theme.borderColor)
            
            HStack {
                Spacer()
                Button("DONE") {
                    dismiss()
                }
                .newsprintButton(isPrimary: true)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Theme.background)
        }
        .frame(width: 700, height: 500)
        .background(Theme.background)
    }
}

struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(title)
                    .font(Theme.uiFont(size: 12, weight: .bold))
                    .tracking(1)
            }
            .padding(.horizontal, 24)
            .frame(maxHeight: .infinity)
            .background(isSelected ? Theme.borderColor : Theme.background) // Use BorderColor for Active Tab BG
            .foregroundColor(isSelected ? Theme.background : Theme.borderColor) // Use BorderColor for Inactive Text
        }
        .buttonStyle(.plain)
    }
}

struct ServerListView: View {
    @ObservedObject var mcpManager = MCPManager.shared
    @Binding var showingAddServerSheet: Bool
    @Binding var newServerName: String
    @Binding var newServerCommand: String
    @Binding var newServerURL: String
    @Binding var newServerTypeString: String
    @Binding var newServerTintHex: String
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(mcpManager.servers) { server in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Rectangle()
                                        .fill(Color(hex: server.tintHex ?? "FFFFFF"))
                                        .frame(width: 10, height: 10)
                                        .overlay(Rectangle().stroke(Theme.borderColor, lineWidth: 1))
                                    Text(server.name)
                                        .font(Theme.headlineFont(size: 16))
                                }
                                
                                HStack {
                                    Image(systemName: serverIcon(for: server.type))
                                        .font(.caption)
                                    Text(serverDescription(for: server.type).uppercased())
                                        .font(Theme.monoFont(size: 10))
                                        .foregroundColor(Theme.inkBlack.opacity(0.6))
                                }
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: Binding(
                                get: { server.isEnabled },
                                set: { _ in mcpManager.toggleServer(server) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            
                            if case .internal = server.type {
                                Image(systemName: "lock.fill")
                                    .foregroundColor(Theme.inkBlack.opacity(0.4))
                                    .font(.caption)
                                    .frame(width: 20)
                            } else {
                                Button(action: {
                                    mcpManager.removeServer(server)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(Theme.editorialRed)
                                }
                                .buttonStyle(.plain)
                                .frame(width: 20)
                            }
                        }
                        .padding(16)
                        .newsprintCard()
                    }
                }
                .padding()
            }
            
            Rectangle().frame(height: 1).foregroundColor(Theme.borderColor)
            
            HStack {
                Spacer()
                Button(action: {
                    newServerTintHex = MCPManager.shared.nextAvailableTintHex()
                    showingAddServerSheet = true
                }) {
                    Label("ADD SERVER", systemImage: "plus")
                }
                .newsprintButton(isPrimary: false)
                .padding()
            }
            .background(Theme.background)
        }
        .sheet(isPresented: $showingAddServerSheet) {
            AddServerView(
                isPresented: $showingAddServerSheet,
                name: $newServerName,
                command: $newServerCommand,
                url: $newServerURL,
                typeString: $newServerTypeString,
                tintHex: $newServerTintHex
            )
        }
    }
    
    func serverIcon(for type: MCPServer.ServerType) -> String {
        switch type {
        case .stdio: return "terminal"
        case .sse: return "globe"
        case .internal: return "cpu"
        }
    }
    
    func serverDescription(for type: MCPServer.ServerType) -> String {
        switch type {
        case .stdio: return "Command (Stdio)"
        case .sse: return "Remote (SSE)"
        case .internal: return "Built-in"
        }
    }
}

struct AddServerView: View {
    @Binding var isPresented: Bool
    @Binding var name: String
    @Binding var command: String
    @Binding var url: String
    @Binding var typeString: String
    @Binding var tintHex: String
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("ADD SERVER")
                    .font(Theme.headlineFont(size: 18))
                Spacer()
            }
            .padding()
            .background(Theme.background)
            .border(width: 1, edges: [.bottom], color: Theme.borderColor)
            
            VStack(alignment: .leading, spacing: 20) {
                // Name Field
                VStack(alignment: .leading, spacing: 4) {
                    Text("NAME")
                        .font(Theme.uiFont(size: 10, weight: .bold))
                    TextField("My Server", text: $name)
                        .newsprintInput()
                }
                
                // Type Picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("SERVER TYPE")
                        .font(Theme.uiFont(size: 10, weight: .bold))
                    Picker("", selection: $typeString) {
                        Text("Command (Stdio)").tag("stdio")
                        Text("Remote / Local Server (SSE)").tag("sse")
                    }
                    .pickerStyle(.segmented)
                }
                
                Rectangle().frame(height: 1).foregroundColor(Theme.borderColor.opacity(0.2))
                
                // Dynamic Fields
                if typeString == "stdio" {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("COMMAND LINE")
                            .font(Theme.uiFont(size: 10, weight: .bold))
                        TextField("e.g., npx -y @modelcontextprotocol/memory", text: $command)
                            .newsprintInput()
                        Text("Enter the full command to execute.")
                            .font(Theme.bodyFont(size: 12))
                            .italic()
                            .foregroundColor(Theme.inkBlack.opacity(0.6))
                            .padding(.top, 4)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SERVER URL")
                            .font(Theme.uiFont(size: 10, weight: .bold))
                        TextField("e.g., http://localhost:8000/sse", text: $url)
                            .newsprintInput()
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("TINT COLOR")
                        .font(Theme.uiFont(size: 10, weight: .bold))
                    TintPalettePicker(selectedHex: $tintHex)
                }
            }
            .padding(24)
            .background(Theme.background)
            
            Spacer()
            
            HStack {
                Button("CANCEL") {
                    isPresented = false
                }
                .newsprintButton(isPrimary: false)
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("ADD SERVER") {
                    addServer()
                }
                .newsprintButton(isPrimary: true)
                .disabled(isAddDisabled)
            }
            .padding()
            .background(Theme.background)
            .border(width: 1, edges: [.top], color: Theme.borderColor)
        }
        .frame(width: 500, height: 400)
        .background(Theme.background)
        .onAppear {
            if tintHex.isEmpty {
                tintHex = MCPManager.shared.nextAvailableTintHex()
            }
        }
    }
    
    var isAddDisabled: Bool {
        if name.isEmpty { return true }
        if typeString == "stdio" && command.isEmpty { return true }
        if typeString == "sse" && url.isEmpty { return true }
        if tintHex.isEmpty { return true }
        return false
    }
    
    func addServer() {
        let type: MCPServer.ServerType
        if typeString == "stdio" {
            let parts = command.split(separator: " ").map { String($0) }
            if let cmd = parts.first {
                let args = Array(parts.dropFirst())
                type = .stdio(command: cmd, arguments: args)
            } else {
                return
            }
        } else {
            if let urlObj = URL(string: url) {
                type = .sse(url: urlObj)
            } else {
                return
            }
        }
        
        MCPManager.shared.addServer(name: name, type: type, tintHex: tintHex)
        isPresented = false
        
        // Reset fields
        name = ""
        command = ""
        url = ""
        tintHex = MCPManager.shared.nextAvailableTintHex()
    }
}

struct ToolListView: View {
    @ObservedObject var mcpManager = MCPManager.shared
    @State private var showingUsageLog = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                AgentUsageSummaryView(showingUsageLog: $showingUsageLog)
                
                ForEach(mcpManager.servers) { server in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(server.name.uppercased())
                            .font(Theme.uiFont(size: 12, weight: .bold))
                            .tracking(2)
                            .padding(.bottom, 4)
                            .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.borderColor), alignment: .bottom)
                        
                        if server.tools.isEmpty {
                            Text("No tools found")
                                .font(Theme.bodyFont(size: 14))
                                .italic()
                                .foregroundColor(Theme.inkBlack.opacity(0.6))
                        } else {
                            ForEach(server.tools) { tool in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(tool.name)
                                            .font(Theme.monoFont(size: 13))
                                        if let desc = tool.description {
                                            Text(desc)
                                                .font(Theme.bodyFont(size: 13))
                                                .foregroundColor(Theme.inkBlack.opacity(0.7))
                                                .lineLimit(2)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    Toggle("", isOn: Binding(
                                        get: { tool.isEnabled },
                                        set: { _ in mcpManager.toggleTool(tool, in: server) }
                                    ))
                                    .toggleStyle(.switch)
                                    .labelsHidden()
                                }
                                .padding(12)
                                .newsprintCard()
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .sheet(isPresented: $showingUsageLog) {
            ToolUsageLogView()
        }
        .background(Theme.background)
    }
}

struct AgentUsageSummaryView: View {
    @ObservedObject var usageManager = ToolUsageManager.shared
    @Binding var showingUsageLog: Bool
    
    private let toolColumns = [GridItem(.adaptive(minimum: 150), spacing: 8)]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AGENT TOOL USAGE")
                    .font(Theme.uiFont(size: 12, weight: .bold))
                    .tracking(2)
                Spacer()
                Button {
                    showingUsageLog = true
                } label: {
                    Label("OPEN LOG", systemImage: "clock.arrow.circlepath")
                        .labelStyle(.titleAndIcon)
                }
                .newsprintButton(isPrimary: false)
            }
            
            if usageManager.isActive {
                HStack(spacing: 10) {
                    Rectangle()
                        .fill(Color(hex: usageManager.activeTintHex ?? MCPManager.tintPalette.first ?? "D6EBD1"))
                        .frame(width: 10, height: 10)
                        .overlay(Rectangle().stroke(Theme.borderColor, lineWidth: 1))
                    Text("\(usageManager.activeAgentName.isEmpty ? "Agent" : usageManager.activeAgentName) is using \(usageManager.activeToolName) on \(usageManager.activeServerName)")
                        .font(Theme.bodyFont(size: 12))
                }
                .padding(10)
                .newsprintCard()
            }
            
            if usageManager.agentSummaries.isEmpty {
                Text("No agent tool activity yet.")
                    .font(Theme.bodyFont(size: 13))
                    .foregroundColor(Theme.inkBlack.opacity(0.7))
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(usageManager.agentSummaries) { summary in
                        AgentSummaryRow(summary: summary, columns: toolColumns)
                    }
                }
            }
        }
        .padding(16)
        .newsprintCard()
    }
}

struct AgentSummaryRow: View {
    let summary: AgentUsageSummary
    let columns: [GridItem]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(summary.agentName)
                    .font(Theme.headlineFont(size: 15))
                Spacer()
                if let lastUsed = summary.lastUsedAt {
                    Text("Last used \(relativeDate(lastUsed))")
                        .font(Theme.monoFont(size: 10))
                        .foregroundColor(Theme.inkBlack.opacity(0.7))
                }
            }
            
            if summary.tools.isEmpty {
                Text("No tools recorded for this agent yet.")
                    .font(Theme.bodyFont(size: 12))
                    .foregroundColor(Theme.inkBlack.opacity(0.7))
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(summary.tools, id: \.self) { tool in
                        Text(tool)
                            .font(Theme.monoFont(size: 12))
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(Theme.background)
                            .overlay(Rectangle().stroke(Theme.borderColor, lineWidth: 1))
                    }
                }
            }
        }
        .padding(12)
        .newsprintCard()
    }
    
    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct ToolUsageLogView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var usageManager = ToolUsageManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("AGENT TOOL USAGE LOG")
                    .font(Theme.headlineFont(size: 16))
                Spacer()
                Button("CLOSE") {
                    dismiss()
                }
                .newsprintButton(isPrimary: false)
            }
            .padding()
            .background(Theme.background)
            .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.borderColor), alignment: .bottom)
            
            if usageManager.logEntries.isEmpty {
                VStack {
                    Spacer()
                    Text("No tool usage has been recorded yet.")
                        .font(Theme.bodyFont(size: 14))
                        .foregroundColor(Theme.inkBlack.opacity(0.7))
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(usageManager.logEntries.reversed())) { entry in
                            ToolUsageLogRow(entry: entry)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 560, minHeight: 440)
        .background(Theme.background)
    }
}

struct ToolUsageLogRow: View {
    let entry: ToolUsageLogEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                statusBadge(entry)
                Text(entry.toolName)
                    .font(Theme.monoFont(size: 13))
                Spacer()
                Text(entry.durationDescription.uppercased())
                    .font(Theme.monoFont(size: 10))
                    .foregroundColor(Theme.inkBlack.opacity(0.7))
            }
            
            Text("Agent: \(entry.agentName)")
                .font(Theme.bodyFont(size: 12))
            Text("Server: \(entry.serverName)")
                .font(Theme.bodyFont(size: 12))
            
            HStack(spacing: 8) {
                Text(timestamp(entry.startedAt))
                    .font(Theme.monoFont(size: 10))
                    .foregroundColor(Theme.inkBlack.opacity(0.7))
                if let endedAt = entry.completedAt {
                    Text("→ \(timestamp(endedAt))")
                        .font(Theme.monoFont(size: 10))
                        .foregroundColor(Theme.inkBlack.opacity(0.7))
                }
            }
        }
        .padding(12)
        .newsprintCard()
    }
    
    private func statusBadge(_ entry: ToolUsageLogEntry) -> some View {
        let color: Color
        if let succeeded = entry.succeeded {
            color = succeeded ? Theme.borderColor : Theme.editorialRed
        } else {
            color = Theme.inkBlack
        }
        return HStack(spacing: 6) {
            Rectangle()
                .fill(Color(hex: entry.tintHex ?? MCPManager.tintPalette.first ?? "D6EBD1"))
                .frame(width: 10, height: 10)
                .overlay(Rectangle().stroke(Theme.borderColor, lineWidth: 1))
            Text(entry.statusLabel)
                .font(Theme.monoFont(size: 10))
                .foregroundColor(color)
        }
    }
    
    private func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

struct ThemeSettingsView: View {
    @ObservedObject var themeManager = ThemeManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("SELECT THEME")
                .font(Theme.uiFont(size: 12, weight: .bold))
                .tracking(2)
                .padding(.bottom, 8)
                .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.borderColor), alignment: .bottom)
            
            ForEach(ThemeType.allCases) { theme in
                Button(action: {
                    themeManager.currentTheme = theme
                }) {
                    HStack {
                        Text(theme.displayName.uppercased())
                            .font(Theme.headlineFont(size: 16))
                            .foregroundColor(Theme.inkBlack)
                        Spacer()
                        if themeManager.currentTheme == theme {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(Theme.borderColor) // Checkmark matches border/accent
                        }
                    }
                    .padding()
                    .newsprintCard()
                    .overlay(
                        Rectangle()
                            .stroke(Theme.borderColor, lineWidth: themeManager.currentTheme == theme ? 4 : 1)
                    )
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
        }
        .padding()
        .background(Theme.background)
    }
}

struct TintPalettePicker: View {
    @Binding var selectedHex: String
    
    private let columns = Array(repeating: GridItem(.fixed(24), spacing: 8), count: 6)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(MCPManager.tintPalette, id: \.self) { hex in
                    Button(action: {
                        selectedHex = hex
                    }) {
                        Rectangle()
                            .fill(Color(hex: hex))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Rectangle()
                                    .stroke(Theme.borderColor, lineWidth: selectedHex == hex ? 2 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Text("Selected: #\(selectedHex)")
                .font(Theme.monoFont(size: 10))
                .foregroundColor(Theme.inkBlack.opacity(0.7))
        }
    }
}
