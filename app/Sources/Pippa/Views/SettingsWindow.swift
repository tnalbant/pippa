import AppKit
import PippaCore
import ServiceManagement
import SwiftUI

/// Where the online-AI settings save, and whether an answer is running (then they wait).
@MainActor
final class SettingsModel: ObservableObject {
    static let shared = SettingsModel()
    @Published private(set) var inferenceSettings = InferenceSettings.load(from: PiSession.settingsDirectory)
    var isActiveWork: Bool { ChatModel.shared.isAnswering }

    func saveInferenceSettings(_ settings: InferenceSettings) throws {
        guard !isActiveWork else { throw InferenceError.busy }
        try settings.save(to: PiSession.settingsDirectory)
        inferenceSettings = settings
        PiSession.shared.settingsChanged()
        SetupModel.shared.objectWillChange.send()
    }
}

/// Settings: the AI, the shortcut, opening at login, Mac permissions, updates.
@MainActor
final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = T("Pippa Settings", table: "App")
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(settings: .shared, setup: .shared))
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsView: View {
    @ObservedObject var settings: SettingsModel
    @ObservedObject var setup: SetupModel
    private let hotkeyState = State(initialValue: Hotkey.current)
    private let opensAtLoginState = State(initialValue: SMAppService.mainApp.status == .enabled)

    var body: some View {
        Form {
            Section(T("Pippa’s AI", table: "App")) {
                if setup.isReady {
                    LabeledContent(T("On this Mac", table: "App"), value: T("Ready", table: "App"))
                } else {
                    SetupCard(setup: setup)
                }
                ChatGPTSubscriptionSettings(model: settings)
                ModelConnectionSettings(model: settings)
            }
            Section(T("Everyday", table: "App")) {
                Picker(T("Shortcut", table: "App"), selection: hotkeyState.projectedValue) {
                    ForEach(Hotkey.allCases) { Text($0.display).tag($0) }
                }
                .onChange(of: hotkeyState.wrappedValue) { _, value in Hotkey.current = value; HotkeyCenter.shared.apply(value) }
                Toggle(T("Open at login", table: "App"), isOn: opensAtLoginState.projectedValue)
                    .onChange(of: opensAtLoginState.wrappedValue) { _, on in
                        if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                        opensAtLoginState.wrappedValue = SMAppService.mainApp.status == .enabled
                    }
            }
            Section(T("Permissions", table: "App")) {
                Text(T("Pippa asks the first time she needs Calendar, Reminders, Mail, Photos or your files. You can change that later in System Settings.", table: "App"))
                    .font(.callout).foregroundStyle(.secondary)
                Button(T("Open Privacy & Security…", table: "App")) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!)
                }
            }
            Section(T("Updates", table: "App")) {
                Button(T("Check for Updates…", table: "App")) { Updates.shared.checkNow() }
                LabeledContent(T("Version", table: "App"), value: AppVersion.label)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .frame(minHeight: 480)
    }
}

/// One row in a settings group: title, explanation, control (used by the online-AI settings).
struct SettingsRow<Trailing: View>: View {
    var title: String
    var detail: String?
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            trailing
        }
    }
}

enum ButtonKind { case primary, secondary, quiet }

extension View {
    @ViewBuilder func pippa(_ kind: ButtonKind, large: Bool = false) -> some View {
        switch kind {
        case .primary: buttonStyle(.borderedProminent)
        case .secondary: buttonStyle(.bordered)
        case .quiet: buttonStyle(.borderless)
        }
    }
}
