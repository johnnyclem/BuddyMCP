import SwiftUI

struct ToolDiscoveryView: View {
    @ObservedObject var catalog = ToolCatalogManager.shared
    @ObservedObject var mcpManager = MCPManager.shared
    @State private var searchText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().foregroundColor(Theme.borderColor)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    callout
                    searchField
                    tokenCard
                    DiscoverySection(
                        title: "Curated Starter Picks",
                        subtitle: "Hand-picked servers that make BuddyMCP feel like an App Store.",
                        items: filtered(catalog.curatedItems)
                    )
                    DiscoverySection(
                        title: "@modelcontextprotocol on GitHub",
                        subtitle: "Browse the official MCP packages and add them in one click.",
                        items: filtered(catalog.githubPackages),
                        isLoading: catalog.isLoadingGitHub,
                        emptyPlaceholder: "No repos found yet. Try adding a GitHub token to lift rate limits.",
                        lastError: catalog.lastError
                    )
                    DiscoverySection(
                        title: "Smithery Picks",
                        subtitle: "Popular community MCPs indexed by Smithery.",
                        items: filtered(catalog.smitheryPicks),
                        isLoading: catalog.isLoadingSmithery,
                        emptyPlaceholder: "Smithery picks will appear here as soon as they load."
                    )
                }
                .padding()
            }
            .background(Theme.background)
        }
        .background(Theme.background)
    }
    
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Discover MCP Tools")
                    .font(Theme.headlineFont(size: 22))
                Text("Browse official packages, Smithery picks, and curated bundles. Add a server with one click—then enable the tools you want.")
                    .font(Theme.bodyFont(size: 13))
                    .foregroundColor(Theme.inkBlack.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding()
        .background(Theme.background)
    }
    
    private var callout: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.point.up.left")
                .font(.title3)
                .foregroundColor(Theme.borderColor)
            VStack(alignment: .leading, spacing: 6) {
                Text("Servers install enabled; tools start off")
                    .font(Theme.uiFont(size: 13, weight: .bold))
                Text("When you add a server, it connects right away but every tool is disabled until you toggle it on in the TOOLS tab. This keeps first-time use safe for novices.")
                    .font(Theme.bodyFont(size: 12))
                    .foregroundColor(Theme.inkBlack.opacity(0.7))
            }
            Spacer()
        }
        .padding(12)
        .newsprintCard()
    }
    
    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Theme.inkBlack.opacity(0.6))
            TextField("Search packages, tags, or descriptions", text: $searchText)
                .textFieldStyle(.plain)
                .font(Theme.bodyFont(size: 13))
        }
        .padding(12)
        .background(Theme.background)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderColor, lineWidth: 1))
    }
    
    private var tokenCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("GitHub token (optional)")
                    .font(Theme.uiFont(size: 12, weight: .bold))
                Spacer()
                Button(action: { catalog.saveGitHubToken() }) {
                    Text("SAVE")
                        .font(Theme.uiFont(size: 11, weight: .bold))
                }
                .newsprintButton(isPrimary: false)
            }
            TextField("ghp_xxx to lift API rate limits when browsing @modelcontextprotocol", text: $catalog.githubToken)
                .textFieldStyle(.plain)
                .font(Theme.bodyFont(size: 12))
                .padding(10)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderColor, lineWidth: 1))
            Text("We only use this token to talk to GitHub’s API and store it securely in your Keychain.")
                .font(Theme.bodyFont(size: 11))
                .foregroundColor(Theme.inkBlack.opacity(0.7))
        }
        .padding(12)
        .newsprintCard()
    }
    
    private func filtered(_ items: [MCPCatalogItem]) -> [MCPCatalogItem] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return items }
        let query = searchText.lowercased()
        return items.filter { item in
            item.name.lowercased().contains(query) ||
            item.summary.lowercased().contains(query) ||
            item.tags.contains(where: { $0.lowercased().contains(query) })
        }
    }
}

struct DiscoverySection: View {
    let title: String
    let subtitle: String
    let items: [MCPCatalogItem]
    var isLoading: Bool = false
    var emptyPlaceholder: String = ""
    var lastError: String?
    @ObservedObject var catalog = ToolCatalogManager.shared
    @ObservedObject var mcpManager = MCPManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title.uppercased())
                        .font(Theme.uiFont(size: 11, weight: .bold))
                        .tracking(1)
                    Text(subtitle)
                        .font(Theme.bodyFont(size: 12))
                        .foregroundColor(Theme.inkBlack.opacity(0.7))
                }
                Spacer()
                Button(action: { Task { await catalog.refreshCatalogs() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            }
            
            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Theme.borderColor)
                    .padding(.vertical, 12)
            }
            
            if let lastError {
                Text(lastError)
                    .font(Theme.bodyFont(size: 12))
                    .foregroundColor(Theme.editorialRed)
                    .padding(.bottom, 4)
            }
            
            if items.isEmpty && !isLoading {
                Text(emptyPlaceholder)
                    .font(Theme.bodyFont(size: 12))
                    .foregroundColor(Theme.inkBlack.opacity(0.6))
                    .padding(.vertical, 8)
            }
            
            ForEach(items) { item in
                CatalogCard(item: item, isInstalled: isInstalled(item))
            }
        }
        .padding(.vertical, 4)
    }
    
    private func isInstalled(_ item: MCPCatalogItem) -> Bool {
        return mcpManager.servers.contains { $0.name.lowercased() == item.name.lowercased() }
    }
}

struct CatalogCard: View {
    let item: MCPCatalogItem
    let isInstalled: Bool
    @ObservedObject var catalog = ToolCatalogManager.shared
    @ObservedObject var mcpManager = MCPManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Rectangle()
                    .fill(Color(hex: item.tintHex ?? MCPManager.shared.nextAvailableTintHex()))
                    .frame(width: 8)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(Theme.headlineFont(size: 15))
                    Text(item.summary)
                        .font(Theme.bodyFont(size: 12))
                        .foregroundColor(Theme.inkBlack.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                installButton
            }
            
            HStack(spacing: 8) {
                sourceBadge
                if item.requiresAuth {
                    badge(text: "OAUTH", icon: "lock.fill")
                }
                ForEach(item.tags, id: \.self) { tag in
                    badge(text: tag.uppercased())
                }
                if let homepage = item.homepage {
                    Link(destination: homepage) {
                        Image(systemName: "link")
                            .font(.footnote)
                            .foregroundColor(Theme.inkBlack.opacity(0.7))
                    }
                }
            }
        }
        .padding(14)
        .newsprintCard()
    }
    
    private var installButton: some View {
        let installing = catalog.installingItems.contains(item.id)
        return Button(action: { catalog.install(item) }) {
            if isInstalled {
                Label("INSTALLED", systemImage: "checkmark.circle.fill")
            } else if installing {
                ProgressView()
            } else {
                Label("INSTALL", systemImage: "plus")
            }
        }
        .newsprintButton(isPrimary: !isInstalled)
        .disabled(isInstalled || installing)
    }
    
    private var sourceBadge: some View {
        switch item.source {
        case .curated:
            badge(text: "CURATED", icon: "star.fill")
        case .github:
            badge(text: "GITHUB", icon: "shippingbox.fill")
        case .smithery:
            badge(text: "SMITHERY", icon: "sparkles")
        }
    }
    
    private func badge(text: String, icon: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
            }
            Text(text)
        }
        .font(Theme.uiFont(size: 10, weight: .bold))
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Theme.borderColor.opacity(0.12))
        .foregroundColor(Theme.inkBlack)
        .cornerRadius(6)
    }
}
