import Foundation
import PippaCore

/// Setting up the AI on this Mac: Pi, Node, the model folder and models.json happen quietly (`PiSetupFlow`); the only
/// question is the download. An online AI chosen in Settings needs none of this.
@MainActor
final class SetupModel: ObservableObject {
    static let shared = SetupModel()

    @Published private(set) var state: PiSetupState = .preparing(adoptingFrom: nil)
    let hardware = MacHardware.summary()
    private var flow: PiSetupFlow?
    private var roots: PiInstallRoots?
    private var task: Task<Void, Never>?
    private var lastProgressAt = Date.distantPast

    var isReady: Bool { if case .ready = state { true } else { false } }
    /// An online AI is switched on in Settings: Pippa can answer without the download.
    var usesOnlineAI: Bool {
        let settings = InferenceSettings.load(from: PiSession.settingsDirectory)
        return settings.subscriptionModel != nil || PiOnlineProvider.activeConnection(settings) != nil
    }
    var canAnswer: Bool { isReady || usesOnlineAI }
    /// The setup card shows: a question, a download or a problem, and no online AI to fall back on.
    var needsAttention: Bool {
        if usesOnlineAI { return false }
        switch state {
        case .askDownload, .downloading, .failed: return true
        case .preparing, .ready: return false
        }
    }

    /// Snapshots only.
    func showForSnapshot(_ state: PiSetupState) { self.state = state }

    init() {
        let env = ProcessInfo.processInfo.environment
        guard let payload = PiPayload.locate(environment: env) else {
            state = .failed(PiSetupProblem(.payloadMissing(env["PIPPA_PI_PAYLOAD"] ?? "Contents/Resources/pi-payload")))
            return
        }
        let roots: PiInstallRoots
        if let home = env["PIPPA_PI_HOME"] {
            let url = URL(fileURLWithPath: home, isDirectory: true)
            roots = PiInstallRoots(home: url, payload: payload, searchPath: [url.appendingPathComponent(".local/bin")])
        } else {
            roots = PiInstallRoots(support: Pippa.supportDirectory, payload: payload)
        }
        let saved = PippaSettings.load(from: roots.support)
        guard let choice = PiSetupFlow.choice(override: env["PIPPA_PI_MODEL"] ?? saved.localModelKey) else {
            state = .failed(PiSetupProblem(message: T("Pippa needs a Mac with Apple silicon (M1 or later).", table: "App"),
                                           details: "No catalog model fits this Mac", canRetry: false))
            return
        }
        self.roots = roots
        flow = PiSetupFlow(roots: roots, model: choice.model, contextWindow: choice.ctx)
        // An interrupted download goes on by itself: the person already said yes.
        if saved.downloadConsent == choice.model.key { resumeConsent = true }
    }

    private var resumeConsent = false

    /// Everything without network; stops at the download question or an error.
    func begin() {
        guard let flow, task == nil else { return }
        state = .preparing(adoptingFrom: nil)
        task = Task { [weak self] in
            let source = await Task.detached(priority: .userInitiated) { flow.adoptionSource() }.value
            if let source { self?.state = .preparing(adoptingFrom: source) }
            let result = await Task.detached(priority: .userInitiated) { flow.prepare() }.value
            self?.finish(result)
        }
    }

    /// "Load": the one consent, kept so an interrupted download continues at the next start.
    func load() {
        guard let flow, task == nil else { return }
        if let roots { try? PippaSettings.saveDownloadConsent(flow.model.key, to: roots.support) }
        state = .downloading(progress: 0, remaining: nil)
        task = Task { [weak self] in
            let result = await flow.download { progress, remaining in
                Task { @MainActor in self?.progress(progress, remaining) }
            }
            self?.finish(result)
        }
    }

    /// "Stop": pauses the download (what came stays) and asks again.
    func stopDownload() {
        guard case .downloading = state else { return }
        task?.cancel(); task = nil
        resumeConsent = false
        if let roots { try? PippaSettings.saveDownloadConsent(nil, to: roots.support) }
        begin()
    }

    private func progress(_ value: Double, _ remaining: TimeInterval?) {
        guard case .downloading(let shown, _) = state else { return }
        guard value >= 1 || (abs(value - shown) >= 0.002 && Date().timeIntervalSince(lastProgressAt) >= 0.5) else { return }
        lastProgressAt = Date()
        state = .downloading(progress: value, remaining: remaining)
    }

    private func finish(_ result: PiSetupState) {
        task = nil
        state = result
        if case .askDownload = result, resumeConsent { resumeConsent = false; load() }
        if case .ready = result { PiSession.shared.settingsChanged() }
    }
}
