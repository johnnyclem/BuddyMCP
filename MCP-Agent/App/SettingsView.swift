import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var mcpManager = MCPManager.shared
    @State private var showingAddServerSheet = false
    @State private var newServerName = ""
    @State private var newServerCommand = "" // For Stdio
    @State private var newServerURL = "" // For SSE
    @State private var newServerTypeString = "stdio" // "stdio" or "sse"
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom Tab Bar
            HStack(spacing: 0) {
                TabButton(title: "SERVERS", icon: "server.rack", isSelected: selectedTab == 0) { selectedTab = 0 }
                Rectangle().frame(width: 1).foregroundColor(Theme.inkBlack)
                TabButton(title: "TOOLS", icon: "hammer", isSelected: selectedTab == 1) { selectedTab = 1 }
                Rectangle().frame(width: 1).foregroundColor(Theme.inkBlack)
                TabButton(title: "THEME", icon: "paintbrush", isSelected: selectedTab == 2) { selectedTab = 2 }
                Rectangle().frame(width: 1).foregroundColor(Theme.inkBlack)
                Spacer()
            }
            .frame(height: 44)
            .background(Theme.background)
            .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.inkBlack), alignment: .bottom)
            
            // Content
            Group {
                if selectedTab == 0 {
                    ServerListView(
                        showingAddServerSheet: $showingAddServerSheet,
                        newServerName: $newServerName,
                        newServerCommand: $newServerCommand,
                        newServerURL: $newServerURL,
                        newServerTypeString: $newServerTypeString
                    )
                } else if selectedTab == 1 {
                    ToolListView()
                } else {
                    ThemeSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            
            Rectangle().frame(height: 1).foregroundColor(Theme.inkBlack)
            
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
            .background(isSelected ? Theme.inkBlack : Theme.background)
            .foregroundColor(isSelected ? Theme.background : Theme.inkBlack)
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
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(mcpManager.servers) { server in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(server.name)
                                    .font(Theme.headlineFont(size: 16))
                                
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
            
            Rectangle().frame(height: 1).foregroundColor(Theme.inkBlack)
            
            HStack {
                Spacer()
                Button(action: {
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
                typeString: $newServerTypeString
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
            .border(width: 1, edges: [.bottom], color: Theme.inkBlack)
            
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
                
                Rectangle().frame(height: 1).foregroundColor(Theme.inkBlack.opacity(0.2))
                
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
            .border(width: 1, edges: [.top], color: Theme.inkBlack)
        }
        .frame(width: 500, height: 400)
        .background(Theme.background)
    }
    
    var isAddDisabled: Bool {
        if name.isEmpty { return true }
        if typeString == "stdio" && command.isEmpty { return true }
        if typeString == "sse" && url.isEmpty { return true }
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
        
        MCPManager.shared.addServer(name: name, type: type)
        isPresented = false
        
        // Reset fields
        name = ""
        command = ""
        url = ""
    }
}

struct ToolListView: View {
    @ObservedObject var mcpManager = MCPManager.shared
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(mcpManager.servers) { server in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(server.name.uppercased())
                            .font(Theme.uiFont(size: 12, weight: .bold))
                            .tracking(2)
                            .padding(.bottom, 4)
                            .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.inkBlack), alignment: .bottom)
                        
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
        .background(Theme.background)
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
                .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.inkBlack), alignment: .bottom)
            
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
                                .foregroundColor(Theme.inkBlack)
                        }
                    }
                    .padding()
                    .newsprintCard()
                    .overlay(
                        Rectangle()
                            .stroke(Theme.inkBlack, lineWidth: themeManager.currentTheme == theme ? 4 : 1)
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