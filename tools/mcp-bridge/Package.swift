// swift-tools-version:6.0
// Mac bridge for ticket 023: Claude Code launches `pencilecho-mcp serve` as a stdio
// MCP server; it forwards to Pencil Echo on the iPad over TLS-PSK on the LAN.
import PackageDescription

let package = Package(
    name: "pencilecho-mcp",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "pencilecho-mcp", path: "Sources/pencilecho-mcp"),
    ]
)
