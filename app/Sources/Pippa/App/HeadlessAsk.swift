import Foundation
import PiRPC
import PippaCore

/// `Pippa --ask "…"`: one question through `PiSession`, printed as plain lines. For acceptance runs without the window.
@MainActor
enum HeadlessAsk {
    static func setup() async -> Int32 {
        let setup = SetupModel.shared
        setup.begin()
        var last = ""
        while true {
            let line = String(describing: setup.state)
            if line != last, !line.hasPrefix("downloading") || line.count < 60 { print(line); last = line }
            switch setup.state {
            case .ready: return 0
            case .failed(let problem): print("FAILED: \(problem.message) — \(problem.details)"); return 1
            case .askDownload: setup.load()
            default: break
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    static func run(_ question: String) async -> Int32 {
        let started = Date()
        func say(_ line: String) {
            FileHandle.standardOutput.write(Data((String(format: "%6.1fs ", Date().timeIntervalSince(started)) + line + "\n").utf8))
        }
        var answer = ""
        _ = PippaMCPService.readNotes.take(); _ = PippaMCPService.writeNotes.take()
        do {
            try await PiSession.shared.ask(question, conversation: "ask-" + UUID().uuidString.lowercased()) { event in
                switch event {
                case .textDelta(let delta): answer += delta
                case .toolStarted(_, let name, let arguments): say("→ \(name) \(arguments.prefix(300))")
                case .toolEnded(_, let name, let isError, let result, _, _): say("← \(name)\(isError ? " ERROR" : "") \(result.prefix(300).replacingOccurrences(of: "\n", with: " "))")
                case .assistantEnded(_, let reason, let error): say("· model turn ended: \(reason)\(error.map { " " + $0 } ?? "")")
                default: break
                }
            }
        } catch {
            say("FAILED: \(error.localizedDescription)")
            await PiSession.shared.shutdown()
            return 1
        }
        for card in PippaMCPService.readNotes.take().compactMap(\.card) { say("[card] \(String(describing: card).prefix(200))") }
        for receipt in PippaMCPService.writeNotes.take() { say("[done] \(receipt.action) \(receipt.outcome) \(receipt.name)") }
        say("ANSWER (\(Int(Date().timeIntervalSince(started))) s):\n\(answer)")
        await PiSession.shared.shutdown()
        if let server = PiSession.shared.ownedServer { await server.stop() }
        return 0
    }
}
