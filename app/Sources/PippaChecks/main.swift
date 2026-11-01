import AppKit
import CoreText
import Foundation
import PippaCore
import SQLite3

// Line-buffer stdout, even into a pipe (CI), so output doesn't sit in the buffer.
setvbuf(stdout, nil, _IOLBF, 0)

// Minimal check runner: `check("name") { … }`; exits non-zero on failures at the end. No network.
nonisolated(unsafe) var failures = 0
func check(_ name: String, _ body: () throws -> Bool) {
    do {
        if try body() { print("✓ \(name)") } else { failures += 1; print("✗ \(name)") }
    } catch { failures += 1; print("✗ \(name): \(error)") }
}
func checkAsync(_ name: String, _ body: () async throws -> Bool) async {
    // Announce before long checks so a hang is visible in the CI output.
    if ProcessInfo.processInfo.environment["CI"] != nil { print("… \(name)") }
    do {
        if try await body() { print("✓ \(name)") } else { failures += 1; print("✗ \(name)") }
    } catch { failures += 1; print("✗ \(name): \(error)") }
}

nonisolated(unsafe) let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent("pippa-checks-\(UUID().uuidString)", isDirectory: true)
try fm.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: root) }
setenv("PIPPA_LOG_DIR", root.appendingPathComponent("log").path, 1)
// Identical copies go "to the Trash" in a folder of the run, never into the real Trash.
setenv("PIPPA_CHECK_TRASH", root.appendingPathComponent("Papierkorb").path, 1)
// Checks never depend on this Mac's system model (Apple Intelligence on or off): tidying uses recordings or nothing.
setenv("PIPPA_NO_SYSTEM_MODEL", "1", 1)

// Focused runs (PIPPA_<AREA>_CHECKS=1): one area only, for parallel work on a busy machine. The full run includes them.
func focused(_ variable: String, _ label: String, _ body: () async -> Void) async {
    guard ProcessInfo.processInfo.environment[variable] == "1" else { return }
    await body()
    print(failures == 0 ? "\(label) checks passed." : "\(label) checks failed.")
    exit(failures == 0 ? 0 : 1)
}
await focused("PIPPA_DURABLE_JOB_CHECKS", "Durable job") { await runDurableJobChecks() }
await focused("PIPPA_FILE_PREPARATION_CHECKS", "File preparation") { await runFilePreparationChecks() }
await focused("PIPPA_MCP_FILE_PREPARATION_CHECKS", "MCP file preparation") { await runMCPFilePreparationChecks() }
await focused("PIPPA_DOWNLOAD_CHECKS", "Download") { await runDownloadChecks() }
// Mail identity, readback and insertion decisions; no native app actions.
await focused("PIPPA_LETTER_CHECKS", "Letter") { await runLetterChecks() }
// Installer only (PiSetup, fake HOME under .build/fake-home-*).
await focused("PIPPA_SETUP_CHECKS", "Installer") { await runSetupChecks() }
// Only Pippa's MCP server (stand-in readers, no real Mail/Calendar/Excel).
await focused("PIPPA_MCP_CHECKS", "MCP") {
    await runMCPChecks()
    await runNativeReminderChecks()
}

func dir(_ name: String) -> URL {
    let u = root.appendingPathComponent(name, isDirectory: true)
    try? fm.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}
/// Small thread-safe box for values from @Sendable callbacks.
final class LockedBox<T>: @unchecked Sendable {
    private var stored: T
    private let lock = NSLock()
    init(_ value: T) { stored = value }
    var value: T { lock.withLock { stored } }
    func mutate(_ change: (inout T) -> Void) { lock.withLock { change(&stored) } }
}
func write(_ text: String, _ url: URL) { try? text.write(to: url, atomically: true, encoding: .utf8) }

/// Text PDF with one page per entry (CoreText), for reading, search and speed checks.
func makePDF(_ pages: [String], at url: URL) {
    var box = CGRect(x: 0, y: 0, width: 595, height: 842)
    guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
    for page in pages {
        ctx.beginPDFPage(nil)
        let attr = NSAttributedString(string: page, attributes: [.font: NSFont.systemFont(ofSize: 11)])
        let setter = CTFramesetterCreateWithAttributedString(attr)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), CGPath(rect: box.insetBy(dx: 50, dy: 50), transform: nil), nil)
        CTFrameDraw(frame, ctx)
        ctx.endPDFPage()
    }
    ctx.closePDF()
}

let invoiceText = """
Stadtwerke Musterstadt GmbH
Hauptstraße 1, 12345 Musterstadt
Rechnung
Rechnungsnummer 2026-118734
Rechnungsdatum 02.03.2026
Strom März 2026
Gesamtbetrag 84,20 €
IBAN DE89 3704 0044 0532 0130 00
"""
let contractPages = [
    "Mietvertrag\nzwischen Hausverwaltung Berger und Max Muster\nüber die Wohnung in der Lindenstraße 5\nMusterstadt, den 14.06.2021",
    "§ 8 Kündigung\nDas Mietverhältnis läuft auf unbestimmte Zeit. Es kann von beiden Seiten mit einer Frist von drei Monaten zum Monatsende gekündigt werden.",
]

// MARK: - Names

check("Name: YYYY-MM sender kind") {
    Naming.document(date: DayDate(year: 2026, month: 3, day: 2), sender: "Stadtwerke", kind: "Rechnung", ext: "PDF") == "2026-03 Stadtwerke Rechnung.pdf"
}
check("Name: contract and draft") {
    Naming.contract(kind: "Mietvertrag", subject: "Wohnung", year: 2021, ext: "pdf") == "Mietvertrag Wohnung 2021.pdf"
        && Naming.document(date: DayDate(year: 2026, month: 4, day: 1), sender: "Hausverwaltung", kind: "Brief", ext: "docx", draft: true) == "2026-04 Hausverwaltung Brief (Entwurf).docx"
}
check("Name: photo") { Naming.photo(date: DayDate(year: 2026, month: 7, day: 14)!, number: 1, ext: "JPG") == "2026-07-14 Foto 01.jpg" }
check("Name: sanitised") { Naming.sanitize("  ../Re:chnung/ März\u{0007}  ") == "Re-chnung- März" }
check("Folder") { Naming.folder(for: .invoice, year: 2026) == "Rechnungen/2026" && Naming.folder(for: .contract, year: nil) == "Verträge" }
check("Collision gets \" (2)\"") {
    let d = dir("collision")
    write("x", d.appendingPathComponent("2026-03 Stadtwerke Rechnung.pdf"))
    var taken = Set<String>()
    let a = Naming.unique("2026-03 Stadtwerke Rechnung.pdf", in: d, taken: &taken)
    let b = Naming.unique("2026-03 Stadtwerke Rechnung.pdf", in: d, taken: &taken)
    return a.lastPathComponent == "2026-03 Stadtwerke Rechnung (2).pdf" && b.lastPathComponent == "2026-03 Stadtwerke Rechnung (3).pdf"
}

check("Case: only the same file counts as a pure rename") {
    let d = dir("case-same")
    let a = d.appendingPathComponent("brief.txt"), b = d.appendingPathComponent("anders.txt")
    write("a", a); write("b", b)
    let insensitive = (try? d.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]))?.volumeSupportsCaseSensitiveNames == false
    return Executor.isSameFile(a.path, a.path) && !Executor.isSameFile(a.path, b.path)
        && !Executor.isSameFile(a.path, d.appendingPathComponent("fehlt.txt").path)
        && (!insensitive || Executor.isSameFile(a.path, d.appendingPathComponent("Brief.txt").path))
}

// MARK: - Model choice

/// Memory budget for Apple Silicon (rule from the former pi-local installer): what a table model may need.
func budgetGiB(physicalMemory: UInt64) -> Double {
    let ram = Double(physicalMemory) / 1_073_741_824
    return ram <= 12 ? ram * 0.6 : min(ram * 0.75, ram - 6)
}

let GB: UInt64 = 1 << 30
/// The bundled catalog, with a stand-in pin for table models that are not pinned yet (only so the table itself can be
/// checked; "Default model is pinned" checks the real pins).
let tableCatalog: ModelCatalog = {
    var catalog = ModelCatalog.bundled()
    for index in catalog.models.indices where catalog.models[index].pinned == nil && ModelSelector.tableKeys.contains(catalog.models[index].key) {
        catalog.models[index].pending = nil
        let json = #"{"revision": "check", "files": [{"path": "stand-in.gguf", "size": 1, "sha256": "\#(String(repeating: "0", count: 64))"}]}"#
        catalog.models[index].pinned = try? JSONDecoder().decode(CatalogModel.Pinned.self, from: Data(json.utf8))
    }
    return catalog
}()
func pick(_ gb: UInt64, _ preference: ModelPreference = .standard) -> ModelChoice? {
    try? ModelSelector.choose(physicalMemory: gb * GB, preference: preference, appleSilicon: true, catalog: tableCatalog).get()
}
check("Default model is pinned: every table model has revision, path, size and SHA256 (scripts/pin-model.sh)") {
    let catalog = ModelCatalog.bundled()
    let unpinned = ModelSelector.tableKeys.filter { key in
        guard let model = catalog.model(key), model.pending == nil, let pinned = model.pinned, !pinned.files.isEmpty,
              pinned.revision.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil else { return true }
        return !pinned.files.allSatisfy { $0.size > 0 && $0.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil }
    }
    if !unpinned.isEmpty { print("   not pinned: \(unpinned.joined(separator: ", ")) → scripts/pin-model.sh <key> <hf-repo>") }
    return unpinned.isEmpty
}
check("Model: 8 GB → qwen3.5-4b-q4, also with \"More thorough\" saved (no choice below 24 GB)") {
    pick(8)?.model.key == "qwen3.5-4b-q4" && pick(8, .thorough)?.model.key == "qwen3.5-4b-q4"
        && !ModelSelector.offersThorough(physicalMemory: 8 * GB)
}
check("Model: 32 and 64 GB → qwen3.6-35b-a3b-q3, ctx 32768, thinking off; \"More thorough\" → qwen3.6-35b-a3b-iq3") {
    [32, 64].allSatisfy { gb in
        let c = pick(UInt64(gb))
        return c?.model.key == "qwen3.6-35b-a3b-q3" && c?.ctx == 32768 && c?.model.thinking == "off"
            && c?.extra["cache-ram"] == "1024" && c?.extra["ctx-checkpoints"] == "4"
            && pick(UInt64(gb), .thorough)?.model.key == "qwen3.6-35b-a3b-iq3"
            && ModelSelector.offersThorough(physicalMemory: UInt64(gb) * GB) == ModelSelector.thoroughTested
    }
}
check("Model: the 35B is for 32 GB and up only; 24 GB keeps no fallback to it, smaller and own models stay usable") {
    ModelSelector.isForLargerMacs("qwen3.6-35b-a3b-q3", physicalMemory: 24 * GB)
        && ModelSelector.isForLargerMacs("qwen3.6-35b-a3b-q3", physicalMemory: 16 * GB)
        && !ModelSelector.isForLargerMacs("qwen3.6-35b-a3b-q3", physicalMemory: 32 * GB)
        && !ModelSelector.isForLargerMacs("qwen3.5-9b-q4", physicalMemory: 24 * GB)
        && !ModelSelector.isForLargerMacs("qwen3.6-35b-a3b-iq3", physicalMemory: 24 * GB)
        && !ModelSelector.isForLargerMacs("k2-horizon-7b", physicalMemory: 24 * GB)
        && ModelSelector.isForLargerMacs("qwen3.5-9b-q4", physicalMemory: 8 * GB)
}
check("Model: an unpinned table model is unavailable (never a download without a SHA256)") {
    var catalog = tableCatalog
    if let index = catalog.models.firstIndex(where: { $0.key == "qwen3.5-9b-q4" }) { catalog.models[index].pinned = nil }
    if case .failure(.modelUnavailable) = ModelSelector.choose(physicalMemory: 16 * GB, appleSilicon: true, catalog: catalog) { return true }
    return false
}
check("Model: Intel → not supported") {
    if case .failure(.unsupportedHardware) = ModelSelector.choose(physicalMemory: 32 * GB, appleSilicon: false) { return true }
    return false
}
check("Model: table only; `named` only for measurements and models.json (both table rows keep their settings)") {
    let auto = pick(16)
    let same = ModelSelector.named("qwen3.5-9b-q4", physicalMemory: 16 * GB, catalog: tableCatalog)
    let thorough = ModelSelector.named("qwen3.6-35b-a3b-iq3", physicalMemory: 24 * GB, catalog: tableCatalog)
    let other = ModelSelector.named("k2-horizon-7b", physicalMemory: 16 * GB, catalog: tableCatalog)
    return same == auto && thorough == pick(24, .thorough) && other?.model.key == "k2-horizon-7b" && other?.ctx == 16384
        && other?.extra["cache-ram"] == "0"
        && ModelSelector.named("gibt-es-nicht", physicalMemory: 16 * GB) == nil
}
check("Existing models: matching name, wrong content is not adopted") {
    let home = dir("existing-wrong")
    let payload = Data((0..<4096).map { UInt8($0 % 13) })
    let hash = String(repeating: "a", count: 64)
    let json = """
    {"sampling": {}, "models": [
      {"key": "a", "label": "A", "repo": "r/a", "quant": "q", "memGiB": 1, "ctx": 4096, "rank": 1,
       "pinned": {"revision": "x", "files": [{"path": "a.gguf", "size": \(payload.count), "sha256": "\(hash)"}]}}]}
    """
    let catalog = try JSONDecoder().decode(ModelCatalog.self, from: Data(json.utf8))
    let lms = home.appendingPathComponent(".lmstudio/models")
    try fm.createDirectory(at: lms, withIntermediateDirectories: true)
    try payload.write(to: lms.appendingPathComponent("a.gguf"))
    guard let found = ExistingModels.find(catalog, roots: ExistingModels.defaultRoots(home: home))[hash] else { return false }
    let models = dir("existing-wrong-models")
    let d = ModelDownloader(directory: models)
    let adopted = try d.adopt(catalog.model("a")!.pinned!.files[0], from: found.url)
    let left = try fm.contentsOfDirectory(atPath: models.path)
    return !adopted && left.isEmpty && fm.fileExists(atPath: found.url.path)
}
await checkAsync("Existing models: no download without consent after a failed adoption") {
    let home = dir("existing-no-consent")
    let payload = Data((0..<4096).map { UInt8($0 % 17) })
    let json = """
    {"sampling": {}, "models": [
      {"key": "a", "label": "A", "repo": "r/a", "quant": "q", "memGiB": 1, "ctx": 4096, "rank": 1,
       "pinned": {"revision": "x", "files": [{"path": "a.gguf", "size": \(payload.count), "sha256": "\(String(repeating: "b", count: 64))"}]}}]}
    """
    let catalog = try JSONDecoder().decode(ModelCatalog.self, from: Data(json.utf8))
    let lms = home.appendingPathComponent(".lmstudio/models")
    try fm.createDirectory(at: lms, withIntermediateDirectories: true)
    try payload.write(to: lms.appendingPathComponent("a.gguf"))
    let found = ExistingModels.find(catalog, roots: ExistingModels.defaultRoots(home: home))
    let models = dir("existing-no-consent-models")
    let d = ModelDownloader(directory: models)
    let rejected = LockedBox<[String]>([])
    do {
        try await d.download(catalog.model("a")!, existing: found, allowNetwork: false, rejected: { sha in rejected.mutate { $0.append(sha) } }) { _, _ in }
        return false
    } catch is ModelDownloader.AdoptionFailed {}
    // Likewise with no file found and no consent: nothing from the network.
    do { try await d.download(catalog.model("a")!, allowNetwork: false) { _, _ in }; return false }
    catch is ModelDownloader.AdoptionFailed {}
    let contents = try fm.contentsOfDirectory(atPath: models.path)
    return rejected.value == [String(repeating: "b", count: 64)] && contents.isEmpty
}
check("Existing models: llama.cpp name only with exactly the repo prefix") {
    let home = dir("existing-llamacpp")
    let size = 2048
    let json = """
    {"sampling": {}, "models": [
      {"key": "a", "label": "A", "repo": "owner/a-GGUF", "quant": "q", "memGiB": 1, "ctx": 4096, "rank": 1,
       "pinned": {"revision": "x", "files": [{"path": "a.gguf", "size": \(size), "sha256": "\(String(repeating: "c", count: 64))"}]}}]}
    """
    let catalog = try JSONDecoder().decode(ModelCatalog.self, from: Data(json.utf8))
    let cache = home.appendingPathComponent("Library/Caches/llama.cpp")
    try fm.createDirectory(at: cache, withIntermediateDirectories: true)
    try Data(count: size).write(to: cache.appendingPathComponent("old_a.gguf"))
    let roots = ExistingModels.defaultRoots(home: home)
    guard ExistingModels.find(catalog, roots: roots).isEmpty else { return false }
    try Data(count: size).write(to: cache.appendingPathComponent("owner_a-GGUF_a.gguf"))
    return ExistingModels.find(catalog, roots: roots).first?.value.source == "llama.cpp"
}
check("Download URL as in installer/hf.mjs") {
    ModelDownloader.url(repo: "unsloth/Qwen3.5-4B-GGUF", revision: "e87f176479d0855a907a41277aca2f8ee7a09523", path: "Qwen3.5-4B-Q4_K_M.gguf").absoluteString
        == "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/e87f176479d0855a907a41277aca2f8ee7a09523/Qwen3.5-4B-Q4_K_M.gguf"
}
check("Server arguments: local only, key only in the environment, jinja, catalogue values") {
    let c = pick(16)!
    let args = LlamaServer.arguments(choice: c, model: URL(fileURLWithPath: "/m.gguf"), port: 9000, supported: nil)
    let s = args.joined(separator: " ")
    let k2Choice = ModelSelector.named("k2-horizon-7b", physicalMemory: 16 * GB, catalog: tableCatalog)!
    let k2 = LlamaServer.arguments(choice: k2Choice, model: URL(fileURLWithPath: "/k2.gguf"), port: 9000, supported: nil).joined(separator: " ")
    let env = LlamaServer.environment(apiKey: "geheim-k", base: ["PATH": "/usr/bin"])
    return s.contains("--host 127.0.0.1") && !s.contains("--api-key") && !s.contains("geheim-k")
        && env["LLAMA_API_KEY"] == "geheim-k" && env["PATH"] == "/usr/bin" && s.contains("--jinja") && s.contains("--ctx-size 16384")
        && s.contains("--ctx-checkpoints 4") && s.contains("--cache-ram 0") && s.contains("--top-k 20") && s.contains("--no-webui")
        && s.contains("--reasoning off") && !s.contains("--chat-template-kwargs")
        && k2.contains("--top-k 0") && k2.contains(#"--chat-template-kwargs {"reasoning_effort":"low","tool_call_format":"xml"}"#)
}

check("Model: 16 GB → qwen3.5-9b-q4, ctx 16384, ctx-checkpoints 4, cache-ram 0; no \"More thorough\"") {
    let c = pick(16)
    return c?.model.key == "qwen3.5-9b-q4" && c?.ctx == 16384 && c?.extra["ctx-checkpoints"] == "4" && c?.extra["cache-ram"] == "0"
        && pick(16, .thorough)?.model.key == "qwen3.5-9b-q4" && !ModelSelector.offersThorough(physicalMemory: 16 * GB)
        && (c?.model.memGiB ?? 99) <= budgetGiB(physicalMemory: 16 * GB)
}
check("Model: K2 Horizon 7B does not fit 8 GB; low thinking via the template, XML tool calls") {
    let k2 = tableCatalog.model("k2-horizon-7b")
    return (k2?.memGiB ?? 0) > budgetGiB(physicalMemory: 8 * GB)
        && k2?.extra?["chat-template-kwargs"]?.description == #"{"reasoning_effort":"low","tool_call_format":"xml"}"#
}
check("Model: 24 GB → the 16 GB profile (qwen3.5-9b-q4, ctx 16384, medium, ctx-checkpoints 4, cache-ram 0); \"More thorough\" → qwen3.6-35b-a3b-iq3 within the memory budget") {
    let c = pick(24), t = pick(24, .thorough)
    return c == pick(16) && c?.model.key == "qwen3.5-9b-q4" && c?.ctx == 16384 && c?.model.thinking == "medium"
        && c?.extra["cache-ram"] == "0" && c?.extra["ctx-checkpoints"] == "4"
        && ModelSelector.offersThorough(physicalMemory: 24 * GB) == ModelSelector.thoroughTested
        && t?.model.key == "qwen3.6-35b-a3b-iq3" && t?.ctx == 32768
        && (t?.model.memGiB ?? 99) <= budgetGiB(physicalMemory: 24 * GB)
}
await checkAsync("Existing models: LM Studio, Ollama, Hugging Face detected, adopted without network, source stays") {
    let home = dir("existing-home")
    let payload = Data((0..<65_536).map { UInt8($0 % 251) })
    let probe = home.appendingPathComponent("probe")
    try payload.write(to: probe)
    let hash = try ModelDownloader.sha256(of: probe)
    let json = """
    {"sampling": {}, "models": [
      {"key": "a", "label": "A", "repo": "r/a", "quant": "q", "memGiB": 1, "ctx": 4096, "rank": 1,
       "pinned": {"revision": "x", "files": [{"path": "sub/a.gguf", "size": \(payload.count), "sha256": "\(hash)"}]}}]}
    """
    let catalog = try JSONDecoder().decode(ModelCatalog.self, from: Data(json.utf8))
    let model = catalog.model("a")!
    let roots = ExistingModels.defaultRoots(home: home)
    guard ExistingModels.find(catalog, roots: roots).isEmpty else { return false }
    // LM Studio: name as on Hugging Face; a same-size file with a different name doesn't count.
    let lms = home.appendingPathComponent(".lmstudio/models/r/a-GGUF")
    try fm.createDirectory(at: lms, withIntermediateDirectories: true)
    try Data(repeating: 7, count: payload.count).write(to: lms.appendingPathComponent("b.gguf"))
    try payload.write(to: lms.appendingPathComponent("a.gguf"))
    let found = ExistingModels.find(catalog, roots: roots)
    guard found[hash]?.source == "LM Studio", found[hash]?.url.lastPathComponent == "a.gguf" else { return false }
    // Ollama: named by content.
    let ollama = home.appendingPathComponent(".ollama/models/blobs")
    try fm.createDirectory(at: ollama, withIntermediateDirectories: true)
    try payload.write(to: ollama.appendingPathComponent("sha256-\(hash)"))
    guard ExistingModels.find(catalog, roots: roots.filter { $0.source == "Ollama" })[hash] != nil else { return false }
    // Hugging Face: snapshots/…/a.gguf is a symlink to blobs/<sha256>.
    let hub = home.appendingPathComponent(".cache/huggingface/hub/models--r--a")
    try fm.createDirectory(at: hub.appendingPathComponent("blobs"), withIntermediateDirectories: true)
    try fm.createDirectory(at: hub.appendingPathComponent("snapshots/x"), withIntermediateDirectories: true)
    try payload.write(to: hub.appendingPathComponent("blobs/\(hash)"))
    try fm.createSymbolicLink(atPath: hub.appendingPathComponent("snapshots/x/a.gguf").path, withDestinationPath: "../../blobs/\(hash)")
    guard ExistingModels.find(catalog, roots: roots.filter { $0.source == "Hugging Face" })[hash] != nil else { return false }
    // Adopt instead of download: nothing is missing, no network needed, the source stays.
    let d = ModelDownloader(directory: dir("existing-models"))
    let size = Int64(payload.count)
    guard d.downloadSize(model, existing: found) == ModelDownloadSize(total: size, remaining: 0, existing: size, existingSource: "LM Studio"),
          !d.isInstalled(model) else { return false }
    try await d.download(model, existing: found) { _, _ in }
    let source = lms.appendingPathComponent("a.gguf")
    let sourceData = try Data(contentsOf: source)
    return d.isInstalled(model) && sourceData == payload && d.downloadSize(model)?.remaining == 0
}

// MARK: - Reading

check("Mail (.eml): header, text, attachments") {
    let eml = """
    From: "Hausverwaltung Berger" <info@berger.example>
    To: max@example.com
    Subject: =?utf-8?Q?Nebenkostenabrechnung_2025_f=C3=BCr_Sie?=
    Date: Mon, 6 Apr 2026 09:12:00 +0200
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary="XYZ"

    --XYZ
    Content-Type: text/plain; charset=utf-8
    Content-Transfer-Encoding: quoted-printable

    Hallo, anbei die Abrechnung. Nachzahlung 312,48 =E2=82=AC.
    --XYZ
    Content-Type: application/pdf; name="Abrechnung.pdf"
    Content-Disposition: attachment; filename="Abrechnung.pdf"
    Content-Transfer-Encoding: base64

    JVBERi0=
    --XYZ--
    """
    let url = root.appendingPathComponent("mail.eml"); write(eml, url)
    let doc = TextReader.read(url)
    return doc.headers["subject"] == "Nebenkostenabrechnung 2025 für Sie" && doc.attachments == ["Abrechnung.pdf"]
        && doc.fullText.contains("312,48 €")
}
check("Mail (.eml) in Latin-1: 8bit and quoted-printable without \"KÃ¼ndigung\"") {
    let eightBit = """
    From: Stadtwerke <info@stadtwerke.example>
    Subject: =?iso-8859-1?Q?K=FCndigungsbest=E4tigung?=
    MIME-Version: 1.0
    Content-Type: text/plain; charset=iso-8859-1
    Content-Transfer-Encoding: 8bit

    Kündigung bis 31.12.2026 möglich. Gebühr 5 €.
    """
    // Latin-1 has no €: as in real mails, the data set holds the Windows-1252 byte 0x80.
    var bytes = eightBit.replacingOccurrences(of: "€", with: "").data(using: .isoLatin1)!
    bytes.insert(0x80, at: bytes.lastIndex(of: UInt8(ascii: "."))!)
    let url = root.appendingPathComponent("latin1.eml")
    try bytes.write(to: url)
    let doc = TextReader.read(url)
    let qp = MailParser.parse(Data("""
    Content-Type: multipart/alternative; boundary="b"

    --b
    Content-Type: text/plain; charset="ISO-8859-1"
    Content-Transfer-Encoding: quoted-printable

    K=FCndigung bis 31.12.2026, Gr=FC=DFe
    --b--
    """.utf8))
    return doc.fullText.contains("Kündigung bis 31.12.2026 möglich. Gebühr 5 €.") && !doc.fullText.contains("Ã")
        && doc.headers["subject"] == "Kündigungsbestätigung"
        && qp.body == "Kündigung bis 31.12.2026, Grüße"
}
check("PDF: text per page with page number") {
    let url = root.appendingPathComponent("vertrag.pdf")
    makePDF(contractPages, at: url)
    let doc = TextReader.read(url)
    return doc.pages.count == 2 && doc.pages[1].contains("drei Monaten") && doc.isPaged
}
check("PDF: lines in reading order (PDFKit put the last paragraph line first)") {
    // Same typesetting as in the test corpus (Helvetica 10.5 pt, 60 pt margin); `page.string` returned here
    // "Vermieterin nötig." before "Kleintiere sind erlaubt. …", so the verbatim quote was no longer in the text.
    let url = root.appendingPathComponent("order.pdf")
    var box = CGRect(x: 0, y: 0, width: 595, height: 842)
    let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil)
    let page = "§ 4 Kaution\nDie Mieterin leistet eine Mietsicherheit in Höhe von drei Monatsmieten, also 2.460,00 €. Die Kaution kann in drei gleichen monatlichen Teilzahlungen erbracht werden.\n\n§ 5 Schönheitsreparaturen\nDie Mieterin übernimmt keine Schönheitsreparaturen. Kleine Instandhaltungen bis 100,00 € je Einzelfall trägt die Mieterin, höchstens jedoch 8 % der Jahresgrundmiete.\n\n§ 6 Tierhaltung\nKleintiere sind erlaubt. Für Hunde und Katzen ist die vorherige schriftliche Zustimmung der Vermieterin nötig."
    let attr = NSAttributedString(string: page, attributes: [.font: NSFont(name: "Helvetica", size: 10.5)!])
    CTFrameDraw(CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(attr), CFRange(location: 0, length: 0),
                                         CGPath(rect: box.insetBy(dx: 60, dy: 60), transform: nil), nil), ctx)
    ctx.endPDFPage(); ctx.closePDF()
    let text = TextReader.read(url).fullText
    let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    return flat.contains("Für Hunde und Katzen ist die vorherige schriftliche Zustimmung der Vermieterin nötig.")
        && flat.range(of: "Kleintiere sind erlaubt.")!.lowerBound < flat.range(of: "Vermieterin nötig.")!.lowerBound
        && text.hasPrefix("§ 4 Kaution")
}
check("OCR: columns (label left, amount right) become lines again") {
    // This is how Vision returns a receipt: all labels first, then all amounts (origin bottom left).
    let pieces: [(rect: CGRect, text: String)] = [
        (CGRect(x: 0.1, y: 0.50, width: 0.3, height: 0.02), "SUMME EUR"),
        (CGRect(x: 0.1, y: 0.47, width: 0.2, height: 0.02), "Bar"),
        (CGRect(x: 0.1, y: 0.60, width: 0.4, height: 0.02), "Ibuprofen 400 akut"),
        (CGRect(x: 0.7, y: 0.601, width: 0.1, height: 0.02), "5,95"),
        (CGRect(x: 0.7, y: 0.499, width: 0.1, height: 0.02), "23,45"),
        (CGRect(x: 0.7, y: 0.471, width: 0.1, height: 0.02), "30,00"),
    ]
    let lines = TextReader.lineRows(pieces)
    return lines == ["Ibuprofen 400 akut 5,95", "SUMME EUR 23,45", "Bar 30,00"]
}
check("Models folder via PIPPA_MODELS_DIR") {
    let base = URL(fileURLWithPath: "/x/Support")
    return PiLocalServer.modelsDirectory(base: base).path == "/x/Support/models"
        && PiLocalServer.modelsDirectory(base: base, environment: ["PIPPA_MODELS_DIR": "/scratch/m"]).path == "/scratch/m"
}

// MARK: - Mail and scripts (read only, no real apps)

check("Mail from Apple Mail becomes .eml, which the normal reader understands") {
    let m = MailMessage(subject: "Nebenkosten 2025 – Nachzahlung", sender: "Hausverwaltung Berger <info@berger-hv.de>",
                        date: Date(timeIntervalSince1970: 1_790_000_000), body: "Zahlbar bis 31.10.2026.\nGrüße", attachmentNames: ["Abrechnung.pdf", "Plan \"neu\".pdf"])
    let parsed = MailParser.parse(Data(m.emlText.utf8))
    return parsed.headers["subject"] == "Nebenkosten 2025 – Nachzahlung" && parsed.body == "Zahlbar bis 31.10.2026.\nGrüße"
        && parsed.attachments == ["Abrechnung.pdf", "Plan 'neu'.pdf"] && m.fileName == "Nebenkosten 2025 – Nachzahlung.eml"
}

await checkAsync("Script for reading mail compiles (nothing is sent)") {
    let result = await MainActor.run { IntegrationScripts.compileAll() }
    // Excel is missing from the result when Excel isn't installed (CI); its script is then not compiled.
    return result["Mail"] == true && result["MailReply"] == true && result["MailSearch"] == true && (result["Excel"] ?? true)
        && result["PhotosSearch"] == true && result["PhotosShow"] == true
        && result["Safari"] == true && result["FrontDocument"] == true && (result["Chrome"] ?? true)
        && Set(result.keys).isSubset(of: ["Mail", "MailReply", "MailSearch", "Excel", "PhotosSearch", "PhotosShow", "Safari", "Chrome", "FrontDocument"])
}

// MARK: - Found in real runs

check("Download: file size freshly read (resume otherwise looped forever at the same spot)") {
    let f = root.appendingPathComponent("grow.part")
    try Data(count: 100).write(to: f)
    _ = try f.resourceValues(forKeys: [.fileSizeKey])          // fills the URL cache
    let h = try FileHandle(forWritingTo: f); try h.seekToEnd(); try h.write(contentsOf: Data(count: 50)); try h.close()
    return ModelDownloader.fileSize(f) == 150 && ModelDownloader.fileSize(root.appendingPathComponent("fehlt")) == -1
}

// MARK: - Messages

check("System errors in our own words, never the system's wording") {
    let noAccess = L("I don’t have access to that.", table: "Core"), noSpace = L("There’s no space left.", table: "Core")
    return SystemError.reason(errno: EACCES) == noAccess && SystemError.reason(errno: EPERM) == noAccess
        && SystemError.reason(errno: ENOENT) == L("The file is no longer there.", table: "Core")
        && SystemError.reason(errno: EEXIST) == L("There’s already a file with that name.", table: "Core")
        && SystemError.reason(errno: EXDEV) == L("It’s on a different drive.", table: "Core") && SystemError.reason(errno: ENOSPC) == noSpace
        && SystemError.reason(errno: EIO) == L("That didn’t work just now.", table: "Core")
        && SystemError.reason(CocoaError(.fileWriteNoPermission)) == noAccess
        && SystemError.reason(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError,
                                      userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))])) == noSpace
}

runErrorMessageChecks()
runLocalizationChecks()
runSkillChecks()
await runInferenceChecks()
await runToolChecks()
await runOCRChecks()
await runJournalChecks()
await runDurableJobChecks()
await runFilePreparationChecks()
await runMCPFilePreparationChecks()
await runLetterChecks()
await runSheetChecks()
await runSubscriptionChecks()
await runCalendarChecks()
runCalendarStoreChecks()
await runResultCardChecks()
runPressureChecks()
await runSetupChecks()
await runMCPChecks()
await runNativeReminderChecks()
await runPermissionRepairChecks()
await runDownloadHangChecks()

print(failures == 0 ? "All checks passed." : "\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
