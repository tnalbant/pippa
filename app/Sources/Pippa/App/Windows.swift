import AppKit
import PippaCore
import SwiftUI

/// The chat window: a normal, resizable window that remembers its frame.
@MainActor
final class ChatWindow {
    static let shared = ChatWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Pippa"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 560, height: 420)
            window.contentView = NSHostingView(rootView: ChatView(chat: .shared, setup: .shared))
            window.center()
            window.setFrameAutosaveName("PippaChat")
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        PiSession.shared.preload()
    }

    var isKey: Bool { window?.isKeyWindow == true }
    func hide() { window?.orderOut(nil) }
}

/// The pill: a small floating mark that opens the chat and takes dropped files. A dot says what Pippa is doing.
@MainActor
final class Pill {
    static let shared = Pill()
    private var panel: NSPanel?

    var isShown: Bool {
        get { UserDefaults.standard.object(forKey: "showsPill") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "showsPill"); newValue ? show() : panel?.orderOut(nil) }
    }

    func show() {
        guard isShown else { return }
        if panel == nil {
            let size = NSSize(width: 52, height: 52)
            let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.nonactivatingPanel, .borderless],
                                backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.isMovableByWindowBackground = true
            panel.contentView = NSHostingView(rootView: PillView(chat: .shared, setup: .shared))
            if let screen = NSScreen.main?.visibleFrame {
                panel.setFrameOrigin(NSPoint(x: screen.maxX - size.width - 24, y: screen.minY + 24))
            }
            panel.setFrameAutosaveName("PippaPill")
            self.panel = panel
        }
        panel?.orderFrontRegardless()
    }
}

struct PillView: View {
    @ObservedObject var chat: ChatModel
    @ObservedObject var setup: SetupModel
    private let targetedState = State(initialValue: false)

    private let hoverState = State(initialValue: false)

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 44, height: 44)
                .overlay {
                    // Working: a ring that turns around the mark.
                    if chat.isAnswering {
                        TimelineView(.animation) { context in
                            Circle().trim(from: 0, to: 0.3)
                                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                .rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2 * 360))
                                .frame(width: 48, height: 48)
                        }
                    }
                }
                .scaleEffect(targetedState.wrappedValue ? 1.12 : hoverState.wrappedValue ? 1.05 : 1)
                .animation(.easeOut(duration: 0.15), value: hoverState.wrappedValue)
                .animation(.easeOut(duration: 0.15), value: targetedState.wrappedValue)
                .onTapGesture { AppActions.callPippa() }
                .onHover { hoverState.wrappedValue = $0 }
            // Only when Pippa needs the person: the AI is not set up yet.
            if !setup.canAnswer && !chat.isAnswering {
                Circle().fill(Theme.needDot).frame(width: 11, height: 11)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
            }
        }
        .frame(width: 52, height: 52)
        .help(T("Ask Pippa", table: "App"))
        .onDrop(of: [.fileURL], isTargeted: targetedState.projectedValue) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in AppActions.attach([url]) }
                }
            }
            return true
        }
    }
}

/// What the shortcut, the pill, the menu and the Dock icon do.
@MainActor
enum AppActions {
    /// Opens the chat; the app that was in front becomes a chip the person can keep or remove.
    static func callPippa(front: NSRunningApplication? = NSWorkspace.shared.frontmostApplication) {
        if let front, front.bundleIdentifier != Bundle.main.bundleIdentifier, let name = front.localizedName,
           ChatModel.shared.draft.isEmpty {
            ChatModel.shared.frontApp = name
        }
        ChatWindow.shared.show()
    }

    static func attach(_ urls: [URL]) {
        for url in urls where url.isFileURL && !ChatModel.shared.attachments.contains(url) { ChatModel.shared.attachments.append(url) }
        ChatWindow.shared.show()
    }
}
