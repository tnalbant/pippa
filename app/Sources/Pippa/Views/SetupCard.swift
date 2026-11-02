import PippaCore
import SwiftUI

/// First run, one card: load the AI for this Mac, or use an online AI in Settings.
struct SetupCard: View {
    @ObservedObject var setup: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.body.weight(.semibold)).foregroundStyle(Theme.accent)
                    .frame(width: 32, height: 32)
                    .background(Theme.accentTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(T("Pippa’s AI", table: "App")).font(.headline)
                Spacer()
                if case .downloading(let progress, _) = setup.state {
                    Text(progress, format: .percent.precision(.fractionLength(0))).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            switch setup.state {
            case .preparing(let source):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(source.map { T("Taking over the AI from %@…", table: "App", $0) } ?? T("Getting ready…", table: "App"))
                }
            case .askDownload(let bytes):
                Text(T("Pippa’s AI runs on this Mac. It needs a one-time download of %@.", table: "App",
                       ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)))
                Text(T("Picked to fit your Mac: %@", table: "App", setup.hardware)).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(T("Load Pippa’s AI", table: "App")) { setup.load() }.buttonStyle(.borderedProminent)
                    Button(T("Use an Online AI…", table: "App")) { SettingsWindow.shared.show() }
                }
            case .downloading(let progress, let remaining):
                ProgressView(value: progress).tint(Theme.accent)
                HStack {
                    Text(remaining.map { T("About %@ left", table: "App", Self.duration($0)) } ?? T("Loading…", table: "App"))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(T("Stop", table: "App")) { setup.stopDownload() }
                }
            case .failed(let problem):
                Text(problem.message)
                if problem.canRetry { Button(T("Try Again", table: "App")) { setup.begin() } }
            case .ready:
                Label(T("Ready", table: "App"), systemImage: "checkmark.circle").foregroundStyle(Theme.ok)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chatCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.chatBorder))
    }

    private var symbol: String {
        switch setup.state {
        case .failed: return "exclamationmark.triangle"
        case .ready: return "checkmark"
        default: return "arrow.down.circle"
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .short
        formatter.allowedUnits = seconds > 3600 ? [.hour, .minute] : [.minute]
        return formatter.string(from: max(seconds, 60)) ?? ""
    }
}
