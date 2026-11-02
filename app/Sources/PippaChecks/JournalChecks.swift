import Foundation
import PippaCore

/// The undo journal for result files (file preparation): what Undo removes and what it leaves alone.
func runJournalChecks() async {
    await checkAsync("Result in journal: undo removes the file in the cache along with its folder, inputs stay unchanged") {
        let input = dir("result-input").appendingPathComponent("Scan.jpg")
        write("Bilddaten", input)
        let before = FileFingerprint.of(input)
        let folder = try ResultsFolder.fresh()
        let output = folder.appendingPathComponent("Scans.pdf")
        write("%PDF-1.4 Ergebnis", output)
        let ex = try Executor(baseDirectory: dir("result-support"))
        let receipt = try await ex.recordResult([output], summary: "Scans.pdf", detail: "")
        let report = try await ex.undo(jobID: receipt.id)
        let removed = L("Removed.", table: "TrayCore")
        return receipt.undoDetail == removed && receipt.revealURL == output && report.conflicts.isEmpty
            && !FileManager.default.fileExists(atPath: output.path) && !FileManager.default.fileExists(atPath: folder.path)
            && FileManager.default.fileExists(atPath: ResultsFolder.directory.path)
            && before?.matches(FileFingerprint.of(input)) == true
    }
    await checkAsync("Result in journal: an already removed file counts as undone, empty list is rejected") {
        let folder = try ResultsFolder.fresh()
        let output = folder.appendingPathComponent("weg.jpg")
        write("x", output)
        let ex = try Executor(baseDirectory: dir("result-gone-support"))
        let receipt = try await ex.recordResult([output], summary: "weg.jpg", detail: "")
        try? FileManager.default.removeItem(at: folder)
        let report = try await ex.undo(jobID: receipt.id)
        var refused = false
        do { _ = try await ex.recordResult([], summary: "", detail: "") } catch { refused = true }
        return report.conflicts.isEmpty && refused
    }
}
