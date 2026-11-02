import Combine
import AppKit
import PippaCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    /// The menu bar mark: still and single-colour at rest, turning while Pippa works.
    private let menuMark = MarkNSView(size: 18, monochromeIdle: true)
    private var markWatch: AnyCancellable?
    private var shuttingDown = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard SingleInstance.acquire() else {
            SingleInstance.signalRunningInstance()
            exit(0)
        }
        SingleInstance.listen { AppActions.callPippa() }
        DiagnosticsLog.shared.event("start", ["version": AppVersion.label, "macos": ProcessInfo.processInfo.operatingSystemVersionString])
        NSApp.mainMenu = mainMenu()
        statusItem = makeStatusItem()
        HotkeyCenter.shared.onPress = { AppActions.callPippa() }
        HotkeyCenter.shared.apply(Hotkey.current)
        SetupModel.shared.begin()
        Pill.shared.show()
        Updates.shared.start()
        // First run: open the chat, which shows the setup card.
        if !SetupModel.shared.canAnswer { ChatWindow.shared.show() }
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            menuMark.frame = NSRect(x: (button.bounds.width - 18) / 2, y: (button.bounds.height - 18) / 2, width: 18, height: 18)
            menuMark.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
            button.addSubview(menuMark)
            button.setAccessibilityLabel("Pippa")
        }
        markWatch = ChatModel.shared.$isAnswering.sink { [weak self] working in self?.menuMark.setState(working ? .arbeitet : .ruht) }
        let menu = NSMenu()
        menu.addItem(MenuAction.item(T("Ask Pippa", table: "App")) { AppActions.callPippa() })
        menu.addItem(MenuAction.item(T("New Conversation", table: "App")) { ChatModel.shared.newConversation(); ChatWindow.shared.show() })
        menu.addItem(.separator())
        let pill = MenuAction.item(T("Show Pill", table: "App")) { Pill.shared.isShown.toggle() }
        menu.addItem(pill)
        menu.addItem(MenuAction.item(T("Settings…", table: "App")) { SettingsWindow.shared.show() })
        menu.addItem(.separator())
        menu.addItem(MenuAction.item(T("Quit Pippa", table: "App")) { NSApp.terminate(nil) })
        menu.delegate = MenuAction.stateUpdater { pill.state = Pill.shared.isShown ? .on : .off }
        item.menu = menu
        return item
    }

    /// Invisible main menu: without it, a menu bar app has no ⌘C/⌘V/⌘A/⌘Z in text fields and no ⌘N, ⌘W, ⌘,.
    private func mainMenu() -> NSMenu {
        let main = NSMenu()
        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = menu
            main.addItem(item)
        }
        func edit(_ title: String, _ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            return item
        }
        submenu("Pippa", [
            MenuAction.item(T("Settings…", table: "App"), key: ",", modifiers: [.command]) { SettingsWindow.shared.show() },
            MenuAction.item(T("Check for Updates…", table: "App")) { Updates.shared.checkNow() },
            .separator(),
            MenuAction.item(T("Quit Pippa", table: "App"), key: "q", modifiers: [.command]) { NSApp.terminate(nil) },
        ])
        submenu(T("File", table: "App"), [
            MenuAction.item(T("New Conversation", table: "App"), key: "n", modifiers: [.command]) { ChatModel.shared.newConversation(); ChatWindow.shared.show() },
            edit(T("Close Window", table: "App"), #selector(NSWindow.performClose(_:)), "w"),
        ])
        submenu(T("Edit", table: "App"), [
            edit(T("Undo", table: "App"), Selector(("undo:")), "z"),
            edit(T("Redo", table: "App"), Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            edit(T("Cut", table: "App"), #selector(NSText.cut(_:)), "x"),
            edit(T("Copy", table: "App"), #selector(NSText.copy(_:)), "c"),
            edit(T("Paste", table: "App"), #selector(NSText.paste(_:)), "v"),
            edit(T("Select All", table: "App"), #selector(NSText.selectAll(_:)), "a"),
        ])
        return main
    }

    /// Stop Pi and the local model cleanly, then quit; at most 5 seconds.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !shuttingDown else { return .terminateLater }
        shuttingDown = true
        let server = PiSession.shared.ownedServer
        let reply = TerminateReply()
        Task { @MainActor in await PiSession.shared.shutdown() }
        Task.detached {
            await server?.stop()
            reply.send()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { reply.send() }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppActions.callPippa()
        return false
    }

    /// "Open with Pippa" and files dropped on the app icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        AppActions.attach(urls.filter(\.isFileURL))
    }
}

/// Menu items with closures.
@MainActor
enum MenuAction {
    private final class Target: NSObject {
        let action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func run() { action() }
    }
    private final class Updater: NSObject, NSMenuDelegate {
        let update: () -> Void
        init(_ update: @escaping () -> Void) { self.update = update }
        func menuWillOpen(_ menu: NSMenu) { update() }
    }
    private static var retained: [NSObject] = []

    static func item(_ title: String, key: String = "", modifiers: NSEvent.ModifierFlags = [], _ action: @escaping () -> Void) -> NSMenuItem {
        let target = Target(action)
        retained.append(target)
        let item = NSMenuItem(title: title, action: #selector(Target.run), keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        return item
    }

    static func stateUpdater(_ update: @escaping () -> Void) -> NSMenuDelegate {
        let updater = Updater(update)
        retained.append(updater)
        return updater
    }
}

/// Only one Pippa at a time: a lock file; a second instance wakes the first and quits.
enum SingleInstance {
    private static let notification = Notification.Name("app.pippa.activate")
    nonisolated(unsafe) private static var lockFD: Int32 = -1

    static func acquire() -> Bool {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Pippa", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fd = open(dir.appendingPathComponent("pippa.lock").path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return true }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 { close(fd); return false }
        lockFD = fd
        return true
    }

    static func signalRunningInstance() {
        DistributedNotificationCenter.default().postNotificationName(notification, object: nil, userInfo: nil, deliverImmediately: true)
    }

    @MainActor
    static func listen(_ action: @escaping @MainActor () -> Void) {
        DistributedNotificationCenter.default().addObserver(forName: notification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { action() }
        }
    }
}

/// `NSApp.reply(toApplicationShouldTerminate:)` once, whoever comes first.
private final class TerminateReply: @unchecked Sendable {
    private var sent = false
    private let lock = NSLock()
    func send() {
        guard lock.withLock({ defer { sent = true }; return !sent }) else { return }
        RunLoop.main.perform(inModes: [.common, .modalPanel]) {
            MainActor.assumeIsolated { NSApp.reply(toApplicationShouldTerminate: true) }
        }
    }
}
