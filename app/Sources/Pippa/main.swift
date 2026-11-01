import AppKit

// Pi, llama-server and Node are children on pipes: if one dies just before a write, the write fails instead of
// SIGPIPE ending Pippa.
signal(SIGPIPE, SIG_IGN)
let app = NSApplication.shared
if CommandLine.arguments.dropFirst().contains("--verify-runtime") {
    do { try BundleVerification.run(); exit(0) }
    catch { FileHandle.standardError.write(Data("Bundle verification failed: \(error)\n".utf8)); exit(1) }
}
// First launch from the disk image or Downloads: offer once to move to Applications.
if AppMover.runIfNeeded() { exit(0) }
let delegate = AppDelegate()
app.delegate = delegate
// Pippa lives in the menu bar and as a pill; PIPPA_REGULAR_APP=1 gives a Dock icon for UI automation.
app.setActivationPolicy(ProcessInfo.processInfo.environment["PIPPA_REGULAR_APP"] == "1" ? .regular : .accessory)
app.run()
