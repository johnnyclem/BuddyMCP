import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var mcpManager = MCPManager.shared
    @State private var showingAddServerSheet = false
    @State private var newServerName = ""
    @State private var newServerCommand = "" // For Stdio
    @State private var newServerURL = "" // For SSE
    @State private var newServerTypeString = "stdio" // "stdio" or "sse"
    
    var body: some View {
        VStack(spacing: 0) {
            TabView {
                ServerListView(
                    showingAddServerSheet: $showingAddServerSheet,
                    newServerName: $newServerName,
                    newServerCommand: $newServerCommand,
                    newServerURL: $newServerURL,
                    newServerTypeString: $newServerTypeString
                )
                .tabItem {
                    Label("Servers", systemImage: "server.rack")
                }
                
                ToolListView()
                    .tabItem {
                        Label("Tools", systemImage: "hammer")
                    }
            }
            .frame(width: 700, height: 500)
            .padding()
            
            Divider()
            
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
        }
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
            List {
                ForEach(mcpManager.servers) { server in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(server.name)
                                .font(.headline)
                            
                            HStack {
                                Image(systemName: serverIcon(for: server.type))
                                    .font(.caption)
                                Text(serverDescription(for: server.type))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Toggle("Enabled", isOn: Binding(
                            get: { server.isEnabled },
                            set: { _ in mcpManager.toggleServer(server) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        
                        if case .internal = server.type {
                            // Can't delete internal server
                            Image(systemName: "lock.fill")
                                .foregroundColor(.gray)
                                .font(.caption)
                                .frame(width: 20)
                        } else {
                            Button(action: {
                                mcpManager.removeServer(server)
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                            .frame(width: 20)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .listStyle(.inset)
            
            Divider()
            
            HStack {
                Spacer()
                Button(action: {
                    showingAddServerSheet = true
                }) {
                    Label("Add Server", systemImage: "plus")
                }
                .controlSize(.regular)
                .padding()
            }
            .background(Color(nsColor: .windowBackgroundColor))
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
        VStack(alignment: .leading, spacing: 20) {
            Text("Add MCP Server")
                .font(.title2)
                .bold()
            
            VStack(alignment: .leading, spacing: 12) {
                // Name Field
                VStack(alignment: .leading, spacing: 4) {
                    Text("Name")
                        .font(.headline)
                    TextField("My Server", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                
                // Type Picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("Server Type")
                        .font(.headline)
                    Picker("", selection: $typeString) {
                        Text("Command (Stdio)").tag("stdio")
                        Text("Remote / Local Server (SSE)").tag("sse")
                    }
                    .pickerStyle(.segmented)
                }
                
                Divider().padding(.vertical, 8)
                
                // Dynamic Fields
                if typeString == "stdio" {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Command Line")
                            .font(.headline)
                        TextField("e.g., npx -y @modelcontextprotocol/memory", text: $command)
                            .textFieldStyle(.roundedBorder)
                        Text("Enter the full command to execute. The agent will manage the process.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Server URL")
                            .font(.headline)
                        TextField("e.g., http://localhost:8000/sse", text: $url)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            
            Spacer()
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Add Server") {
                    addServer()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAddDisabled)
                // Note: removed keyboardShortcut(.defaultAction) here to avoid conflict with the Done button in parent
            }
        }
        .padding(24)
        .frame(width: 500, height: 350)
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
        List {
            ForEach(mcpManager.servers) { server in
                Section(header: Text(server.name)) {
                    ForEach(server.tools) { tool in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(tool.name)
                                    .font(.system(.body, design: .monospaced))
                                if let desc = tool.description {
                                    Text(desc)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
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
                        .padding(.vertical, 4)
                    }
                    if server.tools.isEmpty {
                        Text("No tools found")
                            .font(.caption)
                            .italic()
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .listStyle(.inset)
    }
}