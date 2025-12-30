import Foundation
import ServiceManagement
import OSLog

// MARK: - Watchdog Service Manager
class WatchdogService: ObservableObject {
    static let shared = WatchdogService()
    
    private let logger = Logger(subsystem: "com.mcp.agent", category: "WatchdogService")
    private let serviceIdentifier = "com.mcp.agent.AgentDaemon"
    
    @Published var isServiceInstalled = false
    @Published var serviceStatus: SMAppService.Status = .notRegistered
    @Published var lastHealthCheck: Date?
    @Published var restartCount = 0
    
    private let healthCheckQueue = DispatchQueue(label: "watchdog.health", qos: .utility)
    private var healthCheckTimer: Timer?
    
    private init() {
        Task {
            await checkServiceStatus()
        }
        
        startHealthMonitoring()
    }
    
    // MARK: - Service Management
    
    func installAndStartService() async throws {
        logger.info("Installing and starting watchdog service")
        
        // Create the agent daemon bundle
        try await createAgentDaemonBundle()
        
        // Register the service with launchd
        try SMAppService.mainApp.register()
        
        // Wait a moment for registration
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        await checkServiceStatus()
        
        if isServiceInstalled {
            logger.info("Watchdog service installed successfully")
        } else {
            throw WatchdogError.serviceRegistrationFailed
        }
    }
    
    func uninstallService() async throws {
        logger.info("Uninstalling watchdog service")
        
        try await SMAppService.mainApp.unregister()
        
        // Clean up daemon files
        try? FileManager.default.removeItem(at: agentDaemonPath())
        
        await checkServiceStatus()
    }
    
    private func createAgentDaemonBundle() async throws {
        let bundlePath = agentDaemonPath()
        
        // Create Info.plist
        let infoPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleExecutable</key>
            <string>AgentDaemon</string>
            <key>CFBundleIdentifier</key>
            <string>\(serviceIdentifier)</string>
            <key>CFBundleInfoDictionaryVersion</key>
            <string>6.0</string>
            <key>CFBundleName</key>
            <string>Agent Daemon</string>
            <key>CFBundlePackageType</key>
            <string>BNDL</string>
            <key>CFBundleShortVersionString</key>
            <string>1.0</string>
            <key>CFBundleVersion</key>
            <string>1</string>
            <key>LSUIElement</key>
            <true/>
            <key>LSMultipleJobSeparationsDisabled</key>
            <true/>
        </dict>
        </plist>
        """
        
        try infoPlist.write(to: bundlePath.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        
        // Create the daemon executable (this is a stub - you would include a real binary)
        let daemonCode = """
        #!/bin/bash
        # Agent Daemon Stub
        # This would be the actual daemon executable
        
        # Set up environment
        export AGENT_LOG_DIR="$HOME/Library/Logs/MCP-Agent"
        mkdir -p "$AGENT_LOG_DIR"
        
        # Launch the actual agent process
        open -a MCP-Agent --args --daemon-mode
        
        # Keep the daemon alive
        while true; do
            if ! pgrep -f "MCP-Agent" > /dev/null; then
                echo "$(date): Agent process died, restarting" >> "$AGENT_LOG_DIR/daemon.log"
                open -a MCP-Agent --args --daemon-mode
            fi
            sleep 30
        done
        """
        
        let daemonPath = bundlePath.appendingPathComponent("AgentDaemon")
        try daemonCode.write(to: daemonPath, atomically: true, encoding: .utf8)
        
        // Make executable
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: daemonPath.path)
        
        logger.info("Created agent daemon bundle at \(bundlePath.path)")
    }
    
    private func agentDaemonPath() -> URL {
        let libraryPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("MCP-Agent")
            .appendingPathComponent("AgentDaemon.bundle")
        
        try? FileManager.default.createDirectory(at: libraryPath, withIntermediateDirectories: true)
        return libraryPath
    }
    
    private func checkServiceStatus() async {
        await MainActor.run {
            serviceStatus = SMAppService.mainApp.status
            isServiceInstalled = serviceStatus == .enabled
        }
    }
    
    // MARK: - Health Monitoring
    
    private func startHealthMonitoring() {
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task {
                await self?.performHealthCheck()
            }
        }
    }
    
    private func performHealthCheck() async {
        await MainActor.run {
            lastHealthCheck = Date()
        }
        
        let agentProcess = "BuddyMCP"
        
        let isRunning = await withCheckedContinuation { continuation in
            let task = Process()
            task.launchPath = "/usr/bin/pgrep"
            task.arguments = ["-f", agentProcess]
            
            let outputPipe = Pipe()
            task.standardOutput = outputPipe
            
            task.terminationHandler = { process in
                let status = process.terminationStatus
                continuation.resume(returning: status == 0)
            }
            
            task.launch()
        }
        
        if !isRunning {
            await handleAgentFailure()
        } else {
            await performAdditionalHealthChecks()
        }
    }
    
    private func performAdditionalHealthChecks() async {
        // Check memory usage
        let memoryWarning = await checkMemoryUsage()
        
        // Check disk space
        let diskWarning = await checkDiskSpace()
        
        // Check network connectivity
        let networkWarning = await checkNetworkConnectivity()
        
        if memoryWarning || diskWarning || networkWarning {
            logger.warning("Health check warnings: memory=\(memoryWarning), disk=\(diskWarning), network=\(networkWarning)")
            // Could trigger restart or alert here
        }
    }
    
    private func checkMemoryUsage() async -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/python3"
        task.arguments = ["-c", """
        import psutil, os
        process = psutil.Process(os.getpid())
        memory_mb = process.memory_info().rss / 1024 / 1024
        print(f'{memory_mb:.1f}')
        """]
        
        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        
        return await withCheckedContinuation { continuation in
            task.terminationHandler = { process in
                let status = process.terminationStatus
                if status == 0 {
                    let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let memoryStr = output, let memoryMB = Double(memoryStr) {
                        // Warn if using more than 8GB
                        let shouldWarn = memoryMB > 8192
                        continuation.resume(returning: shouldWarn)
                        return
                    }
                }
                continuation.resume(returning: false)
            }
            task.launch()
        }
    }
    
    private func checkDiskSpace() async -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/df"
        task.arguments = ["-h", "/"]
        
        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        
        return await withCheckedContinuation { continuation in
            task.terminationHandler = { process in
                let status = process.terminationStatus
                if status == 0 {
                    let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    // Check if available space is less than 1GB
                    let shouldWarn = output.contains("< 1.0G")
                    continuation.resume(returning: shouldWarn)
                    return
                }
                continuation.resume(returning: false)
            }
            task.launch()
        }
    }
    
    private func checkNetworkConnectivity() async -> Bool {
        let url = URL(string: "https://www.google.com")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode != 200
        } catch {
            return true // Warning if network fails
        }
    }
    
    private func handleAgentFailure() async {
        logger.error("Agent process not running, attempting restart")
        
        restartCount += 1
        
        // Try to restart the agent
        let restartSuccess = await withCheckedContinuation { continuation in
            let task = Process()
            task.launchPath = "/usr/bin/open"
            task.arguments = ["-a", "BuddyMCP", "--args", "--daemon-mode", "--restart"]
            
            task.terminationHandler = { process in
                let success = process.terminationStatus == 0
                continuation.resume(returning: success)
            }
            
            task.launch()
        }
        
        if restartSuccess {
            logger.info("Successfully restarted agent")
            // Wait a moment and check if it's running
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            let isRunning = await checkIfAgentIsRunning()
            if !isRunning {
                logger.error("Restart failed - agent still not running")
                await escalateFailure()
            }
        } else {
            logger.error("Failed to restart agent")
            await escalateFailure()
        }
    }
    
    private func checkIfAgentIsRunning() async -> Bool {
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.launchPath = "/usr/bin/pgrep"
            // Use -f to match against full command line, which catches "swift run" or script wrappers
            task.arguments = ["-f", "BuddyMCP"]
            
            task.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus == 0)
            }
            
            task.launch()
        }
    }
    
    private func escalateFailure() async {
        // Send escalation to user about agent failure
        logger.critical("Agent failed to restart, escalating to user")
        
        do {
            try await MCPManager.shared.callTool("escalate_to_user", arguments: [
                "reason": "Agent watchdog failure",
                "message": "The MCP Agent has failed and the watchdog was unable to restart it automatically. Please check the system logs and restart the application manually."
            ])
        } catch {
            logger.error("Failed to send escalation: \(error.localizedDescription)")
        }
    }
    
    func forceRestartAgent() async throws {
        logger.info("Force restarting agent")
        
        // Kill existing process
        let killSuccess = await withCheckedContinuation { continuation in
            let task = Process()
            task.launchPath = "/usr/bin/pkill"
            task.arguments = ["-9", "BuddyMCP"]
            
            task.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus == 0)
            }
            
            task.launch()
        }
        
        if killSuccess {
            // Start new process
            let startSuccess = await withCheckedContinuation { continuation in
                let task = Process()
                task.launchPath = "/usr/bin/open"
                task.arguments = ["-a", "BuddyMCP", "--args", "--daemon-mode"]
                
                task.terminationHandler = { process in
                    continuation.resume(returning: process.terminationStatus == 0)
                }
                
                task.launch()
            }
            
            if !startSuccess {
                throw WatchdogError.forceRestartFailed
            }
            
            logger.info("Agent force restarted successfully")
        } else {
            throw WatchdogError.forceKillFailed
        }
    }
}

// MARK: - Watchdog Errors
enum WatchdogError: Error, LocalizedError {
    case serviceRegistrationFailed
    case serviceUnregistrationFailed
    case forceRestartFailed
    case forceKillFailed
    
    var errorDescription: String? {
        switch self {
        case .serviceRegistrationFailed:
            return "Failed to register service with launchd"
        case .serviceUnregistrationFailed:
            return "Failed to unregister service from launchd"
        case .forceRestartFailed:
            return "Failed to force restart the agent"
        case .forceKillFailed:
            return "Failed to kill existing agent process"
        }
    }
}
