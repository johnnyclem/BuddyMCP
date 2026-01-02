# Repository Guidelines

## Project Structure & Module Organization
- `MCP-Agent/App/`: SwiftUI views, app entry point, and theming.
- `MCP-Agent/Agent/`: Core agent managers (MCP, LLM, memory, approvals, etc.).
- `MCP-Agent/AgentCore/`: Python runtime used by the app.
- `MCP-Agent/BuddyMCP.app/`: Generated app bundle (do not hand-edit).
- `MCP-Agent/AI_DOCS/`: design notes and references.
- `README.md` and `PRD.md`: product overview and requirements.

## Build, Test, and Development Commands
- `cd MCP-Agent && swift run`: build and run the macOS app from source.
- `cd MCP-Agent && ./package_app.sh`: build a distributable `.app` bundle.
- `ollama pull qwen3:8b`: download the default local model (required at runtime).

## Coding Style & Naming Conventions
- Swift formatting follows standard Xcode conventions: 4-space indentation, trailing commas where appropriate, and one type per file when practical.
- Naming: Types use `PascalCase`, methods/properties use `camelCase`, constants use `let` with descriptive names.
- Keep SwiftUI views small and composed; prefer reusable subviews over deeply nested bodies.

## Testing Guidelines
- No automated test target is included yet. If adding tests, use XCTest and place them in a new `MCP-Agent/Tests/` target with descriptive `*Tests.swift` names.
- Manual verification should include app launch, MCP server connection, and an LLM response.

## Commit & Pull Request Guidelines
- Git history uses short, lowercase, present-tense messages (e.g., `adds theme switcher`). Follow this style unless a change requires more detail.
- PRs should include: a short summary, testing steps (`swift run`, manual flows), and screenshots for UI changes.
- Note any new permissions, external dependencies, or local configuration changes (e.g., Ollama models).

## Configuration & Security Notes
- The app is local-first but integrates with macOS services (Calendar, Reminders). Changes that touch permissions should be called out explicitly.
- Keep bundled secrets out of the repo; prefer local configuration and Keychain integration where applicable.
