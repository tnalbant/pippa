import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PDFKit
import PippaCore
import UniformTypeIdentifiers

private func pdfText(_ url: URL) -> String { PDFDocument(url: url)?.string ?? "" }

private func renderedPDFInk(_ url: URL, page number: Int) -> Int? {
    let width = 180, height = 240
    guard let document = CGPDFDocument(url as CFURL), let page = document.page(at: number),
          let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
          let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
    let bounds = CGRect(x: 0, y: 0, width: width, height: height)
    context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(bounds)
    context.concatenate(page.getDrawingTransform(.mediaBox, rect: bounds, rotate: 0, preserveAspectRatio: true))
    return withExtendedLifetime((document, context)) {
        context.drawPDFPage(page)
        return (0..<(width * height)).reduce(0) { count, pixel in
            let offset = pixel * 4
            return count + ((data[offset] < 240 || data[offset + 1] < 240 || data[offset + 2] < 240) ? 1 : 0)
        }
    }
}

/// One-answer tools: results only in the results folder, originals unchanged.
func runToolChecks() async {
    // Results go to the check folder instead of ~/Library/Caches (like PIPPA_LOG_DIR).
    let results = dir("tools-results")
    setenv("PIPPA_RESULTS_DIR", results.path, 1)

    let folder = dir("tools")
    let png = folder.appendingPathComponent("Mietvertrag.png")
    let jpeg = folder.appendingPathComponent("Seite 2.jpg")
    let sideways = folder.appendingPathComponent("Quer.jpg")
    let heic = folder.appendingPathComponent("IMG_0001.heic")
    let video = folder.appendingPathComponent("video.mov")
    let letter = folder.appendingPathComponent("Brief.pdf")
    let noise = folder.appendingPathComponent("Rauschen.pdf")
    let locked = folder.appendingPathComponent("Geschützt.pdf")
    let bigPhoto = folder.appendingPathComponent("Groß.jpg")
    let tiny = folder.appendingPathComponent("Punkt.png")

    let text = ["Mietvertrag", "Pippa 4711"]
    ToolFixtures.writeImage(ToolFixtures.textImage(text, width: 1200, height: 1600), type: .png, to: png)
    ToolFixtures.writeImage(ToolFixtures.textImage(text, width: 1200, height: 1600), type: .jpeg, to: jpeg)
    // Shot sideways, EXIF 6: displayed upright.
    ToolFixtures.writeImage(ToolFixtures.textImage(text, width: 1600, height: 1000), type: .jpeg, to: sideways, orientation: 6)
    let hasHEIC = ToolFixtures.canWriteHEIC
        && ToolFixtures.writeImage(ToolFixtures.textImage(text, width: 1600, height: 1000), type: .heic, to: heic, orientation: 6)
    write("kein Video", video)
    makePDF(["Brief Seite eins", "Brief Seite zwei"], at: letter)
    ToolFixtures.noisePDF(pages: 2, at: noise)
    ToolFixtures.lockedPDF(["Geheim Seite eins", "Geheim Seite zwei"], password: "pw", at: locked)
    ToolFixtures.writeImage(ToolFixtures.noiseImage(width: 3000, height: 2000, seed: 42), type: .jpeg, to: bigPhoto, quality: 1.0)
    ToolFixtures.writeImage(ToolFixtures.textImage([], width: 16, height: 16), type: .png, to: tiny)

    var inputs = [png, jpeg, sideways, video, letter, noise, locked, bigPhoto, tiny]
    if hasHEIC { inputs.append(heic) }
    let before = inputs.map { ToolFixtures.identity($0) }

    // MARK: IDs, accepted inputs, texts

    check("Tools: IDs as in the task log, Codable") {
        let ids = ToolID.allCases.map(\.rawValue)
        let data = try JSONEncoder().encode(ToolID.allCases)
        let back = try JSONDecoder().decode([ToolID].self, from: data)
        return ids == ["make-one-pdf", "make-smaller", "as-pdf"] && back == ToolID.allCases
    }
    check("Tools: what they accept") {
        OneAnswerTools.accepts(.makeOnePDF, png) && OneAnswerTools.accepts(.makeOnePDF, letter) && !OneAnswerTools.accepts(.makeOnePDF, video)
            && OneAnswerTools.accepts(.asPDF, jpeg) && !OneAnswerTools.accepts(.asPDF, letter)
            && OneAnswerTools.accepts(.makeSmaller, letter) && OneAnswerTools.accepts(.makeSmaller, noise) && !OneAnswerTools.accepts(.makeSmaller, folder)
    }
    check("Tools: every failure is one sentence, without a path") {
        let failures: [ToolFailure] = [.locked(locked), .wrongPassword(locked), .nothingUsable(skipped: [FileReason(name: "video.mov", why: "x")]),
                                       .nothingUsable(skipped: []), .alreadySmall, .notEnoughSpace, .unreadable(name: "kaputt.pdf")]
        return failures.allSatisfy { f in
            guard let s = f.errorDescription else { return false }
            return !s.isEmpty && !s.contains(folder.path)
        } && ToolFailure.nothingUsable(skipped: [FileReason(name: "video.mov", why: "x")]).errorDescription?.contains("video.mov") == true
    }

    check("Names: German and English, PDFs only \"Combined\", single files with a suffix") {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 10; parts.day = 6; parts.hour = 12
        guard let date = Calendar(identifier: .gregorian).date(from: parts) else { return false }
        let de = Locale(identifier: "de_DE"), en = Locale(identifier: "en_US")
        let pdf = URL(fileURLWithPath: "/tmp/Brief.pdf")
        return ResultNaming.name(for: .makeOnePDF, inputs: [png, jpeg], date: date, locale: de) == "Scans 06.10.2026.pdf"
            && ResultNaming.name(for: .makeOnePDF, inputs: [png, pdf], date: date, locale: en) == "Scans 2026-10-06.pdf"
            && ResultNaming.name(for: .makeOnePDF, inputs: [pdf, pdf], date: date, locale: en) == "Combined 2026-10-06.pdf"
            && ResultNaming.name(for: .makeSmaller, inputs: [pdf], date: date, locale: en) == "Brief (smaller).pdf"
            && ResultNaming.name(for: .makeSmaller, inputs: [pdf], date: date, locale: de) == "Brief (kleiner).pdf"
            && ResultNaming.name(for: .asPDF, inputs: [URL(fileURLWithPath: "/tmp/../a:b.png")], date: date, locale: en) == "a-b.pdf"
    }

    // MARK: Originals and cleanup

    check("Originals: bytes and fingerprint unchanged") {
        let after = inputs.map { ToolFixtures.identity($0) }
        return zip(before, after).allSatisfy { old, new in
            old.sha == new.sha && old.fingerprint != nil && old.fingerprint?.matches(new.fingerprint) == true
        }
    }
    check("Originals: no result in the originals' folder") {
        let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        let allowed = Set(inputs.map(\.lastPathComponent) + [heic.lastPathComponent])
        return !names.isEmpty && Set(names).isSubset(of: allowed)
    }
    check("Results folder: cleanup keeps what is still needed") {
        let kept = try ResultsFolder.fresh(), gone = try ResultsFolder.fresh()
        let keptFile = kept.appendingPathComponent("Scans.pdf")
        write("x", keptFile)
        write("y", gone.appendingPathComponent("Alt.pdf"))
        let removed = ResultsFolder.prune(keeping: [keptFile], maxAge: 60, now: Date().addingTimeInterval(3600))
        return removed >= 1 && fm.fileExists(atPath: keptFile.path) && !fm.fileExists(atPath: gone.path)
            && ResultsFolder.contains(keptFile) && !ResultsFolder.contains(results)
    }
}
