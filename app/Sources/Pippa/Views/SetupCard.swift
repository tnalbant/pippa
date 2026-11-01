import PippaCore
import SwiftUI

/// First run, one card: load the AI for this Mac, or use an online AI in Settings.
struct SetupCard: View {
    @ObservedObject var setup: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(T("Pippa’s AI", table: "App")).font(.headline)
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
                ProgressView(value: progress)
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
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chatCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.chatBorder))
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .short
        formatter.allowedUnits = seconds > 3600 ? [.hour, .minute] : [.minute]
        return formatter.string(from: max(seconds, 60)) ?? ""
    }
}
