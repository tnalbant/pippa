import AppKit
import PippaCore
import SwiftUI

/// `Pippa --snapshot <folder>`: renders the chat window with sample conversations, light and dark, as PNGs. For
/// checking the layout without screen access; nothing is read from or written to the person's conversations.
@MainActor
enum Snapshots {
    static func run(into folder: URL) async -> Int32 {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let chat = ChatModel.shared
        let setup = SetupModel.shared
        setup.showForSnapshot(.ready(adoptedFrom: nil))
        let scenes: [(String, () -> Void)] = [
            ("welcome", { chat.showSample([], current: nil, answering: false) }),
            ("conversation", { chat.showSample(sampleConversations(), current: "c1", answering: false) }),
            ("answering", { chat.showSample(sampleConversations(answering: true), current: "c1", answering: true) }),
            ("error", { chat.showSample(sampleConversations(failed: true), current: "c1", answering: false) }),
            ("setup", {
                chat.showSample([], current: nil, answering: false)
                setup.showForSnapshot(.downloading(progress: 0.42, remaining: 380))
            }),
            ("attachments", {
                setup.showForSnapshot(.ready(adoptedFrom: nil))
                chat.showSample(sampleConversations(), current: nil, answering: false)
                chat.attachments = [URL(fileURLWithPath: "/Users/me/Desktop/Rechnung-Oktober.pdf"), URL(fileURLWithPath: "/Users/me/Desktop/IMG_2041.jpeg")]
                chat.frontApp = "Mail"
            }),
        ]
        for (name, prepare) in scenes {
            prepare()
            for dark in [false, true] {
                let view = ChatView(chat: chat, setup: setup)
                let file = folder.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png")
                await render(view, size: NSSize(width: 1040, height: 720), dark: dark, to: file)
            }
            chat.attachments = []; chat.frontApp = nil
        }
        await render(SettingsView(settings: .shared, setup: setup), size: NSSize(width: 560, height: 640), dark: false, to: folder.appendingPathComponent("settings-light.png"))
        await render(PillPreview(), size: NSSize(width: 120, height: 80), dark: false, to: folder.appendingPathComponent("pill.png"))
        print(folder.path)
        return 0
    }

    private static func render<V: View>(_ view: V, size: NSSize, dark: Bool, to file: URL) async {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
        window.orderFrontRegardless()
        // Let SwiftUI lay out, load images and run onAppear before drawing.
        for _ in 0..<6 { try? await Task.sleep(for: .milliseconds(120)); host.layoutSubtreeIfNeeded() }
        guard let frameView = window.contentView?.superview,
              let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: file)
        window.orderOut(nil)
    }

    private struct PillPreview: View {
        var body: some View { HStack { PillView(chat: .shared, setup: .shared) }.frame(width: 120, height: 80).background(Color.gray.opacity(0.3)) }
    }

    private static func sampleConversations(answering: Bool = false, failed: Bool = false) -> [Conversation] {
        let now = Date()
        var answer = ChatMessage(role: .assistant, text: """
        Dein aktueller Stand ist **ETF-Portfolio.md**, zuletzt geändert am 1. November 2026.

        ## Überblick
        - **MSCI World:** 62 % · Sparrate 400 €
        - **Emerging Markets:** 18 % · Sparrate 120 €
        - **Anleihen:** 20 % · keine Sparrate

        Die anderen beiden Dateien (`ETF-Ideen.md`, `ETF-2024.md`) sind älter und nennen andere Zahlen.
        """)
        answer.steps = [
            ChatStep(id: "1", label: "Searching files for “ETF”", done: true),
            ChatStep(id: "2", label: "Reading ETF-Portfolio.md", done: true),
            ChatStep(id: "3", label: "Reading ETF-Ideen.md", done: true),
        ]
        answer.receipts = [PippaMCPWriteReceipt(action: "reminderAdd", outcome: "done", name: "Sparplan prüfen · Fr., 7. Nov.")]
        if answering {
            answer.text = ""
            answer.receipts = []
            answer.steps = [ChatStep(id: "1", label: "Searching files for “ETF”", done: true), ChatStep(id: "2", label: "Reading ETF-Portfolio.md", done: true)]
            answer.thinking = "Die Person fragt nach der aktuellen ETF-Übersicht. Es gibt drei Dateien; ETF-Portfolio.md ist die neueste (updated 2026-11-01). Ich lese sie und nenne die Aufteilung." 
        }
        if failed {
            answer.text = ""
            answer.receipts = []
            answer.steps = [ChatStep(id: "1", label: "Reading Calendar", done: true, failed: true)]
            answer.error = "Pippa darf deinen Kalender nicht lesen. Erlaube es in den Systemeinstellungen unter Datenschutz & Sicherheit."
        }
        let first = Conversation(id: "c1", title: "Wo ist meine aktuelle ETF-Übersicht?", updated: now, messages: [
            ChatMessage(role: .user, text: "Wo ist meine aktuelle ETF-Übersicht in brain und was steht drin?"),
            answer,
        ])
        return [
            first,
            Conversation(id: "c2", title: "Frist im Brief vom Finanzamt", updated: now.addingTimeInterval(-3600 * 5), messages: []),
            Conversation(id: "c3", title: "Fotos vom Umzug als PDF", updated: now.addingTimeInterval(-3600 * 30), messages: []),
            Conversation(id: "c4", title: "Termine nächste Woche", updated: now.addingTimeInterval(-3600 * 24 * 4), messages: []),
            Conversation(id: "c5", title: "Kündigungsfrist Mietvertrag", updated: now.addingTimeInterval(-3600 * 24 * 20), messages: []),
        ]
    }
}

extension ChatModel {
    /// Snapshots only: show sample conversations without touching the saved ones.
    func showSample(_ conversations: [Conversation], current: String?, answering: Bool) {
        replaceForSnapshot(conversations, current: current, answering: answering)
    }
}
