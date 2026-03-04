import Foundation
import MCP
import LilDocKit

// MARK: - Entry point

let server = Server(
    name: "lildoc",
    version: "0.1.0",
    capabilities: .init(tools: .init())
)

// Register tool list handler
await server.withMethodHandler(ListTools.self) { _ in
    .init(tools: LilDocTools.all)
}

// Register tool call handler
await server.withMethodHandler(CallTool.self) { params in
    do {
        return try await LilDocTools.handle(params)
    } catch {
        return .init(content: [.text(text: error.localizedDescription, annotations: nil, _meta: nil)], isError: true)
    }
}

let transport = StdioTransport()
try await server.start(transport: transport)
await server.waitUntilCompleted()
