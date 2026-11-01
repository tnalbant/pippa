import Foundation
import PiRPC

/// How Pippa starts Pi: the command line, the environment and the MCP attachment, all without starting anything.
@MainActor func runLaunchChecks() {
    let t = URL(fileURLWithPath: "/fixture/pi", isDirectory: true)
    let bundled = URL(fileURLWithPath: "/fixture/Pippa.app/Contents/Resources/pippa-skills", isDirectory: true)
    let memory = URL(fileURLWithPath: "/fixture/Application Support/Pippa/memory.md")
    let web = URL(fileURLWithPath: "/fixture/pippa-web/index.ts")
    let paths = PippaPiLaunch.Paths(extensionsDirectory: t, webExtension: web, sessionDirectory: t, skillsDirectory: bundled, memoryFile: memory)
    func run(_ args: [String], _ part: [String]) -> Bool {
        guard args.count >= part.count else { return false }
        return (0...(args.count - part.count)).contains { Array(args[$0..<($0 + part.count)]) == part }
    }
    func value(_ args: [String], after flag: String) -> String? {
        args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
    }

    let args = PippaPiLaunch.arguments(paths: paths, sessionID: "ABC-123:Rev", language: "de")
    check("Only Pippa's bundled skills load, never the person's terminal skills",
          run(args, ["--no-skills", "--skill", bundled.path]))
    let withoutSkills = PippaPiLaunch.Paths(extensionsDirectory: t, webExtension: nil, sessionDirectory: t)
    check("Without a skills folder no skill is passed",
          !PippaPiLaunch.arguments(paths: withoutSkills, sessionID: nil, language: "de").contains("--skill"))
    check("Context files, foreign extensions and project trust are off",
          ["--no-context-files", "--no-extensions", "--no-approve"].allSatisfy(args.contains))
    check("The tool list is fixed and names Pippa's MCP server",
          value(args, after: "--tools") == PippaPiLaunch.tools.joined(separator: ",") && PippaPiLaunch.tools.contains("mcp__pippa__*"))
    check("A conversation gets its own session with an ID Pi accepts",
          value(args, after: "--session-dir") == t.path && value(args, after: "--session-id") == "abc-123_rev")
    check("Without a session ID nothing is saved",
          PippaPiLaunch.arguments(paths: paths, sessionID: nil, language: "en").contains("--no-session"))
    check("Session IDs keep only characters Pi allows",
          PippaPiLaunch.piSessionID("--A b:C--") == "a_b_c" && PippaPiLaunch.piSessionID("::") == "pippa")
    check("The system prompt follows the language and stays short",
          value(args, after: "--system-prompt") == PippaPiLaunch.systemPrompt(language: "de")
          && PippaPiLaunch.systemPrompt(language: "en") != PippaPiLaunch.systemPrompt(language: "de")
          && ["de", "en"].allSatisfy { PippaPiLaunch.systemPrompt(language: $0).split(whereSeparator: \.isWhitespace).count < 200 })

    let launcher = PippaPiLaunch.Launcher(executable: URL(fileURLWithPath: "/usr/bin/true"), launcherArguments: ["cli.js"],
                                          piArguments: ["--provider", "pippa-local"], environment: ["PI_OFFLINE": "0", "X": "1"])
    let configured = PippaPiLaunch.configuration(launcher: launcher, workingDirectory: t, paths: paths, sessionID: nil, language: "de")
    check("Launcher arguments come first, the offline switches cannot be overridden",
          configured.launcherArguments == ["cli.js"] && Array(configured.arguments.prefix(2)) == ["--provider", "pippa-local"]
          && configured.environment["PI_OFFLINE"] == "1" && configured.environment["PI_TELEMETRY"] == "0"
          && configured.environment["X"] == "1")
    check("Memory file and language reach the extensions",
          configured.environment[PippaPiLaunch.memoryVariable] == memory.path && configured.environment["PIPPA_LANGUAGE"] == "de")
    check("Only Pippa's extensions load, web access last",
          configured.extensions == ["pippa-tools.ts", "pippa-assist.ts", "pippa-memory.ts"].map { t.appendingPathComponent($0) } + [web])

    let endpoint = PippaPiLaunch.MCPEndpoint(url: URL(string: "http://127.0.0.1:4711/mcp")!, token: String(repeating: "a", count: 64))
    let mcpFile = t.appendingPathComponent("pippa-mcp.ts")
    var withMCP = PippaPiLaunch.configuration(launcher: launcher, workingDirectory: t, paths: paths, sessionID: nil, language: "en",
                                              mcp: (endpoint, mcpFile))
    PippaPiLaunch.addMCP(endpoint, extension: mcpFile, to: &withMCP)
    check("The MCP server is attached once, with address and key only for this Pi",
          withMCP.extensions.filter { $0 == mcpFile }.count == 1 && withMCP.extensions.last == mcpFile
          && withMCP.environment["PIPPA_MCP_URL"] == "http://127.0.0.1:4711/mcp"
          && withMCP.environment["PIPPA_MCP_TOKEN"] == endpoint.token && withMCP.environment["PIPPA_MCP_EXPOSURE"] == "direct")

    let broken: [String: Any] = ["content": [["type": "text", "text": "EACCES"]]]
    let moved: [String: Any] = ["content": [["type": "text", "text": "Moved a.pdf to the Trash."]], "details": ["trash": true]]
    check("A tool's own error stays a failure; a finished move is done",
          PiTurnReceipt.classify(tool: "move_files", isError: true, result: broken) == .failed
          && PiTurnReceipt.classify(tool: "move_files", isError: false, result: moved) == .done)
    var receipt = PiTurnReceipt()
    for (id, to) in [("a", "/x/trash bin"), ("b", " Trash ")] {
        receipt.observe(.toolStarted(id: id, name: "move_files", arguments: #"{"from":"/x/a.pdf","to":"\#(to)"}"#))
        receipt.observe(.toolEnded(id: id, name: "move_files", isError: false, result: "Moved.", outcome: .done, fileAccessFailure: nil))
    }
    check("Only the word trash means the Trash; a folder whose name contains it is a move",
          receipt.records.map(\.action) == ["move", "trash"])
}
